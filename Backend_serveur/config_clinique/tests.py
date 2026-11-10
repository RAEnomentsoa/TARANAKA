from io import StringIO

from django.core.management import call_command
from django.test import override_settings

from comptes.models import CodeProfile
from config_clinique.models import ConfigurationClinique
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

URL = "/api/clinical-config/"


class ConfigurationCliniqueTest(BaseApiTest):
    def creer(self, contenu=None, **extra):
        self.comme(self.admin)
        return self.client.post(
            URL,
            {"libelle": "Essai", "contenu": contenu or self.config_exemple(), **extra},
            format="json",
        )

    def test_admin_cree_un_brouillon(self):
        reponse = self.creer()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["version"], 1)
        self.assertEqual(reponse.data["statut"], "brouillon")
        self.assertEqual(reponse.data["statut_validation"], "a_valider")
        self.assertEqual(self.creer().data["version"], 2)
        self.assertTrue(JournalAudit.objects.filter(action="config_creee").exists())

    def test_contenu_verifie_par_le_schema(self):
        contenu = self.config_exemple()
        contenu["malnutrition"]["classification"]["regles"][1]["si_un_des"][0] = {
            "champ": "pb",
            "inferieur_a": 115,
        }
        reponse = self.creer(contenu)
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("contenu", reponse.data)

    def test_signes_danger_exiges_comme_par_le_telephone(self):
        # The phone never installs a version without these lists
        # (ClinicalConfig.problems): the server must not publish one.
        for retirer in ("signes_danger", "enfant", "grossesse"):
            with self.subTest(retirer=retirer):
                contenu = self.config_exemple()
                if retirer == "signes_danger":
                    del contenu["signes_danger"]
                else:
                    del contenu["signes_danger"][retirer]
                reponse = self.creer(contenu)
                self.assertEqual(reponse.status_code, 400)
                self.assertIn("contenu", reponse.data)

    def test_seul_l_admin_ecrit(self):
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        for user in (self.asc, self.agent, self.femme, superviseur):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                reponse = self.client.post(
                    URL,
                    {"libelle": "x", "contenu": self.config_exemple()},
                    format="json",
                )
                self.assertEqual(reponse.status_code, 403)

    def test_publication_et_version_courante(self):
        version = self.creer().data["version"]
        self.comme(self.asc)
        self.assertEqual(self.client.get(f"{URL}current/").status_code, 404)
        self.assertEqual(self.client.get(f"{URL}{version}/").status_code, 404)

        self.comme(self.admin)
        reponse = self.client.post(f"{URL}{version}/publish/")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["statut"], "publiee")

        for user in (self.asc, self.femme, self.agent):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                courante = self.client.get(f"{URL}current/")
                self.assertEqual(courante.status_code, 200)
                self.assertEqual(courante.data["version"], version)
                self.assertEqual(
                    courante.data["contenu"]["meta"]["statut_validation"],
                    "À VALIDER",
                )
                self.assertEqual(courante["ETag"], f'"v{version}"')

    def test_etag_evite_de_retelecharger(self):
        config = self.publier_config()
        self.comme(self.asc)
        reponse = self.client.get(
            f"{URL}current/",
            HTTP_IF_NONE_MATCH=f'"v{config.version}"',
        )
        self.assertEqual(reponse.status_code, 304)

    def test_une_version_publiee_ne_change_plus(self):
        config = self.publier_config()
        self.comme(self.admin)
        reponse = self.client.patch(
            f"{URL}{config.version}/",
            {"libelle": "Autre"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(
            self.client.post(f"{URL}{config.version}/publish/").status_code,
            400,
        )

    def test_brouillon_modifiable(self):
        version = self.creer().data["version"]
        reponse = self.client.patch(
            f"{URL}{version}/",
            {
                "statut_validation": "validee",
                "valide_par": "Comité médical (test)",
                "reference_validation": "PV-001",
                "date_validation": "2026-11-01",
            },
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["statut_validation"], "validee")

    def test_retrait_revient_a_la_version_precedente(self):
        premiere = self.publier_config()
        seconde = self.publier_config()
        self.comme(self.admin)
        self.client.post(f"{URL}{seconde.version}/retire/")
        self.comme(self.asc)
        self.assertEqual(
            self.client.get(f"{URL}current/").data["version"],
            premiere.version,
        )

    @override_settings(TARANAKA_CONFIG_VALIDEE_OBLIGATOIRE=True)
    def test_production_exige_une_validation_ecrite(self):
        version = self.creer().data["version"]
        reponse = self.client.post(f"{URL}{version}/publish/")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("statut_validation", reponse.data)

        self.client.patch(
            f"{URL}{version}/",
            {
                "statut_validation": "validee",
                "valide_par": "Ministère de la Santé publique (test)",
                "reference_validation": "Lettre n° 1",
                "date_validation": "2026-11-01",
            },
            format="json",
        )
        self.assertEqual(self.client.post(f"{URL}{version}/publish/").status_code, 200)

    def test_liste_sans_le_contenu(self):
        self.publier_config()
        self.comme(self.femme)
        reponse = self.client.get(URL)
        self.assertEqual(reponse.status_code, 200)
        self.assertNotIn("contenu", reponse.data["results"][0])


class CommandeChargementTest(BaseApiTest):
    def test_charge_l_exemple_et_le_publie(self):
        sortie = StringIO()
        call_command("charger_config_clinique", "--publier", stdout=sortie)
        config = ConfigurationClinique.objects.get()
        self.assertEqual(config.statut, "publiee")
        self.assertEqual(config.statut_validation, "a_valider")
        self.assertIn("À VALIDER", sortie.getvalue())

    def test_exemple_marque_a_valider(self):
        contenu = self.config_exemple()
        self.assertEqual(contenu["meta"]["statut_validation"], "À VALIDER")
        sections = [cle for cle in contenu if cle != "meta"]
        for section in sections:
            with self.subTest(section=section):
                self.assertEqual(contenu[section]["statut"], "À VALIDER")
        for regle in contenu["malnutrition"]["classification"]["regles"]:
            self.assertEqual(regle["statut"], "À VALIDER")
        for regle in contenu["malnutrition"]["orientation"]["regles"]:
            self.assertEqual(regle["statut"], "À VALIDER")
