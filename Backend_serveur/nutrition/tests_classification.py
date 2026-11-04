"""Classification tests: WHO z-scores, MAS / MAM / normal, orientation.

The thresholds come from the sample config (À VALIDER). These tests check that
the server applies the config faithfully, not that the values are clinically
right: that is for the health authorities to validate.
"""

import math
from datetime import date, timedelta
from decimal import Decimal

from django.test import SimpleTestCase

from config_clinique import regles
from nutrition.classification import classer_mesure
from nutrition.models import Mesure
from nutrition.zscores import zscore_lms
from referentiel.models import ReferenceOms
from synchro.outils_tests import CONFIG_EXEMPLE, BaseApiTest

MALNUTRITION = CONFIG_EXEMPLE["malnutrition"]

# Rows of the WHO 2006 tables: LMS values, and the SD weights WHO publishes in
# its simplified z-score tables (kg, rounded to 0.1).
OMS_GARCON_LONGUEUR_75 = {
    "lms": ("-0.3521", "9.5032", "0.08295"),
    "sd": {-3: 7.5, -2: 8.1, -1: 8.8, 0: 9.5, 1: 10.3, 2: 11.3, 3: 12.3},
}
OMS_FILLE_HAUTEUR_80 = {
    "lms": ("-0.3833", "10.2332", "0.08932"),
    "sd": {-3: 7.9, -2: 8.6, -1: 9.4, 0: 10.2, 1: 11.2, 2: 12.3, 3: 13.6},
}
OMS_GARCON_POIDS_AGE_18_MOIS = {
    "lms": ("0.0211", "10.9385", "0.11119"),
    "sd": {-3: 7.8, -2: 8.8, -1: 9.8, 0: 10.9, 1: 12.2, 2: 13.7, 3: 15.3},
}


def poids_a_k_ecarts(l, m, s, k):
    l, m, s = float(l), float(m), float(s)
    return m * (1 + l * s * k) ** (1 / l)


class ZscoreOmsTest(SimpleTestCase):
    """Reference cases from the WHO 2006 tables."""

    def test_les_ecarts_types_publies_par_l_oms_sont_retrouves(self):
        for nom, table in (
            ("garçon P/L 75 cm", OMS_GARCON_LONGUEUR_75),
            ("fille P/T 80 cm", OMS_FILLE_HAUTEUR_80),
            ("garçon P/A 18 mois", OMS_GARCON_POIDS_AGE_18_MOIS),
        ):
            for k, publie in table["sd"].items():
                with self.subTest(table=nom, k=k):
                    self.assertAlmostEqual(
                        poids_a_k_ecarts(*table["lms"], k),
                        publie,
                        delta=0.05 + 1e-9,
                    )

    def test_poids_median_donne_zero(self):
        l, m, s = OMS_GARCON_LONGUEUR_75["lms"]
        self.assertAlmostEqual(zscore_lms(m, l, m, s, ajuster=True), 0, places=6)

    def test_valeurs_publiees_donnent_le_bon_ecart(self):
        for k, publie in OMS_GARCON_LONGUEUR_75["sd"].items():
            with self.subTest(k=k):
                z = zscore_lms(publie, *OMS_GARCON_LONGUEUR_75["lms"], ajuster=True)
                self.assertAlmostEqual(z, k, delta=0.15)

    def test_methode_restreinte_de_l_oms_au_dela_de_3(self):
        l, m, s = OMS_GARCON_LONGUEUR_75["lms"]
        sd3neg = poids_a_k_ecarts(l, m, s, -3)
        sd2neg = poids_a_k_ecarts(l, m, s, -2)
        poids = sd3neg - 0.5 * (sd2neg - sd3neg)
        self.assertAlmostEqual(zscore_lms(poids, l, m, s, ajuster=True), -3.5, places=6)
        brut = zscore_lms(poids, l, m, s, ajuster=False)
        self.assertNotAlmostEqual(brut, -3.5, places=2)

    def test_l_nul(self):
        self.assertAlmostEqual(
            zscore_lms(math.e * 10, 0, 10, 0.5),
            2.0,
            places=6,
        )


def valeurs(age_mois=18, **extra):
    return {
        "age_mois": age_mois,
        "date_mesure": date(2026, 11, 4),
        "oedemes_bilateraux": "aucun",
        "whz": None,
        "waz": None,
        "haz": None,
        "pb_mm": None,
        "signes_danger": [],
        "complications_medicales": False,
        "appetit": "non_teste",
        "difficultes_allaitement": False,
        **extra,
    }


def classer(**extra):
    v = valeurs(**extra)
    classification = regles.classer(MALNUTRITION, v)
    orientation = regles.orienter(MALNUTRITION, {**v, "classification": classification})
    return (
        classification,
        orientation and orientation["centre"],
        orientation and orientation["urgence"],
    )


