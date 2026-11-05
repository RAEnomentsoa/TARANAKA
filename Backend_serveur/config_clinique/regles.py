"""Rule engine for the clinical configuration.

The code only knows *how* to read a rule. *What* the rules say (thresholds,
destinations, delays) comes from the published configuration (spec §11).

A rule is a JSON object, for example:

    {
      "code": "mas",
      "age_mois_min": 6,
      "si_un_des": [
        {"champ": "oedemes_bilateraux", "dans": ["+", "++", "+++"]},
        {"champ": "whz", "inferieur_a": -3},
        {"champ": "pb_mm", "inferieur_a": 115}
      ]
    }

A condition on a missing value (None) is false, so an unknown z-score never
triggers a rule by itself.
"""

from decimal import Decimal, InvalidOperation

CHAMPS_MESURE = (
    "age_mois",
    "oedemes_bilateraux",
    "whz",
    "waz",
    "haz",
    "pb_mm",
    "signes_danger",
    "complications_medicales",
    "appetit",
    "difficultes_allaitement",
    "classification",
)


def _nombre(valeur):
    try:
        return Decimal(str(valeur))
    except (InvalidOperation, ValueError):
        return None


def _comparer(valeur, reference, test):
    a, b = _nombre(valeur), _nombre(reference)
    if a is None or b is None:
        return False
    return test(a, b)


OPERATEURS = {
    "inferieur_a": lambda v, r: _comparer(v, r, lambda a, b: a < b),
    "inferieur_ou_egal_a": lambda v, r: _comparer(v, r, lambda a, b: a <= b),
    "superieur_a": lambda v, r: _comparer(v, r, lambda a, b: a > b),
    "superieur_ou_egal_a": lambda v, r: _comparer(v, r, lambda a, b: a >= b),
    "egal": lambda v, r: v == r,
    "dans": lambda v, r: v in r,
}


def condition_vraie(condition, valeurs):
    valeur = valeurs.get(condition["champ"])
    if "non_vide" in condition:
        return bool(valeur) == condition["non_vide"]
    if valeur is None:
        return False
    for operateur, test in OPERATEURS.items():
        if operateur in condition:
            return test(valeur, condition[operateur])
    return False


def regle_applicable(regle, valeurs):
    age = valeurs.get("age_mois")
    if "age_mois_min" in regle and (age is None or age < regle["age_mois_min"]):
        return False
    if "age_mois_max" in regle and (age is None or age > regle["age_mois_max"]):
        return False
    classifications = regle.get("si_classification")
    if classifications is not None and valeurs.get("classification") not in classifications:
        return False
    un_des = regle.get("si_un_des")
    if un_des is not None and not any(condition_vraie(c, valeurs) for c in un_des):
        return False
    tous = regle.get("si_tous")
    if tous is not None and not all(condition_vraie(c, valeurs) for c in tous):
        return False
    return True


def premiere_regle(regles, valeurs):
    """Rules are read in order: the first one that applies wins."""
    return next((r for r in regles if regle_applicable(r, valeurs)), None)


def classer(malnutrition, valeurs):
    """MAS / MAM / normal / at-risk infant, or None outside the age range."""
    age = valeurs.get("age_mois")
    if age is None or not (
        malnutrition.get("age_min_mois", 0) <= age <= malnutrition["age_max_mois"]
    ):
        return None
    classification = malnutrition["classification"]
    regle = premiere_regle(classification["regles"], valeurs)
    return regle["code"] if regle else classification["par_defaut"]


def orienter(malnutrition, valeurs):
    """The orientation rule for a classified child, or None."""
    if not valeurs.get("classification"):
        return None
    return premiere_regle(malnutrition["orientation"]["regles"], valeurs)
