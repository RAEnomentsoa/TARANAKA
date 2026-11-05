import re
from datetime import timedelta

from django.db import IntegrityError, transaction
from django.db.models import Case, IntegerField, OuterRef, Q, Subquery, Value, When
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError

from comptes.models import CodeProfile
from config_clinique.services import config_active
from nutrition.models import Mesure, StatutPriseEnCharge
from nutrition.services import enfants_visibles
from synchro.services import (
    creer_ligne,
    lignes,
    enregistrer_modification,
    journaliser_ligne,
    verifier_version,
    verrouiller,
)

from .models import (
    Origine,
    Priorite,
    Referencement,
    RendezVous,
    Status,
    StatutRendezVous,
)

MESSAGE_CODE_UTILISE = "Ce code de référencement existe déjà."
ORDRE_STATUS = list(Status.values)
ESSAIS_GENERATION_CODE = 5

# One step at a time. A discharge (cured, transferred, died…) can happen as
# soon as the child has arrived, without waiting for every step.
TRANSITIONS = {
    Status.ENVOYE: (Status.RECU,),
    Status.RECU: (Status.PRIS_EN_CHARGE, Status.SORTIE),
    Status.PRIS_EN_CHARGE: (Status.EN_SUIVI, Status.SORTIE),
    Status.EN_SUIVI: (Status.SORTIE,),
    Status.SORTIE: (),
}
DATE_PAR_STATUS = {
    Status.RECU: "date_reception",
    Status.PRIS_EN_CHARGE: "date_prise_en_charge",
    Status.EN_SUIVI: "date_suivi",
    Status.SORTIE: "date_sortie",
}
STATUT_ENFANT_PAR_STATUS = {
    Status.PRIS_EN_CHARGE: StatutPriseEnCharge.PRIS_EN_CHARGE,
    Status.EN_SUIVI: StatutPriseEnCharge.SUIVI,
}
# Every exit outcome has a child status of the same name.
URGENCE_PAR_PRIORITE = {
    Priorite.URGENTE: "rouge",
    Priorite.HAUTE: "orange",
    Priorite.NORMALE: "jaune",
}
MESSAGE_SORTIE_RESERVEE = (
    "Seul un professionnel du centre destinataire peut enregistrer une sortie."
)


def referencements_visibles(user, inclure_supprimes=False):
    code = user.profile.code
    referencements = lignes(Referencement, inclure_supprimes).select_related(
        "grossesse__user",
        "asc",
    )
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


def changer_status(referencement, status, version, contexte, issue_sortie=""):
    """Move the case one step forward (spec §7) and update the child's status."""
    if status == Status.SORTIE and contexte.user.profile.code != CodeProfile.AGENT_CSB:
        raise PermissionDenied(MESSAGE_SORTIE_RESERVEE)
    if status == Status.SORTIE and not issue_sortie:
        raise ValidationError({"issue_sortie": ["L'issue de sortie est obligatoire."]})
    if status != Status.SORTIE and issue_sortie:
        raise ValidationError(
            {"issue_sortie": ["L'issue ne s'indique que pour une sortie."]}
        )
    with transaction.atomic():
        # Same locking order as creer_referencement: the child first.
        enfant = verrouiller(referencement.enfant) if referencement.enfant_id else None
        courant = verrouiller(referencement)
        verifier_version(courant, version)
        ancien = courant.status
        _verifier_ordre(ancien, status)
        courant.status = status
        champs = ["status", "version", "device_id", "updated_at"]
        if status in DATE_PAR_STATUS:
            setattr(courant, DATE_PAR_STATUS[status], timezone.now())
            champs.append(DATE_PAR_STATUS[status])
        if status == Status.SORTIE:
            courant.issue_sortie = issue_sortie
            champs.append("issue_sortie")
        courant.version += 1
        courant.device_id = contexte.device_id
        courant.save(update_fields=champs)
        journaliser_ligne(
            "status_change",
            courant,
            contexte,
            version=courant.version,
            ancien=ancien,
            nouveau=status,
            **({"issue_sortie": issue_sortie} if issue_sortie else {}),
        )
        if enfant is not None:
            _suivre_enfant(enfant, status, issue_sortie, contexte)
    return courant