class ClassificationTest(SimpleTestCase):
    """Spec §7 table, applied through the sample config."""

    def test_scenario_5_pb_112_sans_oedeme_ni_complication(self):
        self.assertEqual(classer(age_mois=18, pb_mm=112), ("mas", "crenas", "orange"))

    def test_mas_avec_complication_va_au_creni(self):
        cas = {
            "complication": {"complications_medicales": True},
            "signe de danger": {"signes_danger": ["convulsions"]},
            "perte d'appétit": {"appetit": "mauvais"},
        }
        for nom, extra in cas.items():
            with self.subTest(cas=nom):
                self.assertEqual(
                    classer(pb_mm=110, **extra),
                    ("mas", "creni", "rouge"),
                )

    def test_appetit_bon_reste_au_crenas(self):
        self.assertEqual(classer(pb_mm=110, appetit="bon")[1], "crenas")

    def test_oedemes_bilateraux_donnent_une_mas(self):
        for grade in ("+", "++", "+++"):
            with self.subTest(grade=grade):
                self.assertEqual(
                    classer(oedemes_bilateraux=grade, pb_mm=140, whz=Decimal("0.5"))[0],
                    "mas",
                )

    def test_limites_du_perimetre_brachial(self):
        cas = [(114, "mas"), (115, "mam"), (124, "mam"), (125, "normal")]
        for pb, attendu in cas:
            with self.subTest(pb_mm=pb):
                self.assertEqual(classer(pb_mm=pb)[0], attendu)

    def test_limites_du_poids_pour_taille(self):
        cas = [
            ("-3.01", "mas"),
            ("-3.00", "mam"),
            ("-2.01", "mam"),
            ("-2.00", "normal"),
            ("1.20", "normal"),
        ]
        for whz, attendu in cas:
            with self.subTest(whz=whz):
                self.assertEqual(classer(whz=Decimal(whz))[0], attendu)

    def test_le_critere_le_plus_grave_l_emporte(self):
        self.assertEqual(classer(whz=Decimal("-2.5"), pb_mm=110)[0], "mas")
        self.assertEqual(classer(whz=Decimal("-3.5"), pb_mm=130)[0], "mas")

    def test_orientation_mam_et_normal(self):
        self.assertEqual(classer(pb_mm=120), ("mam", "crenam", "jaune"))
        self.assertEqual(classer(pb_mm=140), ("normal", None, None))

    def test_sans_mesure_utilisable_l_enfant_est_normal(self):
        self.assertEqual(classer()[0], "normal")

    def test_nourrisson_de_moins_de_6_mois(self):
        self.assertEqual(
            classer(age_mois=4, waz=Decimal("-2.4")),
            ("nourrisson_a_risque", "csb", "orange"),
        )
        self.assertEqual(
            classer(age_mois=4, difficultes_allaitement=True)[0],
            "nourrisson_a_risque",
        )
        self.assertEqual(
            classer(age_mois=5, oedemes_bilateraux="+")[0],
            "nourrisson_a_risque",
        )
        self.assertEqual(classer(age_mois=4)[0], "normal")

    def test_nourrisson_avec_signe_de_danger_va_au_creni(self):
        self.assertEqual(
            classer(age_mois=2, signes_danger=["ne_peut_pas_boire"]),
            ("nourrisson_a_risque", "creni", "rouge"),
        )

    def test_hors_tranche_d_age(self):
        self.assertEqual(classer(age_mois=60, pb_mm=100), (None, None, None))

    def test_seuils_lus_dans_la_configuration(self):
        """No threshold in the code: a new config changes the result."""
        malnutrition = {
            **MALNUTRITION,
            "classification": {
                "par_defaut": "normal",
                "regles": [
                    {
                        "code": "mas",
                        "age_mois_min": 6,
                        "si_un_des": [{"champ": "pb_mm", "inferieur_a": 120}],
                    }
                ],
            },
        }
        self.assertEqual(regles.classer(malnutrition, valeurs(pb_mm=118)), "mas")
        self.assertEqual(regles.classer(MALNUTRITION, valeurs(pb_mm=118)), "mam")

    def test_plausibilite(self):
        class Config:
            version = 1
            contenu = CONFIG_EXEMPLE

        resultat = classer_mesure(valeurs(whz=Decimal("-5.2")), Config)
        self.assertTrue(resultat["flag_aberrant"])
        resultat = classer_mesure(valeurs(whz=Decimal("-4.9")), Config)
        self.assertFalse(resultat["flag_aberrant"])

    def test_prochain_controle(self):
        class Config:
            version = 3
            contenu = CONFIG_EXEMPLE

        resultat = classer_mesure(valeurs(pb_mm=140), Config)
        self.assertEqual(resultat["date_prochain_controle"], date(2026, 11, 4) + timedelta(days=90))
        self.assertEqual(resultat["config_version"], 3)


