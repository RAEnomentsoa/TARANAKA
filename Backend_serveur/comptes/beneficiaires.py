"""A beneficiary's file, as a health worker sees it (D16).

The worker finds her in the list of their zone, or by the code she shows
them (from any region: she may visit another centre). Opening her file makes
the worker follow her, so their next pulls carry her data. The cycle is in
the file only if she shares it (option a).
"""

from django.db.models import BooleanField, Count, Exists, OuterRef, Q, Value

from nutrition.serializers import (
    EnfantSerializer,
    JournalAlimentaireSerializer,
    MesureSerializer,
    TeteeSerializer,
    VaccinFaitSerializer,
)
from nutrition.services import (
    enfants_visibles,
    journaux_visibles,
    mesures_visibles,
    tetees_visibles,
    vaccins_visibles,
)
from referencement.serializers import ReferencementSerializer, RendezVousSerializer
from referencement.services import referencements_visibles, rendez_vous_visibles
from sante_femme.models import Grossesse
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

from .models import CodeProfile, SuiviBeneficiaire, User
from .services import beneficiaires_suivies, journaliser, normaliser_code, suivre, zone_beneficiaires

# (section, rows visible to the worker, link to the woman, serializer)
SECTIONS = (
    ("grossesses", grossesses_visibles, "user", GrossesseSerializer),
    ("signes_danger", dangers_visibles, "grossesse__user", DangerGrossesseSerializer),
    ("contacts_soin", contacts_visibles, "grossesse__user", ContactSoinSerializer),
    ("suivis_grossesse", suivis_grossesse_visibles, "grossesse__user", SuiviGrossesseSerializer),
    ("mouvements_bebe", mouvements_visibles, "grossesse__user", MouvementBebeSerializer),
    (
        "mouvements_evenements",
        mouvements_evenements_visibles,
        "grossesse__user",
        MouvementEvenementSerializer,
    ),
    ("alimentations", alimentations_visibles, "user", AlimentationFemmeSerializer),
    ("cycles", cycles_visibles, "user", CycleSerializer),
    ("cycle_jours", cycle_jours_visibles, "user", CycleJourSerializer),
    ("enfants", enfants_visibles, "mere", EnfantSerializer),
    ("mesures", mesures_visibles, "enfant__mere", MesureSerializer),
    ("journaux_alimentaires", journaux_visibles, "enfant__mere", JournalAlimentaireSerializer),
    ("vaccins", vaccins_visibles, "enfant__mere", VaccinFaitSerializer),
    ("tetees", tetees_visibles, "enfant__mere", TeteeSerializer),
    ("rendez_vous", rendez_vous_visibles, "enfant__mere", RendezVousSerializer),
)


def accessibles(agent):
    """The beneficiaries whose file agent may open: their zone and the women
    they already follow."""
    if agent.profile.code == CodeProfile.ADMIN:
        return zone_beneficiaires(agent)
    return zone_beneficiaires(agent) | User.objects.filter(
        pk__in=beneficiaires_suivies(agent),
        efface_le__isnull=True,
    )


def annoter(beneficiaires, agent):
    """What the list shows: is she followed, pregnant, how many children."""
    grossesse_en_cours = Grossesse.objects.filter(
        user=OuterRef("pk"), terminee=False, deleted_at__isnull=True
    )
    if agent.profile.code == CodeProfile.ADMIN:
        suivie = Value(False, output_field=BooleanField())
    else:
        suivie = Exists(
            SuiviBeneficiaire.objects.filter(agent=agent, beneficiaire=OuterRef("pk"))
        )
    return beneficiaires.annotate(
        suivie=suivie,
        grossesse_en_cours=Exists(grossesse_en_cours),
        nb_enfants=Count("enfants", filter=Q(enfants__deleted_at__isnull=True), distinct=True),
    )


def rechercher(beneficiaires, texte):
    texte = (texte or "").strip()
    if not texte:
        return beneficiaires
    condition = (
        Q(prenom__icontains=texte)
        | Q(nom__icontains=texte)
        | Q(phone__icontains=texte)
        | Q(identifiant__iexact=texte)
    )
    code = normaliser_code(texte)
    if code:
        condition |= Q(code_beneficiaire=code)
    return beneficiaires.filter(condition)


def par_code(code):
    code = normaliser_code(code)
    if not code:
        return None
    return User.objects.filter(
        profile__code=CodeProfile.BENEFICIAIRE,
        efface_le__isnull=True,
        is_active=True,
        code_beneficiaire=code,
    ).first()


def ouvrir(femme, agent, contexte, requete, motif):
    """Follow her, log the access, and return her file."""
    suivre(agent, femme, contexte, motif)
    journaliser(
        "consultation_dossier",
        contexte.user,
        contexte.ip,
        cible=femme,
        device_id=contexte.device_id,
        motif=motif,
    )
    return dossier(femme, agent, requete)


def dossier(femme, agent, requete):
    contexte = {"request": requete}
    resultat = {
        "beneficiaire": {
            "id": femme.pk,
            "identifiant": femme.identifiant,
            "prenom": femme.prenom,
            "nom": femme.nom,
            "phone": femme.phone,
            "region_id": femme.region_id,
            "code_beneficiaire": femme.code_beneficiaire,
            "partage_cycle": femme.partage_cycle,
        }
    }
    for nom, visibles, lien, serializer in SECTIONS:
        lignes = visibles(agent).filter(**{lien: femme}).order_by("created_at")
        resultat[nom] = serializer(lignes, many=True, context=contexte).data
    referencements = referencements_visibles(agent).filter(
        Q(grossesse__user=femme) | Q(enfant__mere=femme)
    )
    resultat["referencements"] = ReferencementSerializer(
        referencements.order_by("created_at"), many=True, context=contexte
    ).data
    return resultat