def urgence(referencement):
    return URGENCE_PAR_PRIORITE.get(referencement.priorite)


def delai_non_arrivee():
    """The delay after which a referral that hasn't arrived needs a reminder."""
    config = config_active()
    if config is None:
        return None
    return timedelta(hours=config.contenu["malnutrition"]["suivi"]["delai_alerte_non_arrivee_heures"])


def en_retard(referencement, cache=None):
    cache = {} if cache is None else cache
    if "delai" not in cache:
        cache["delai"] = delai_non_arrivee()
    delai = cache["delai"]
    return bool(
        delai is not None
        and referencement.status == Status.ENVOYE
        and referencement.date_referencement < timezone.now() - delai
    )


def non_arrives(referencements, delai=None):
    delai = delai if delai is not None else delai_non_arrivee()
    if delai is None:
        return referencements.none()
    return referencements.filter(
        status=Status.ENVOYE,
        date_referencement__lt=timezone.now() - delai,
    )


def trier_par_urgence(referencements):
    """Red first, then orange, then yellow; oldest first inside each (spec §10)."""
    rang = Case(
        *(When(priorite=p, then=Value(i)) for i, p in enumerate(Priorite.values)),
        default=Value(len(Priorite.values)),
        output_field=IntegerField(),
    )
    return referencements.annotate(rang_urgence=rang).order_by(
        "rang_urgence",
        "date_referencement",
        "id",
    )


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


def _suivre_enfant(enfant, status, issue_sortie, contexte):
    nouveau = STATUT_ENFANT_PAR_STATUS.get(status)
    if status == Status.SORTIE:
        nouveau = issue_sortie
    if nouveau and enfant.statut_prise_en_charge != nouveau:
        enregistrer_modification(
            enfant,
            {"statut_prise_en_charge": nouveau},
            contexte,
            motif="status_referencement",
        )


def _verifier_ordre(ancien, nouveau):
    if ORDRE_STATUS.index(nouveau) <= ORDRE_STATUS.index(ancien):
        raise ValidationError(
            {"status": ["Le statut ne peut pas revenir en arrière."]}
        )
    suivants = TRANSITIONS[ancien]
    if nouveau not in suivants:
        raise ValidationError(
            {"status": [f"Le statut suivant doit être « {suivants[0]} »."]}
        )


def rendez_vous_visibles(user, inclure_supprimes=False):
    return lignes(RendezVous, inclure_supprimes).filter(
        enfant__in=enfants_visibles(user, inclure_supprimes)
    )


def rendez_vous_manques(rendez_vous):
    """Still « prévu » after its date (spec §7: rendez-vous manqués)."""
    return rendez_vous.filter(
        statut=StatutRendezVous.PREVU,
        date_prevue__lt=timezone.localdate(),
    )


def enfants_a_revoir(user):
    """Children whose latest measurement asks for a check that is now due."""
    derniere = Mesure.objects.filter(enfant=OuterRef("pk")).order_by(
        "-date_mesure",
        "-created_at",
    )
    return (
        enfants_visibles(user)
        .exclude(statut_prise_en_charge=StatutPriseEnCharge.DECEDE)
        .annotate(
            prochain_controle=Subquery(derniere.values("date_prochain_controle")[:1]),
            derniere_classification=Subquery(derniere.values("classification")[:1]),
        )
        .filter(prochain_controle__lte=timezone.localdate())
        .order_by("prochain_controle", "nom")
    )


def relances(user):
    """What the ASC (or the centre) has to follow up (spec §7, §10)."""
    delai = delai_non_arrivee()
    return {
        "delai_non_arrivee_heures": (
            int(delai.total_seconds() // 3600) if delai is not None else None
        ),
        "referencements_non_arrives": trier_par_urgence(
            non_arrives(referencements_visibles(user), delai)
        ),
        "rendez_vous_manques": rendez_vous_manques(rendez_vous_visibles(user)).order_by(
            "date_prevue"
        ),
        "enfants_a_revoir": enfants_a_revoir(user),
    }
