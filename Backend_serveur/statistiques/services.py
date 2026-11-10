"""Aggregated, anonymous statistics for supervisors (spec §10).

No name, no id of a person or a row ever leaves this module: only counts,
rates and averages, by period and zone. A count from 1 to 4 is hidden
(« < 5 »), and so is a rate or an average computed on fewer than 5 cases.
"""

from datetime import timedelta

from django.conf import settings
from django.db.models import Avg, Count, F, Q
from django.utils import timezone

from nutrition.models import Classification, Mesure
from referencement.models import IssueSortie, Referencement, RendezVous, StatutRendezVous
from referentiel.models import Region

INDICATEURS_COMPTES = (
    "depistages",
    "enfants_depistes",
    "cas_mas",
    "cas_mam",
    "nourrissons_a_risque",
    "referencements",
    "referencements_arrives",
    "rendez_vous_manques",
)
INDICATEURS = (
    *INDICATEURS_COMPTES,
    "taux_arrivee_pct",
    "delai_moyen_arrivee_heures",
    *(f"sorties_{issue}" for issue in IssueSortie.values),
)
MOIS_MAX = 24


def seuil():
    return settings.TARANAKA_SEUIL_PETITS_EFFECTIFS


def calculer(date_debut, date_fin, regions=None):
    """Raw indicators for the period and the regions (None = everywhere)."""
    # A weighing at home by the mother (no ASC) is not a screening (D16).
    mesures = Mesure.objects.filter(
        date_mesure__range=(date_debut, date_fin), asc__isnull=False
    )
    referencements = Referencement.objects.filter(
        date_referencement__date__range=(date_debut, date_fin)
    )
    sorties = Referencement.objects.filter(date_sortie__date__range=(date_debut, date_fin))
    rendez_vous = RendezVous.objects.filter(
        statut=StatutRendezVous.PREVU,
        date_prevue__range=(date_debut, min(date_fin, timezone.localdate() - timedelta(days=1))),
    )
    if regions is not None:
        mesures = mesures.filter(enfant__region__in=regions)
        referencements = referencements.filter(csb__region__in=regions)
        sorties = sorties.filter(csb__region__in=regions)
        rendez_vous = rendez_vous.filter(enfant__region__in=regions)

    enfants = mesures.aggregate(
        depistages=Count("id"),
        enfants_depistes=Count("enfant", distinct=True),
        cas_mas=Count("enfant", distinct=True, filter=Q(classification=Classification.MAS)),
        cas_mam=Count("enfant", distinct=True, filter=Q(classification=Classification.MAM)),
        nourrissons_a_risque=Count(
            "enfant",
            distinct=True,
            filter=Q(classification=Classification.NOURRISSON_A_RISQUE),
        ),
    )
    arrivees = referencements.aggregate(
        referencements=Count("id"),
        referencements_arrives=Count("id", filter=Q(date_reception__isnull=False)),
        delai=Avg(
            F("date_reception") - F("date_referencement"),
            filter=Q(date_reception__isnull=False),
        ),
    )
    issues = dict(
        sorties.exclude(issue_sortie="")
        .values("issue_sortie")
        .annotate(n=Count("id"))
        .values_list("issue_sortie", "n")
    )
    total = arrivees["referencements"]
    arrives = arrivees["referencements_arrives"]
    return {
        **enfants,
        "referencements": total,
        "referencements_arrives": arrives,
        "rendez_vous_manques": rendez_vous.count(),
        "taux_arrivee_pct": round(100 * arrives / total, 1) if total else None,
        "delai_moyen_arrivee_heures": (
            round(arrivees["delai"].total_seconds() / 3600, 1) if arrivees["delai"] else None
        ),
        **{f"sorties_{issue}": issues.get(issue, 0) for issue in IssueSortie.values},
        # Denominators, used for masking only, never shown.
        "_denominateur_taux": total,
        "_denominateur_delai": arrives,
    }


