"""WHO 2006 z-scores computed from the LMS values of `reference_oms`.

This is the WHO formula, not a clinical rule. The LMS values are data, loaded
with `python manage.py importer_tables_oms <folder>`. When an indicator's table
is not loaded, the server keeps the phone's value (see `calculer_zscores`).
"""

import math
from decimal import ROUND_HALF_UP, Decimal

from referentiel.models import Indicateur, ReferenceOms

AGE_MAX_JOURS = 1856
SEUIL_LONGUEUR_JOURS = 731
# Weight-based indicators use WHO's restricted method beyond ±3 SD.
INDICATEURS_AJUSTES = {Indicateur.WFA, Indicateur.WFL, Indicateur.WFH}
DEUX_DECIMALES = Decimal("0.01")
UNE_DECIMALE = Decimal("0.1")


def zscore_lms(y, l, m, s, ajuster=False):
    y, l, m, s = float(y), float(l), float(m), float(s)
    if l == 0:
        z = math.log(y / m) / s
    else:
        z = ((y / m) ** l - 1) / (l * s)
    if ajuster and abs(z) > 3:

        def ecart(k):
            return valeur_a_z(l, m, s, k)

        if z > 3:
            z = 3 + (y - ecart(3)) / (ecart(3) - ecart(2))
        else:
            z = -3 + (y - ecart(-3)) / (ecart(-2) - ecart(-3))
    return z


def valeur_a_z(l, m, s, z):
    """The measurement at z standard deviations (WHO's SD curves)."""
    l, m, s = float(l), float(m), float(s)
    if l == 0:
        return m * math.exp(s * z)
    return m * (1 + l * s * z) ** (1 / l)


def _arrondi(z):
    # "+ 0" turns -0.00 into 0.00.
    return Decimal(str(z)).quantize(DEUX_DECIMALES, rounding=ROUND_HALF_UP) + 0


def _zscore(indicateur, sexe, cle, y):
    ligne = ReferenceOms.objects.filter(
        indicateur=indicateur,
        sexe=sexe,
        cle=Decimal(cle).quantize(UNE_DECIMALE, rounding=ROUND_HALF_UP),
    ).first()
    if ligne is None:
        return None
    return _arrondi(
        zscore_lms(
            y,
            ligne.valeur_l,
            ligne.valeur_m,
            ligne.valeur_s,
            ajuster=indicateur in INDICATEURS_AJUSTES,
        )
    )


def tables_chargees():
    return set(ReferenceOms.objects.values_list("indicateur", flat=True).distinct())


def calculer_zscores(sexe, age_jour, poids_kg, taille_corrigee_cm):
    """Return the z-scores the server can compute.

    A key is present only if its WHO table is loaded. Its value is None when
    the child is outside the table (for example under 45 cm).
    """
    chargees = tables_chargees()
    resultats = {}
    dans_l_age = 0 <= age_jour <= AGE_MAX_JOURS
    if Indicateur.WFA in chargees:
        resultats["waz"] = (
            _zscore(Indicateur.WFA, sexe, age_jour, poids_kg) if dans_l_age else None
        )
    if Indicateur.LHFA in chargees:
        resultats["haz"] = (
            _zscore(Indicateur.LHFA, sexe, age_jour, taille_corrigee_cm)
            if dans_l_age
            else None
        )
    indicateur_pt = (
        Indicateur.WFL if age_jour < SEUIL_LONGUEUR_JOURS else Indicateur.WFH
    )
    if indicateur_pt in chargees:
        resultats["whz"] = (
            _zscore(indicateur_pt, sexe, taille_corrigee_cm, poids_kg)
            if dans_l_age
            else None
        )
    return resultats
