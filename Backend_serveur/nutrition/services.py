from decimal import Decimal

from django.db import transaction
from rest_framework.exceptions import ValidationError

from comptes.models import CodeProfile
from referencement.models import Referencement
from synchro.exceptions import LigneProtegee
from synchro.services import (
    creer_ligne,
    enregistrer_modification,
    supprimer_ligne,
    verifier_version,
    verrouiller,
)

from .classification import classer_mesure
from .models import Enfant, Mesure, Position
from .zscores import calculer_zscores

JOURS_PAR_MOIS = Decimal("30.4375")
SEUIL_POSITION_JOURS = 731
CORRECTION_TAILLE_CM = Decimal("0.7")
AGE_MIN_PB_MOIS = 6
AGE_MAX_PB_MOIS = 59
MESSAGE_PB_AGE = "Le périmètre brachial ne peut être saisi qu'entre 6 et 59 mois."
MESSAGE_DATE_AVANT_NAISSANCE = (
    "La date de mesure ne peut pas être avant la date de naissance."
)
MESSAGE_NAISSANCE_INCOMPATIBLE = (
    "Cette date de naissance rend une mesure déjà enregistrée invalide."
)


def enfants_visibles(user):
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return Enfant.objects.all()
    if code == CodeProfile.BENEFICIAIRE:
        return Enfant.objects.filter(mere=user)
    if code == CodeProfile.ASC:
        return Enfant.objects.filter(asc=user)
    # Guard against filter(csb_id=None), which would match rows without a CSB.
    if code == CodeProfile.AGENT_CSB and user.csb_id is not None:
        return Enfant.objects.filter(
            pk__in=Referencement.objects.filter(
                csb_id=user.csb_id,
                enfant__isnull=False,
            ).values("enfant_id")
        )
    return Enfant.objects.none()


def mesures_visibles(user):
    return Mesure.objects.filter(enfant__in=enfants_visibles(user))


def calculer_champs_mesure(enfant, date_mesure, taille_cm, position, pb_mm):
    """Fields the server works out itself, whatever the phone says."""
    age_jour = (date_mesure - enfant.date_naissance).days
    if age_jour < 0:
        raise ValidationError({"date_mesure": [MESSAGE_DATE_AVANT_NAISSANCE]})
    age_mois = int(Decimal(age_jour) / JOURS_PAR_MOIS)
    if pb_mm is not None and not AGE_MIN_PB_MOIS <= age_mois <= AGE_MAX_PB_MOIS:
        raise ValidationError({"pb_mm": [MESSAGE_PB_AGE]})

    return {
        "age_jour": age_jour,
        "age_mois": age_mois,
        "taille_corrigee_cm": _corriger_taille(taille_cm, position, age_jour),
    }


CHAMPS_CALCUL = (
    "date_mesure",
    "poids_kg",
    "taille_cm",
    "position",
    "pb_mm",
    "oedemes_bilateraux",
    "signes_danger",
    "complications_medicales",
    "appetit",
    "difficultes_allaitement",
    "waz",
    "haz",
    "whz",
    "flag_aberrant",
)


def calculer_mesure(enfant, valeurs):
    """Every field the server works out: age, length, z-scores, classification.

    A z-score is taken from the WHO tables when they are loaded, otherwise the
    phone's value is kept. The classification follows the published config.
    """
    calculs = calculer_champs_mesure(
        enfant,
        valeurs["date_mesure"],
        valeurs["taille_cm"],
        valeurs["position"],
        valeurs.get("pb_mm"),
    )
    calculs.update(
        calculer_zscores(
            enfant.sexe,
            calculs["age_jour"],
            valeurs["poids_kg"],
            calculs["taille_corrigee_cm"],
        )
    )
    calculs.update(classer_mesure({**valeurs, **calculs}))
    return calculs


def creer_mesure(donnees, contexte):
    donnees = dict(donnees)
    with transaction.atomic():
        # Lock the child, so its birth date can't change during the calculation.
        enfant = verrouiller(donnees["enfant"])
        donnees.setdefault("asc", enfant.asc)
        donnees.update(calculer_mesure(enfant, donnees))
        return creer_ligne(Mesure, donnees, contexte)


def modifier_mesure(mesure, donnees, contexte):
    with transaction.atomic():
        # Same locking order as modifier_enfant: the child first.
        enfant = verrouiller(mesure.enfant)
        courante = verrouiller(mesure)
        verifier_version(courante, donnees["version"])

        valeurs = {
            champ: donnees.get(champ, getattr(courante, champ))
            for champ in CHAMPS_CALCUL
        }
        calculs = calculer_mesure(enfant, valeurs)
        return enregistrer_modification(courante, {**donnees, **calculs}, contexte)


def modifier_enfant(enfant, donnees, contexte):
    with transaction.atomic():
        courant = verrouiller(enfant)
        verifier_version(courant, donnees["version"])
        ancienne_naissance = courant.date_naissance
        courant = enregistrer_modification(courant, donnees, contexte)
        if courant.date_naissance != ancienne_naissance:
            _recalculer_mesures(courant, contexte)
        return courant


def supprimer_enfant(enfant, contexte):
    with transaction.atomic():
        courant = verrouiller(enfant)
        if Referencement.objects.filter(enfant=courant).exists():
            raise LigneProtegee(
                "Cet enfant a un référencement et ne peut pas être supprimé."
            )
        mesures = Mesure.objects.select_for_update(of=("self",))
        for mesure in mesures.filter(enfant=courant):
            supprimer_ligne(mesure, contexte)
        return supprimer_ligne(courant, contexte)


def _corriger_taille(taille_cm, position, age_jour):
    if age_jour < SEUIL_POSITION_JOURS and position == Position.DEBOUT:
        return taille_cm + CORRECTION_TAILLE_CM
    if age_jour >= SEUIL_POSITION_JOURS and position == Position.COUCHE:
        return taille_cm - CORRECTION_TAILLE_CM
    return taille_cm


def _recalculer_mesures(enfant, contexte):
    mesures = Mesure.objects.select_for_update(of=("self",))
    for mesure in mesures.filter(enfant=enfant):
        try:
            calculs = calculer_mesure(
                enfant,
                {champ: getattr(mesure, champ) for champ in CHAMPS_CALCUL},
            )
        except ValidationError as erreur:
            raise ValidationError(
                {"date_naissance": [MESSAGE_NAISSANCE_INCOMPATIBLE]}
            ) from erreur
        enregistrer_modification(
            mesure,
            calculs,
            contexte,
            motif="date_naissance",
        )
