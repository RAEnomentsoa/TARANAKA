"""Fictional demo data covering the 8 scenarios of spec §13.

Every person, place name and phone number here is made up. Dates are relative
to the day the data is loaded, so the scenarios keep working on any day.

The data is written through the same services as the API, so classification,
audit log and versions are exactly what real use would produce.
"""

import json
from dataclasses import dataclass, field
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from comptes.models import CodeProfile, Profile, User
from config_clinique import services as config_services
from nutrition.models import Enfant, JournalAlimentaire
from nutrition.services import creer_mesure
from referencement.models import Referencement, RendezVous
from referencement.services import changer_status, creer_referencement
from referentiel.models import CSB, Province, Region, TypeDangerGrossesse
from sante_femme.models import Cycle, Grossesse
from synchro.services import Contexte, creer_ligne

APPAREIL = "seed-demo"

# Identifiant, profile, PIN, last name, first name. PINs are for the demo only.
COMPTES = (
    ("admin.demo", CodeProfile.ADMIN, "1111", "Admin", "Démo"),
    ("sup.analamanga", CodeProfile.SUPERVISEUR, "2222", "Rakoto", "Jean"),
    ("sup.national", CodeProfile.SUPERVISEUR, "2223", "Randria", "Mamy"),
    ("ac.rasoa", CodeProfile.ASC, "1234", "Rasoanirina", "Rasoa"),
    ("ac.hery", CodeProfile.ASC, "1235", "Rabearivelo", "Hery"),
    ("ac.antsirabe", CodeProfile.ASC, "1236", "Razafy", "Fidy"),
    ("inf.crenas", CodeProfile.AGENT_CSB, "3333", "Ravelo", "Nirina"),
    ("inf.creni", CodeProfile.AGENT_CSB, "3334", "Andrianina", "Tiana"),
    ("inf.crenam", CodeProfile.AGENT_CSB, "3335", "Rabe", "Lova"),
    ("inf.csb", CodeProfile.AGENT_CSB, "3336", "Rasolofo", "Haja"),
    ("mere.voahangy", CodeProfile.BENEFICIAIRE, "4444", "Rakotomalala", "Voahangy"),
    ("mere.lalao", CodeProfile.BENEFICIAIRE, "4445", "Razanamalala", "Lalao"),
    ("mere.fara", CodeProfile.BENEFICIAIRE, "4446", "Ravaoarisoa", "Fara"),
)
CODES_DEMO = {"mere.voahangy": "VHG444", "mere.lalao": "RZM445", "mere.fara": "FAR446"}


@dataclass
class Demo:
    """What the scenarios need to find again."""

    comptes: dict = field(default_factory=dict)
    centres: dict = field(default_factory=dict)
    regions: dict = field(default_factory=dict)
    enfant_scenario_5: Enfant | None = None
    enfant_scenario_4: Enfant | None = None
    grossesse_scenario_3: Grossesse | None = None
    config_version: int | None = None


def deja_charge():
    return User.objects.filter(identifiant="ac.rasoa").exists()


@transaction.atomic
def charger(sortie=print):
    demo = Demo()
    aujourd_hui = timezone.localdate()
    maintenant = timezone.now()

    _referentiel(demo)
    _comptes(demo)
    _config(demo, sortie)

    asc = demo.comptes["ac.rasoa"]
    contexte_asc = Contexte(user=asc, device_id=APPAREIL)
    contexte_hery = Contexte(user=demo.comptes["ac.hery"], device_id=APPAREIL)
    contexte_antsirabe = Contexte(user=demo.comptes["ac.antsirabe"], device_id=APPAREIL)

    # Scenario 2: 3 cycles of 28-29 days synced by a woman who opted in.
    voahangy = demo.comptes["mere.voahangy"]
    debut = aujourd_hui - timedelta(days=95)
    for duree in (28, 29, 28):
        creer_ligne(
            Cycle,
            {
                "user": voahangy,
                "date_debut": debut,
                "date_fin": debut + timedelta(days=4),
                "intensite": "moyenne",
                "duree_cycle": duree,
                "duree_regle": 5,
            },
            Contexte(user=voahangy, device_id="tel-voahangy"),
        )
        debut += timedelta(days=duree)

    # Scenario 3: last period 84 days ago = 12 weeks + 0 day.
    lalao = demo.comptes["mere.lalao"]
    ddr = aujourd_hui - timedelta(days=84)
    demo.grossesse_scenario_3 = creer_ligne(
        Grossesse,
        {"user": lalao, "ddr": ddr, "dpa": ddr + timedelta(days=280)},
        Contexte(user=lalao, device_id="tel-lalao"),
    )

    # Scenario 4: a 9-month-old child who ate vary + anana + breast milk.
    fara = demo.comptes["mere.fara"]
    demo.enfant_scenario_4 = _enfant(
        contexte_hery,
        "Kanto",
        aujourd_hui - timedelta(days=274),
        "F",
        demo.regions["analamanga"],
        mere=fara,
    )
    creer_ligne(
        JournalAlimentaire,
        {
            "enfant": demo.enfant_scenario_4,
            "date_jour": aujourd_hui,
            "type_allaitement": "mixte",
            "g1_lait_maternel": True,
            "g2_cereales_tubercules": True,
            "g7_fruits_legumes_vit_a": True,
            "notes": "vary, anana, ronono reny",
        },
        Contexte(user=fara, device_id="tel-fara"),
    )

    # Scenario 5: the child the ASC will screen (18 months, no measurement yet).
    demo.enfant_scenario_5 = _enfant(
        contexte_asc,
        "Soa",
        aujourd_hui - timedelta(days=549),
        "F",
        demo.regions["analamanga"],
    )

    _historique(demo, contexte_asc, contexte_hery, contexte_antsirabe, aujourd_hui, maintenant)
    sortie(
        f"Démo chargée : {len(COMPTES)} comptes, "
        f"{Enfant.objects.count()} enfants, {Referencement.objects.count()} référencements."
    )
    return demo


