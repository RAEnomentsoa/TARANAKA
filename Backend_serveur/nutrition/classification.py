"""Malnutrition classification and orientation of a measurement (spec §7).

Every threshold and destination comes from the published clinical config
(`config_clinique`). Without a published config, nothing is classified.
"""

from datetime import timedelta
from decimal import Decimal

from config_clinique import regles
from config_clinique.services import config_active

CHAMPS_ZSCORE = ("waz", "haz", "whz")
SANS_CLASSIFICATION = {
    "classification": "",
    "orientation_centre": "",
    "urgence": "",
    "date_prochain_controle": None,
    "config_version": None,
}


def hors_plausibilite(valeurs, plausibilite):
    """True if a z-score is outside the config's plausible range (« Vérifiez la mesure »)."""
    z_min = Decimal(str(plausibilite["z_min"]))
    z_max = Decimal(str(plausibilite["z_max"]))
    return any(
        valeurs.get(champ) is not None
        and not z_min <= Decimal(str(valeurs[champ])) <= z_max
        for champ in CHAMPS_ZSCORE
    )


def classer_mesure(valeurs, config=None):
    """valeurs holds the measurement fields, with age_mois and the z-scores.

    Return the classification fields, plus flag_aberrant (the phone's flag is
    kept, the server can only add one).
    """
    config = config or config_active()
    flag = bool(valeurs.get("flag_aberrant", False))
    if config is None:
        return {**SANS_CLASSIFICATION, "flag_aberrant": flag}

    malnutrition = config.contenu["malnutrition"]
    flag = flag or hors_plausibilite(valeurs, malnutrition["plausibilite"])
    classification = regles.classer(malnutrition, valeurs) or ""
    orientation = (
        regles.orienter(malnutrition, {**valeurs, "classification": classification})
        or {}
    )
    jours = orientation.get("prochain_controle_jours")
    return {
        "classification": classification,
        "orientation_centre": orientation.get("centre") or "",
        "urgence": orientation.get("urgence") or "",
        "date_prochain_controle": (
            valeurs["date_mesure"] + timedelta(days=jours) if jours is not None else None
        ),
        "config_version": config.version,
        "flag_aberrant": flag,
    }
