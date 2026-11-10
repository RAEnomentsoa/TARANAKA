"""Rights of the data subject, loi malgache n° 2014-038 (spec §8).

- Access: every piece of data the server holds about the person.
- Erasure: personal data is deleted or anonymised. Records that a health
  facility must keep (a referral and what it is about) are kept, but no longer
  point to an identifiable person.

Deleted rows are soft-deleted, so the other phones learn about it through the
usual /api/sync/pull/. Nothing here writes health values to the audit log.
"""

import uuid

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from nutrition.models import (
    ConsultationNutritionnelle,
    Enfant,
    JournalAlimentaire,
    Mesure,
    Tetee,
    VaccinFait,
)
from nutrition.serializers import (
    ConsultationSerializer,
    EnfantSerializer,
    JournalAlimentaireSerializer,
    MesureSerializer,
    TeteeSerializer,
    VaccinFaitSerializer,
)
from nutrition.services import (
    consultations_visibles,
    enfants_visibles,
    journaux_visibles,
    mesures_visibles,
    tetees_visibles,
    vaccins_visibles,
)
from referencement.models import Referencement, RendezVous
from referencement.serializers import ReferencementSerializer, RendezVousSerializer
from referencement.services import referencements_visibles, rendez_vous_visibles
from sante_femme.models import (
    AlimentationFemme,
    ContactSoin,
    Cycle,
    CycleJour,
    DangerGrossesse,
    Grossesse,
    MouvementBebe,
    MouvementEvenement,
    SuiviGrossesse,
)
from sante_femme.serializers import (
    AlimentationFemmeSerializer,
    ContactSoinSerializer,
    CycleJourSerializer,
    CycleSerializer,
    DangerGrossesseSerializer,
    GrossesseSerializer,
    MouvementBebeSerializer,
    MouvementEvenementSerializer,
    SuiviGrossesseSerializer,
)
from sante_femme.services import (
    alimentations_visibles,
    contacts_visibles,
    cycle_jours_visibles,
    cycles_visibles,
    dangers_visibles,
    grossesses_visibles,
    mouvements_evenements_visibles,
    mouvements_visibles,
    suivis_grossesse_visibles,
)
from synchro.models import ConflitSync, HistoriqueVersion, JournalAudit, OperationSync
from synchro.services import enregistrer_modification, supprimer_ligne

from .models import CodeProfile, User
from .services import _revoquer_tokens

LIMITE_JOURNAL = 500
NOM_EFFACE = "Effacé"
NOM_ENFANT_EFFACE = "Enfant effacé"

SECTIONS_SANTE = (
    ("cycles", cycles_visibles, CycleSerializer),
    ("cycle_jours", cycle_jours_visibles, CycleJourSerializer),
    ("alimentations", alimentations_visibles, AlimentationFemmeSerializer),
    ("grossesses", grossesses_visibles, GrossesseSerializer),
    ("signes_danger", dangers_visibles, DangerGrossesseSerializer),
    ("contacts_soin", contacts_visibles, ContactSoinSerializer),
    ("suivis_grossesse", suivis_grossesse_visibles, SuiviGrossesseSerializer),
    ("mouvements_bebe", mouvements_visibles, MouvementBebeSerializer),
    ("mouvements_evenements", mouvements_evenements_visibles, MouvementEvenementSerializer),
    ("enfants", enfants_visibles, EnfantSerializer),
    ("mesures", mesures_visibles, MesureSerializer),
    ("journaux_alimentaires", journaux_visibles, JournalAlimentaireSerializer),
    ("vaccins", vaccins_visibles, VaccinFaitSerializer),
    ("tetees", tetees_visibles, TeteeSerializer),
    ("referencements", referencements_visibles, ReferencementSerializer),
    ("rendez_vous", rendez_vous_visibles, RendezVousSerializer),
    ("consultations", consultations_visibles, ConsultationSerializer),
)


class EffacementImpossible(Exception):
    pass


def exporter(cible, requete):
    """Everything about `cible`. Health sections only for a beneficiary: for a
    health worker, the records they wrote are about their patients, not them."""
    contexte = {"request": requete}
    donnees = {
        "genere_le": timezone.now(),
        "compte": {
            "id": cible.pk,
            "identifiant": cible.identifiant,
            "nom": cible.nom,
            "prenom": cible.prenom,
            "email": cible.email,
            "phone": cible.phone,
            "consentement": cible.consentement,
            "code_beneficiaire": cible.code_beneficiaire,
            "partage_cycle": cible.partage_cycle,
            "profile": cible.profile.code,
            "region_id": cible.region_id,
            "csb_id": cible.csb_id,
            "date_creation": cible.date_creation,
            "last_login": cible.last_login,
            "totp_active": cible.totp_active,
            "efface_le": cible.efface_le,
        },
    }
    if cible.profile.code == CodeProfile.BENEFICIAIRE:
        for nom, visibles, serializer in SECTIONS_SANTE:
            donnees[nom] = serializer(
                visibles(cible).order_by("created_at"),
                many=True,
                context=contexte,
            ).data
    donnees["journal"] = list(
        JournalAudit.objects.filter(Q(user=cible) | Q(ligne_id=cible.pk))
        .order_by("-date_creation")
        .values("date_creation", "action", "table_nom")[:LIMITE_JOURNAL]
    )
    return donnees