class ClassificationApiTest(BaseApiTest):
    """The server classifies every measurement it receives."""

    def setUp(self):
        super().setUp()
        self.ligne = self.enfant(date_naissance=date(2025, 5, 4), sexe="M")
        self.comme(self.asc)

    def creer(self, **extra):
        donnees = {
            "date_mesure": "2026-11-04",
            "poids_kg": "8.10",
            "taille_cm": "75.0",
            "position": "couche",
            "pb_mm": 112,
            "alerte": "orange",
            **extra,
        }
        return self.client.post(
            f"/api/children/{self.ligne.pk}/measurements/",
            donnees,
            format="json",
        )

    def test_sans_configuration_publiee_rien_n_est_classe(self):
        reponse = self.creer()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["classification"], "")
        self.assertIsNone(reponse.data["config_version"])

    def test_scenario_5(self):
        config = self.publier_config()
        reponse = self.creer(classification="normal", urgence="jaune")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["age_mois"], 18)
        self.assertEqual(reponse.data["classification"], "mas")
        self.assertEqual(reponse.data["orientation_centre"], "crenas")
        self.assertEqual(reponse.data["urgence"], "orange")
        self.assertEqual(reponse.data["config_version"], config.version)
        self.assertEqual(reponse.data["date_prochain_controle"], "2026-11-11")

    def test_signes_de_danger_et_complications(self):
        self.publier_config()
        reponse = self.creer(signes_danger=["convulsions"])
        self.assertEqual(reponse.data["orientation_centre"], "creni")
        self.assertEqual(reponse.data["signes_danger"], ["convulsions"])

    def test_modification_reclassee(self):
        self.publier_config()
        mesure_id = self.creer().data["id"]
        reponse = self.client.patch(
            f"/api/measurements/{mesure_id}/",
            {"pb_mm": 130, "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["classification"], "normal")

    def test_zscores_calcules_par_le_serveur_avec_les_tables_oms(self):
        self.publier_config()
        l, m, s = OMS_GARCON_LONGUEUR_75["lms"]
        ReferenceOms.objects.create(
            indicateur="wfl",
            sexe="M",
            cle=Decimal("75.0"),
            valeur_l=Decimal(l),
            valeur_m=Decimal(m),
            valeur_s=Decimal(s),
            mesure_type="L",
        )
        # 7.2 kg at 75 cm: below WHO's -3 SD (7.5 kg) for boys.
        reponse = self.creer(poids_kg="7.20", pb_mm=130, whz="0.00")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        whz = Decimal(reponse.data["whz"])
        self.assertLess(whz, Decimal("-3"))
        self.assertEqual(reponse.data["classification"], "mas")
        # The tables for weight-for-age are not loaded: the phone's value is kept.
        self.assertIsNone(reponse.data["waz"])
        self.assertEqual(Mesure.objects.get().whz, whz)

    def test_le_drapeau_du_serveur_disparait_apres_correction(self):
        self.publier_config()
        l, m, s = OMS_GARCON_LONGUEUR_75["lms"]
        ReferenceOms.objects.create(
            indicateur="wfl",
            sexe="M",
            cle=Decimal("75.0"),
            valeur_l=Decimal(l),
            valeur_m=Decimal(m),
            valeur_s=Decimal(s),
        )
        # 4.0 kg at 75 cm: far below -5 SD, a typo.
        creee = self.creer(poids_kg="4.00", pb_mm=130)
        self.assertTrue(creee.data["flag_aberrant"])
        corrigee = self.client.patch(
            f"/api/measurements/{creee.data['id']}/",
            {"poids_kg": "9.40", "version": 1},
            format="json",
        )
        self.assertEqual(corrigee.status_code, 200, corrigee.data)
        self.assertFalse(corrigee.data["flag_aberrant"])

    def test_hors_table_oms_le_score_est_vide(self):
        ReferenceOms.objects.create(
            indicateur="wfl",
            sexe="M",
            cle=Decimal("75.0"),
            valeur_l=Decimal("-0.3521"),
            valeur_m=Decimal("9.5032"),
            valeur_s=Decimal("0.08295"),
        )
        reponse = self.creer(taille_cm="76.0", whz="-1.00")
        self.assertIsNone(reponse.data["whz"])

    def test_signes_danger_doit_etre_une_liste(self):
        reponse = self.creer(signes_danger="convulsions")
        self.assertEqual(reponse.status_code, 400)
