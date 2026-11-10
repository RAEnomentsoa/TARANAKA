"""Aggregated, anonymous statistics for supervisors (spec §10).

No name, no id of a person or a row ever leaves this module: only counts,
rates and averages, by period and zone. A count from 1 to 4 is hidden
(« < 5 »), and so is a rate or an average computed on fewer than 5 cases.
"""

from datetime import timedelta

from django.conf import settings
from django.db.models import Avg, Count, F, Q
from django.utils import timezone

from comptes.models import CodeProfile, User
from nutrition.models import Classification, Enfant, JournalAlimentaire, Mesure, VaccinFait
from referencement.models import IssueSortie, Referencement, RendezVous, StatutRendezVous
from referentiel.models import Region
from sante_femme.models import AlimentationFemme, DangerGrossesse, Grossesse, SuiviGrossesse

INDICATEURS_COMPTES = (
    "depistages",
    "enfants_depistes",
    "cas_mas",
    "cas_mam",
    "nourrissons_a_risque",
    "referencements",
    "referencements_arrives",
    "rendez_vous_manques",
    # Connected beneficiaries (D16).
    "beneficiaires_actives",
    "grossesses_suivies",
    "signes_danger",
    "referencements_grossesse",
    "referencements_grossesse_arrives",
    "enfants_vaccines",
)
INDICATEURS = (
    *INDICATEURS_COMPTES,
    "taux_arrivee_pct",
    "taux_arrivee_grossesse_pct",
    "couverture_vaccinale_pct",
    "delai_moyen_arrivee_heures",
    *(f"sorties_{issue}" for issue in IssueSortie.values),
)
# rate: (numerator, denominator). A rate is hidden when its denominator is
# small, and so is a numerator or a difference of 1 to 4: the rate would
# give it back.
TAUX = {
    "taux_arrivee_pct": ("referencements_arrives", "referencements"),
    "taux_arrivee_grossesse_pct": (
        "referencements_grossesse_arrives",
        "referencements_grossesse",
    ),
    "couverture_vaccinale_pct": ("_enfants_vaccin_couverture", "_enfants_age_couverture"),
}
# Vaccine coverage, as the WHO counts it: the third dose of pentavalent
# among the children aged 12 to 23 months.
VACCIN_COUVERTURE = "penta3"
AGE_COUVERTURE_JOURS = (365, 729)
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
    grossesse = referencements.filter(grossesse__isnull=False).aggregate(
        total=Count("id"),
        arrives=Count("id", filter=Q(date_reception__isnull=False)),
    )
    total = arrivees["referencements"]
    arrives = arrivees["referencements_arrives"]
    brut = {
        **enfants,
        **beneficiaires(date_debut, date_fin, regions),
        "referencements": total,
        "referencements_arrives": arrives,
        "referencements_grossesse": grossesse["total"],
        "referencements_grossesse_arrives": grossesse["arrives"],
        "rendez_vous_manques": rendez_vous.count(),
        "delai_moyen_arrivee_heures": (
            round(arrivees["delai"].total_seconds() / 3600, 1) if arrivees["delai"] else None
        ),
        **{f"sorties_{issue}": issues.get(issue, 0) for issue in IssueSortie.values},
        # Denominator, used for masking only, never shown.
        "_denominateur_delai": arrives,
    }
    for nom, (numerateur, denominateur) in TAUX.items():
        n, d = brut[numerateur], brut[denominateur]
        brut[nom] = round(100 * n / d, 1) if d else None
    return brut