def _referentiel(demo):
    antananarivo = Province.objects.create(nom="Antananarivo")
    demo.regions["analamanga"] = Region.objects.create(nom="Analamanga", province=antananarivo)
    demo.regions["vakinankaratra"] = Region.objects.create(
        nom="Vakinankaratra",
        province=antananarivo,
    )
    analamanga = demo.regions["analamanga"]
    for cle, nom, type_centre, region, tel in (
        ("csb", "CSB2 Ambohitsoa (fictif)", "csb", analamanga, "020 00 000 01"),
        ("crenam", "CRENAM Ambohitsoa (fictif)", "crenam", analamanga, "020 00 000 02"),
        ("crenas", "CRENAS Ambohitsoa (fictif)", "crenas", analamanga, "020 00 000 03"),
        ("creni", "CRENI Hôpital Tanàna (fictif)", "creni", analamanga, "020 00 000 04"),
        (
            "crenas_antsirabe",
            "CRENAS Vohitra (fictif)",
            "crenas",
            demo.regions["vakinankaratra"],
            "020 00 000 05",
        ),
    ):
        demo.centres[cle] = CSB.objects.create(
            name=nom,
            type_centre=type_centre,
            region=region,
            tel=tel,
        )
    config = json.loads(config_services.EXEMPLE.read_text(encoding="utf-8"))
    for signe in config["signes_danger"]["grossesse"]:
        TypeDangerGrossesse.objects.create(code=signe["code"], description=signe["fr"])


def _comptes(demo):
    analamanga = demo.regions["analamanga"]
    regions = {
        "sup.analamanga": analamanga,
        "ac.rasoa": analamanga,
        "ac.hery": analamanga,
        "ac.antsirabe": demo.regions["vakinankaratra"],
        "mere.voahangy": analamanga,
        "mere.lalao": analamanga,
        "mere.fara": analamanga,
    }
    centres = {
        "inf.crenas": demo.centres["crenas"],
        "inf.creni": demo.centres["creni"],
        "inf.crenam": demo.centres["crenam"],
        "inf.csb": demo.centres["csb"],
    }
    for identifiant, code, pin, nom, prenom in COMPTES:
        demo.comptes[identifiant] = User.objects.create_user(
            identifiant,
            pin,
            nom=nom,
            prenom=prenom,
            profile=Profile.objects.get(code=code),
            region=regions.get(identifiant),
            csb=centres.get(identifiant),
            consentement=code == CodeProfile.BENEFICIAIRE,
            # The code a mother shows to her ASC (D16), fixed for the demo.
            code_beneficiaire=CODES_DEMO.get(identifiant),
        )


def _config(demo, sortie):
    config = config_services.config_active()
    if config is None:
        config = config_services.creer_version(
            {
                "libelle": "Exemple de démonstration – À VALIDER",
                "contenu": json.loads(config_services.EXEMPLE.read_text(encoding="utf-8")),
                "notes": "Chargée par charger_demo. Aucune valeur n'est validée.",
            }
        )
        config = config_services.publier(config)
    demo.config_version = config.version
    sortie(f"Configuration clinique v{config.version} publiée (À VALIDER).")


def _enfant(contexte, nom, naissance, sexe, region, mere=None):
    return creer_ligne(
        Enfant,
        {
            "nom": nom,
            "asc": contexte.user,
            "mere": mere,
            "region": region,
            "date_naissance": naissance,
            "sexe": sexe,
        },
        contexte,
    )


def _mesure(contexte, enfant, jours_avant, poids, taille, pb, **extra):
    date_mesure = timezone.localdate() - timedelta(days=jours_avant)
    return creer_mesure(
        {
            "enfant": enfant,
            "date_mesure": date_mesure,
            "poids_kg": Decimal(poids),
            "taille_cm": Decimal(taille),
            "position": "couche" if (date_mesure - enfant.date_naissance).days < 731 else "debout",
            "pb_mm": pb,
            "alerte": "rouge" if pb < 115 else "orange" if pb < 125 else "vert",
            **extra,
        },
        contexte,
    )