def masquer(brut):
    """Hide small counts and the rates/averages built on them."""
    limite = seuil()
    indicateurs, masques = {}, []
    # Referrals that didn't arrive = referencements − arrives: a difference of
    # 1 to 4 is a small count too, so the arrivals (and the rate, which gives
    # them back) are hidden.
    non_arrives = brut["referencements"] - brut["referencements_arrives"]
    cacher_arrivees = 0 < non_arrives < limite
    for nom in INDICATEURS:
        valeur = brut[nom]
        if nom == "taux_arrivee_pct":
            cache = brut["_denominateur_taux"] < limite
        elif nom == "delai_moyen_arrivee_heures":
            cache = brut["_denominateur_delai"] < limite
        else:
            cache = 0 < valeur < limite
        if nom in ("referencements_arrives", "taux_arrivee_pct") and cacher_arrivees:
            cache = True
        if nom == "taux_arrivee_pct" and 0 < brut["referencements_arrives"] < limite:
            cache = True
        if cache and valeur is not None:
            masques.append(nom)
            valeur = None
        indicateurs[nom] = valeur
    return {"indicateurs": indicateurs, "masques": masques, "_brut": brut}


def suppression_complementaire(resultat):
    """With groups, a hidden value must not come back as total − other groups.

    For each count, if exactly one group is hidden while the total is shown,
    the smallest other group is hidden too (a second unknown). With a single
    group, the total is hidden instead. Groups split the total exactly
    (regions of the zone, months of the period).
    """
    groupes = resultat["groupes"]
    if not groupes:
        return
    total = resultat["total"]
    for nom in INDICATEURS_COMPTES + tuple(f"sorties_{i}" for i in IssueSortie.values):
        caches = [g for g in groupes if nom in g["masques"]]
        if len(caches) != 1 or nom in total["masques"]:
            continue
        autres = [g for g in groupes if nom not in g["masques"]]
        if not autres:
            _cacher(total, nom)
            continue
        _cacher(min(autres, key=lambda g: (g["_brut"][nom] == 0, g["_brut"][nom])), nom)


def _cacher(bloc, nom):
    bloc["indicateurs"][nom] = None
    if nom not in bloc["masques"]:
        bloc["masques"].append(nom)
    if nom == "referencements_arrives":
        _cacher_taux(bloc)


def _cacher_taux(bloc):
    if "taux_arrivee_pct" not in bloc["masques"]:
        bloc["indicateurs"]["taux_arrivee_pct"] = None
        bloc["masques"].append("taux_arrivee_pct")


def mois_de(date_debut, date_fin):
    courant = date_debut.replace(day=1)
    while courant <= date_fin:
        suivant = (courant + timedelta(days=32)).replace(day=1)
        yield max(courant, date_debut), min(suivant - timedelta(days=1), date_fin)
        courant = suivant


def statistiques(date_debut, date_fin, regions, grouper_par=None):
    resultat = {
        "periode": {"date_debut": date_debut, "date_fin": date_fin},
        "seuil_petits_effectifs": seuil(),
        "grouper_par": grouper_par,
        "total": masquer(calculer(date_debut, date_fin, regions)),
        "groupes": [],
    }
    if grouper_par == "region":
        zone = Region.objects.all() if regions is None else regions
        for region in zone.order_by("nom"):
            resultat["groupes"].append(
                {
                    "cle": str(region.pk),
                    "libelle": region.nom,
                    **masquer(calculer(date_debut, date_fin, Region.objects.filter(pk=region.pk))),
                }
            )
    elif grouper_par == "mois":
        for debut, fin in list(mois_de(date_debut, date_fin))[:MOIS_MAX]:
            resultat["groupes"].append(
                {
                    "cle": f"{debut:%Y-%m}",
                    "libelle": f"{debut:%m/%Y}",
                    **masquer(calculer(debut, fin, regions)),
                }
            )
    suppression_complementaire(resultat)
    for bloc in (resultat["total"], *resultat["groupes"]):
        bloc.pop("_brut")
    return resultat


def lignes_csv(resultat):
    """One line per group and indicator; a hidden value is written « <5 »."""
    yield ["groupe", "indicateur", "valeur"]
    blocs = [("total", resultat["total"])] + [
        (groupe["libelle"], groupe) for groupe in resultat["groupes"]
    ]
    for libelle, bloc in blocs:
        for nom in INDICATEURS:
            valeur = bloc["indicateurs"][nom]
            if nom in bloc["masques"]:
                valeur = f"<{resultat['seuil_petits_effectifs']}"
            yield [libelle, nom, "" if valeur is None else valeur]


def periode_par_defaut():
    fin = timezone.localdate()
    return fin - timedelta(days=30), fin