def beneficiaires(date_debut, date_fin, regions):
    """The connected beneficiaries' indicators (D16), by the woman's region."""
    femmes = User.objects.filter(profile__code=CodeProfile.BENEFICIAIRE)
    enfants = Enfant.objects.all()
    if regions is not None:
        femmes = femmes.filter(region__in=regions)
        enfants = enfants.filter(region__in=regions)
    periode = {"updated_at__date__range": (date_debut, date_fin)}

    # Active: her file was written to during the period (by her or a worker).
    actives = set()
    for lignes, lien in (
        (Grossesse.objects.filter(**periode), "user_id"),
        (SuiviGrossesse.objects.filter(**periode), "grossesse__user_id"),
        (AlimentationFemme.objects.filter(**periode), "user_id"),
        (Enfant.objects.filter(**periode, mere__isnull=False), "mere_id"),
        (JournalAlimentaire.objects.filter(**periode), "enfant__mere_id"),
        (VaccinFait.objects.filter(**periode), "enfant__mere_id"),
    ):
        actives.update(lignes.values_list(lien, flat=True))
    actives.discard(None)

    # Open at some point of the period: begun before its end, not closed before it.
    grossesses = Grossesse.objects.filter(
        user__in=femmes, created_at__date__lte=date_fin
    ).exclude(terminee=True, updated_at__date__lt=date_debut)
    dangers = DangerGrossesse.objects.filter(
        grossesse__user__in=femmes,
        date_signalement__date__range=(date_debut, date_fin),
    )
    vaccinations = VaccinFait.objects.filter(
        enfant__in=enfants, date_faite__range=(date_debut, date_fin)
    )

    # Coverage on the children followed in the app (a mother with an account):
    # the only ones whose vaccines are recorded.
    plus_jeune, plus_age = AGE_COUVERTURE_JOURS
    age_couverture = enfants.filter(
        mere__isnull=False,
        date_naissance__range=(
            date_fin - timedelta(days=plus_age),
            date_fin - timedelta(days=plus_jeune),
        ),
    )
    vaccines = VaccinFait.objects.filter(
        enfant__in=age_couverture, code=VACCIN_COUVERTURE, date_faite__lte=date_fin
    )
    return {
        "beneficiaires_actives": femmes.filter(pk__in=actives).count(),
        "grossesses_suivies": grossesses.count(),
        "signes_danger": dangers.count(),
        "enfants_vaccines": vaccinations.values("enfant").distinct().count(),
        "_enfants_age_couverture": age_couverture.count(),
        "_enfants_vaccin_couverture": vaccines.values("enfant").distinct().count(),
    }


def masquer(brut):
    """Hide small counts and the rates/averages built on them."""
    limite = seuil()

    def petit(valeur):
        return 0 < valeur < limite

    caches = {nom for nom in INDICATEURS_COMPTES if petit(brut[nom])}
    caches.update(f"sorties_{i}" for i in IssueSortie.values if petit(brut[f"sorties_{i}"]))
    if brut["_denominateur_delai"] < limite:
        caches.add("delai_moyen_arrivee_heures")
    for nom, (numerateur, denominateur) in TAUX.items():
        n, d = brut[numerateur], brut[denominateur]
        # "Not arrived" = total - arrived: a difference of 1 to 4 is a small
        # count too, so the arrivals (and the rate, which gives them back)
        # are hidden.
        if petit(d - n):
            caches.update((nom, numerateur))
        if d < limite or petit(n):
            caches.add(nom)
    # The children's referrals are the others: total - pregnancy.
    if petit(brut["referencements"] - brut["referencements_grossesse"]):
        caches.update(("referencements_grossesse", "taux_arrivee_grossesse_pct"))
    if petit(brut["referencements_arrives"] - brut["referencements_grossesse_arrives"]):
        caches.update(("referencements_grossesse_arrives", "taux_arrivee_grossesse_pct"))

    indicateurs, masques = {}, []
    for nom in INDICATEURS:
        valeur = brut[nom]
        if nom in caches and valeur is not None:
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
    # A rate gives its numerator or its denominator back.
    for taux, (numerateur, denominateur) in TAUX.items():
        if nom in (numerateur, denominateur) and taux not in bloc["masques"]:
            bloc["indicateurs"][taux] = None
            bloc["masques"].append(taux)


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