def journaliser_acces(cible, contexte):
    JournalAudit.objects.create(
        user=contexte.user,
        action="acces_donnees",
        table_nom="utilisateur",
        ligne_id=cible.pk,
        details={"ip": contexte.ip, "device_id": contexte.device_id},
    )


@transaction.atomic
def effacer(cible, contexte, inclure_enfants=False):
    """Erase a beneficiary's personal data. Return what was done, as counts."""
    cible = User.objects.select_for_update(of=("self",)).get(pk=cible.pk)
    if cible.profile.code != CodeProfile.BENEFICIAIRE:
        raise EffacementImpossible(
            "L'effacement concerne les comptes de bénéficiaires. "
            "Un compte professionnel se désactive (traçabilité des actes)."
        )
    if cible.efface_le is not None:
        raise EffacementImpossible("Les données de ce compte sont déjà effacées.")

    resume = {
        "cycles_supprimes": 0,
        "grossesses_supprimees": 0,
        "grossesses_conservees_anonymes": 0,
        "enfants_detaches": 0,
        "enfants_supprimes": 0,
        "enfants_conserves_anonymes": 0,
    }
    lignes_effacees = []

    # Intimate data, only ever on her phone and here: deleted for good.
    for modele in (Cycle, CycleJour, AlimentationFemme):
        ids = list(modele.all_objects.filter(user=cible).values_list("pk", flat=True))
        modele.all_objects.filter(pk__in=ids).delete()
        lignes_effacees += ids
        if modele is Cycle:
            resume["cycles_supprimes"] = len(ids)

    for grossesse in Grossesse.objects.filter(user=cible):
        if Referencement.all_objects.filter(grossesse=grossesse).exists():
            resume["grossesses_conservees_anonymes"] += 1
            continue
        for modele in (
            DangerGrossesse,
            ContactSoin,
            SuiviGrossesse,
            MouvementBebe,
            MouvementEvenement,
        ):
            for ligne in modele.objects.filter(grossesse=grossesse):
                supprimer_ligne(ligne, contexte)
                lignes_effacees.append(ligne.pk)
        supprimer_ligne(grossesse, contexte)
        lignes_effacees.append(grossesse.pk)
        resume["grossesses_supprimees"] += 1

    for enfant in Enfant.objects.select_for_update(of=("self",)).filter(mere=cible):
        modifications = {"mere": None, "grossesse": None}
        if not inclure_enfants:
            enregistrer_modification(enfant, modifications, contexte, motif="effacement")
            resume["enfants_detaches"] += 1
            continue
        modifications["nom"] = NOM_ENFANT_EFFACE
        enfant = enregistrer_modification(enfant, modifications, contexte, motif="effacement")
        if Referencement.all_objects.filter(enfant=enfant).exists():
            resume["enfants_conserves_anonymes"] += 1
            continue
        for modele in (
            Mesure,
            JournalAlimentaire,
            VaccinFait,
            Tetee,
            RendezVous,
            ConsultationNutritionnelle,
        ):
            for ligne in modele.objects.filter(enfant=enfant):
                supprimer_ligne(ligne, contexte)
                lignes_effacees.append(ligne.pk)
        supprimer_ligne(enfant, contexte)
        lignes_effacees.append(enfant.pk)
        resume["enfants_supprimes"] += 1

    # Copies of her rows kept by the sync machinery.
    OperationSync.objects.filter(Q(user=cible) | Q(ligne_id__in=lignes_effacees)).delete()
    HistoriqueVersion.objects.filter(ligne_id__in=lignes_effacees).delete()
    ConflitSync.objects.filter(Q(user=cible) | Q(ligne_id__in=lignes_effacees)).delete()

    # The follow-ups (D16) stay: the workers' phones must receive the deletions.
    _anonymiser(cible)
    JournalAudit.objects.create(
        user=contexte.user,
        action="effacement_donnees",
        table_nom="utilisateur",
        ligne_id=cible.pk,
        details={
            "ip": contexte.ip,
            "device_id": contexte.device_id,
            "demande_par": "personne" if contexte.user.pk == cible.pk else "admin",
            "inclure_enfants": inclure_enfants,
            **resume,
        },
    )
    return resume


def _anonymiser(user):
    user.identifiant = f"efface-{uuid.uuid4().hex[:12]}"
    user.nom = NOM_EFFACE
    user.prenom = NOM_EFFACE
    user.email = ""
    user.phone = ""
    user.consentement = False
    user.code_beneficiaire = None
    user.partage_cycle = False
    user.is_active = False
    # The region stays: alone it identifies nobody, and the ASCs of the region
    # see her rows through it, so their phones receive the deletions.
    user.csb = None
    user.totp_secret = ""
    user.totp_active = False
    user.totp_dernier_pas = None
    user.tentatives_echouees = 0
    user.bloque_jusqu_a = None
    user.efface_le = timezone.now()
    user.set_unusable_password()
    user.save()
    _revoquer_tokens(user)