def _historique(demo, contexte_asc, contexte_hery, contexte_antsirabe, aujourd_hui, maintenant):
    """Past activity, so the dashboard and the supervisor have numbers to show.

    The CRENAS queue holds no pending referral: scenario 5's referral must come
    first in it (scenario 8).
    """
    analamanga = demo.regions["analamanga"]
    infirmiers = {
        "crenas": Contexte(user=demo.comptes["inf.crenas"], device_id="poste-crenas"),
        "creni": Contexte(user=demo.comptes["inf.creni"], device_id="poste-creni"),
        "crenam": Contexte(user=demo.comptes["inf.crenam"], device_id="poste-crenam"),
    }

    # (name, age in days, weight, length, MUAC, complication, centre, steps, exit)
    cas = (
        ("Rivo", 400, "7.20", "70.0", 108, False, "crenas", 4, "gueri"),
        ("Fanja", 650, "8.30", "76.0", 111, False, "crenas", 3, None),
        ("Tojo", 900, "9.10", "81.0", 113, False, "crenas", 2, None),
        ("Mialy", 300, "6.10", "65.0", 104, True, "creni", 3, None),
        ("Haingo", 1200, "10.20", "88.0", 110, False, "crenas", 4, "abandon"),
        ("Andry", 500, "7.80", "72.0", 112, False, "crenas", 2, None),
        ("Nomena", 700, "8.90", "77.0", 119, False, "crenam", 0, None),
        ("Fitia", 450, "7.90", "71.0", 121, False, "crenam", 2, None),
        ("Lova", 820, "9.30", "80.0", 123, False, None, 0, None),
    )
    for numero, (nom, age, poids, taille, pb, complication, centre, etapes, issue) in enumerate(cas):
        contexte = contexte_asc if numero % 2 == 0 else contexte_hery
        enfant = _enfant(contexte, nom, aujourd_hui - timedelta(days=age), "M" if numero % 2 else "F", analamanga)
        jours = 25 - numero * 2
        mesure = _mesure(
            contexte,
            enfant,
            jours,
            poids,
            taille,
            pb,
            complications_medicales=complication,
        )
        if centre is None:
            continue
        date_ref = maintenant - timedelta(days=jours)
        referencement = creer_referencement(
            {
                "origine": "enfant",
                "enfant": enfant,
                "mesure": mesure,
                "asc": contexte.user,
                "csb": demo.centres[centre],
                "priorite": {"rouge": "urgente", "orange": "haute", "jaune": "normale"}[mesure.urgence],
                "motif": f"{mesure.get_classification_display()} – PB {pb} mm",
                "code_unique": f"TRK-DEMO-{numero:02d}",
                "date_referencement": date_ref,
            },
            contexte,
        )
        statuts = ("recu", "pris_en_charge", "en_suivi")[: min(etapes, 3)]
        for status in statuts:
            referencement = changer_status(
                referencement,
                status,
                referencement.version,
                infirmiers[centre],
            )
        if etapes >= 4 and issue:
            referencement = changer_status(
                referencement,
                "sortie",
                referencement.version,
                infirmiers[centre],
                issue_sortie=issue,
            )
        if etapes:
            Referencement.objects.filter(pk=referencement.pk).update(
                date_reception=date_ref + timedelta(hours=20 + numero * 3),
            )
        if etapes >= 2:
            RendezVous.objects.create(
                enfant=enfant,
                referencement=referencement,
                csb=demo.centres[centre],
                date_prevue=aujourd_hui - timedelta(days=2) if numero == 2 else aujourd_hui + timedelta(days=5),
                motif="Contrôle hebdomadaire",
                device_id=APPAREIL,
            )

    # Normal children: screened, nothing to do until the next check.
    normaux = (
        ("Tsiry", 360, "9.50", "74.0"),
        ("Aina", 540, "10.80", "80.0"),
        ("Mahery", 980, "12.50", "90.0"),
        ("Onja", 1400, "14.50", "100.0"),
    )
    for numero, (nom, age, poids, taille) in enumerate(normaux):
        enfant = _enfant(contexte_hery, nom, aujourd_hui - timedelta(days=age), "M", analamanga)
        _mesure(contexte_hery, enfant, 10 + numero, poids, taille, 140)

    # Another region, for the national supervisor.
    vakinankaratra = demo.regions["vakinankaratra"]
    for numero, (nom, age, pb) in enumerate((("Nirina", 600, 111), ("Bodo", 760, 118))):
        enfant = _enfant(contexte_antsirabe, nom, aujourd_hui - timedelta(days=age), "F", vakinankaratra)
        _mesure(contexte_antsirabe, enfant, 6 + numero, "8.40", "76.0", pb)
