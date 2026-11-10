from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.db.models import Exists, OuterRef, Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from comptes.models import CodeProfile
from comptes.services import beneficiaires_suivies
from referencement.models import Referencement
from referencement.services import referencer_danger
from referentiel.models import CSB
from synchro.exceptions import LigneProtegee
from synchro.services import creer_ligne, lignes, supprimer_ligne, verrouiller

from .models import (
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

PROFILS_SOIGNANTS = (CodeProfile.ASC, CodeProfile.AGENT_CSB)

AVERTISSEMENT_CSB_MANQUANT = "Référencement non créé : CSB manquant"
AVERTISSEMENT_CSB_INCONNU = "Référencement non créé : CSB inconnu"
AVERTISSEMENT_ERREUR = "Référencement non créé : erreur d'enregistrement"


def _du_cycle(modele, user, inclure_supprimes):
    """D16 option (a): a health worker sees the cycle only of the women they
    follow who chose to share it."""
    lignes_cycle = lignes(modele, inclure_supprimes)
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return lignes_cycle
    if code == CodeProfile.BENEFICIAIRE:
        return lignes_cycle.filter(user=user)
    if code in PROFILS_SOIGNANTS:
        return lignes_cycle.filter(
            user__in=beneficiaires_suivies(user),
            user__partage_cycle=True,
        )
    return lignes_cycle.none()


def cycles_visibles(user, inclure_supprimes=False):
    return _du_cycle(Cycle, user, inclure_supprimes)


def cycle_jours_visibles(user, inclure_supprimes=False):
    return _du_cycle(CycleJour, user, inclure_supprimes)


def alimentations_visibles(user, inclure_supprimes=False):
    alimentations = lignes(AlimentationFemme, inclure_supprimes)
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return alimentations
    if code == CodeProfile.BENEFICIAIRE:
        return alimentations.filter(user=user)
    if code in PROFILS_SOIGNANTS:
        return alimentations.filter(user__in=beneficiaires_suivies(user))
    return alimentations.none()


def grossesses_visibles(user, inclure_supprimes=False):
    code = user.profile.code
    grossesses = lignes(Grossesse, inclure_supprimes).select_related("user")
    if code == CodeProfile.ADMIN:
        return grossesses
    if code == CodeProfile.BENEFICIAIRE:
        return grossesses.filter(user=user)
    # D16: a health worker sees the pregnancies of the women they follow.
    suivies = Q(user__in=beneficiaires_suivies(user))
    if code == CodeProfile.ASC:
        return grossesses.filter(suivies)
    # Guard against filter(csb_id=None), which would match rows without a CSB.
    if code == CodeProfile.AGENT_CSB:
        if user.csb_id is None:
            return grossesses.filter(suivies)
        return grossesses.filter(
            suivies
            | Q(
                pk__in=Referencement.objects.filter(
                    csb_id=user.csb_id,
                    grossesse__isnull=False,
                ).values("grossesse_id")
            )
        )
    return grossesses.none()


def _de_grossesse(modele):
    def visibles(user, inclure_supprimes=False):
        return lignes(modele, inclure_supprimes).filter(
            grossesse__in=grossesses_visibles(user, inclure_supprimes)
        )

    return visibles


dangers_visibles = _de_grossesse(DangerGrossesse)
contacts_visibles = _de_grossesse(ContactSoin)
suivis_grossesse_visibles = _de_grossesse(SuiviGrossesse)
mouvements_visibles = _de_grossesse(MouvementBebe)
mouvements_evenements_visibles = _de_grossesse(MouvementEvenement)


def filtrer_dangers_sans_referencement(grossesses, valeur):
    """Pregnancies with a danger sign recorded after their latest referral.

    An older referral doesn't count: the new sign still needs someone's attention.
    """
    referencement_ulterieur = Referencement.objects.filter(
        grossesse=OuterRef("grossesse"),
        created_at__gte=OuterRef("created_at"),
    )
    danger_sans_suite = DangerGrossesse.objects.filter(
        ~Exists(referencement_ulterieur),
        grossesse=OuterRef("pk"),
    )
    condition = Exists(danger_sans_suite)
    return grossesses.filter(condition if valeur else ~condition)


def signaler_danger(grossesse, donnees, contexte):
    """Save the danger sign whatever happens to its referral.

    Return the sign, the referral or None, and a warning or None.
    """
    donnees = dict(donnees)
    csb_id = donnees.pop("csb_id", None)
    donnees.setdefault("date_signalement", timezone.now())
    with transaction.atomic():
        danger = creer_ligne(
            DangerGrossesse,
            {**donnees, "grossesse": grossesse},
            contexte,
        )
        if contexte.user.profile.code != CodeProfile.ASC:
            return danger, None, None
        referencement, avertissement = _referencer(danger, csb_id, contexte)
    return danger, referencement, avertissement


def supprimer_grossesse(grossesse, contexte):
    with transaction.atomic():
        courante = verrouiller(grossesse)
        if Referencement.objects.filter(grossesse=courante).exists():
            raise LigneProtegee(
                "Cette grossesse a un référencement et ne peut pas être supprimée."
            )
        for modele in (
            DangerGrossesse,
            ContactSoin,
            SuiviGrossesse,
            MouvementBebe,
            MouvementEvenement,
        ):
            lignes_liees = modele.objects.select_for_update(of=("self",))
            for ligne in lignes_liees.filter(grossesse=courante):
                supprimer_ligne(ligne, contexte)
        return supprimer_ligne(courante, contexte)


def _referencer(danger, csb_id, contexte):
    if csb_id is None:
        return None, AVERTISSEMENT_CSB_MANQUANT
    csb = CSB.objects.filter(pk=csb_id).first()
    if csb is None:
        return None, AVERTISSEMENT_CSB_INCONNU
    try:
        with transaction.atomic():
            return referencer_danger(danger, csb, contexte), None
    except (DjangoValidationError, IntegrityError, ValidationError):
        return None, AVERTISSEMENT_ERREUR
