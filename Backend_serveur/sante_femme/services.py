from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.db.models import Exists, OuterRef
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from comptes.models import CodeProfile
from referencement.models import Referencement
from referencement.services import referencer_danger
from referentiel.models import CSB
from synchro.exceptions import LigneProtegee
from synchro.services import creer_ligne, lignes, supprimer_ligne, verrouiller

from .models import Cycle, DangerGrossesse, Grossesse

AVERTISSEMENT_CSB_MANQUANT = "Référencement non créé : CSB manquant"
AVERTISSEMENT_CSB_INCONNU = "Référencement non créé : CSB inconnu"
AVERTISSEMENT_ERREUR = "Référencement non créé : erreur d'enregistrement"


def cycles_visibles(user, inclure_supprimes=False):
    cycles = lignes(Cycle, inclure_supprimes)
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return cycles
    if code == CodeProfile.BENEFICIAIRE:
        return cycles.filter(user=user)
    return cycles.none()


def grossesses_visibles(user, inclure_supprimes=False):
    code = user.profile.code
    grossesses = lignes(Grossesse, inclure_supprimes).select_related("user")
    if code == CodeProfile.ADMIN:
        return grossesses
    if code == CodeProfile.BENEFICIAIRE:
        return grossesses.filter(user=user)
    # Guard against filter(region_id=None), which would match every empty region.
    if code == CodeProfile.ASC and user.region_id is not None:
        return grossesses.filter(
            user__region_id=user.region_id,
            user__profile__code=CodeProfile.BENEFICIAIRE,
        )
    if code == CodeProfile.AGENT_CSB and user.csb_id is not None:
        return grossesses.filter(
            pk__in=Referencement.objects.filter(
                csb_id=user.csb_id,
                grossesse__isnull=False,
            ).values("grossesse_id")
        )
    return grossesses.none()


def dangers_visibles(user, inclure_supprimes=False):
    return lignes(DangerGrossesse, inclure_supprimes).filter(
        grossesse__in=grossesses_visibles(user, inclure_supprimes)
    )


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
        dangers = DangerGrossesse.objects.select_for_update(of=("self",))
        for danger in dangers.filter(grossesse=courante):
            supprimer_ligne(danger, contexte)
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
