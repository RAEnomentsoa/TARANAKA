import re

from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from comptes.models import CodeProfile
from nutrition.models import StatutPriseEnCharge
from synchro.services import (
    creer_ligne,
    enregistrer_modification,
    journaliser_ligne,
    verifier_version,
    verrouiller,
)

from .models import Origine, Priorite, Referencement, Status

MESSAGE_CODE_UTILISE = "Ce code de référencement existe déjà."
ORDRE_STATUS = list(Status.values)
ESSAIS_GENERATION_CODE = 5


def referencements_visibles(user):
    code = user.profile.code
    referencements = Referencement.objects.select_related("grossesse__user")
    if code == CodeProfile.ADMIN:
        return referencements
    if code == CodeProfile.BENEFICIAIRE:
        return referencements.filter(Q(enfant__mere=user) | Q(grossesse__user=user))
    if code == CodeProfile.ASC:
        lien = Q(asc=user) | Q(enfant__asc=user)
        if user.region_id is not None:
            lien |= Q(
                grossesse__user__region_id=user.region_id,
                grossesse__user__profile__code=CodeProfile.BENEFICIAIRE,
            )
        return referencements.filter(lien)
    if code == CodeProfile.AGENT_CSB and user.csb_id is not None:
        return referencements.filter(csb_id=user.csb_id)
    return referencements.none()


def creer_referencement(donnees, contexte):
    donnees = dict(donnees)
    with transaction.atomic():
        # Lock the parent, so it can't be deleted while the referral is created.
        if donnees["origine"] == Origine.ENFANT:
            enfant = verrouiller(donnees["enfant"])
            referencement = _inserer(donnees, contexte)
            _marquer_refere(enfant, contexte)
        else:
            verrouiller(donnees["grossesse"])
            referencement = _inserer(donnees, contexte)
    return referencement


def referencer_danger(danger, csb, contexte):
    """Referral created automatically when an ASC records a danger sign."""
    return creer_referencement(
        {
            "origine": Origine.GROSSESSE,
            "grossesse": danger.grossesse,
            "asc": contexte.user,
            "csb": csb,
            "priorite": Priorite.URGENTE,
            "motif": f"Signe de danger : {danger.type_danger_grossesse.description}",
        },
        contexte,
    )


def changer_status(referencement, status, version, contexte):
    with transaction.atomic():
        courant = verrouiller(referencement)
        verifier_version(courant, version)
        ancien = courant.status
        _verifier_ordre(ancien, status)
        courant.status = status
        courant.version += 1
        courant.device_id = contexte.device_id
        courant.save(update_fields=["status", "version", "device_id", "updated_at"])
        journaliser_ligne(
            "status_change",
            courant,
            contexte,
            version=courant.version,
            ancien=ancien,
            nouveau=status,
        )
    return courant


def generer_code(asc):
    """R-<first 4 chars of the ASC id>-<MMDD>-<n>.

    The format has no year, so n carries on from the same date of earlier years.
    Soft-deleted rows count, because their codes stay taken.
    """
    prefixe = f"R-{str(asc.pk)[:4]}-{timezone.localdate():%m%d}-"
    codes = Referencement.all_objects.filter(code_unique__startswith=prefixe)
    numeros = [
        int(code.removeprefix(prefixe))
        for code in codes.values_list("code_unique", flat=True)
        if re.fullmatch(r"[0-9]+", code.removeprefix(prefixe))
    ]
    return f"{prefixe}{max(numeros, default=0) + 1:02d}"


def _inserer(donnees, contexte):
    if donnees.get("code_unique"):
        try:
            with transaction.atomic():
                return creer_ligne(Referencement, donnees, contexte)
        except IntegrityError as erreur:
            raise ValidationError({"code_unique": [MESSAGE_CODE_UTILISE]}) from erreur

    # Two phones may generate the same code at once: take the next one.
    for _ in range(ESSAIS_GENERATION_CODE):
        donnees["code_unique"] = generer_code(donnees["asc"])
        try:
            with transaction.atomic():
                return creer_ligne(Referencement, donnees, contexte)
        except IntegrityError:
            continue
    raise ValidationError(
        {"code_unique": ["Impossible de générer un code. Veuillez réessayer."]}
    )


def _marquer_refere(enfant, contexte):
    if enfant.statut_prise_en_charge != StatutPriseEnCharge.REFERE:
        enregistrer_modification(
            enfant,
            {"statut_prise_en_charge": StatutPriseEnCharge.REFERE},
            contexte,
        )


def _verifier_ordre(ancien, nouveau):
    position = ORDRE_STATUS.index(ancien)
    if ORDRE_STATUS.index(nouveau) <= position:
        raise ValidationError(
            {"status": ["Le statut ne peut pas revenir en arrière."]}
        )
    if ORDRE_STATUS.index(nouveau) != position + 1:
        raise ValidationError(
            {"status": [f"Le statut suivant doit être « {ORDRE_STATUS[position + 1]} »."]}
        )
