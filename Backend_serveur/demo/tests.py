"""Acceptance tests: the server side of the 8 demo scenarios (spec §13), on the
demo data of `charger_demo`, through the real API and real PIN logins.

Scenarios 1 and 6 (first launch, airplane mode) happen on the phone only; the
server part they rely on (config download, idempotent resend) is covered here.
"""

import uuid
from datetime import timedelta

from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from demo import donnees
from referencement.models import Referencement


@override_settings(PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"])
class ScenariosDemoTest(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.demo = donnees.charger(sortie=lambda *args: None)

    def connecter(self, identifiant, appareil="tel-demo"):
        pin = next(c[2] for c in donnees.COMPTES if c[0] == identifiant)
        client = APIClient()
        reponse = client.post(
            "/api/auth/login/",
            {"identifiant": identifiant, "pin": pin},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {reponse.data['access']}",
            HTTP_X_DEVICE_ID=appareil,
        )
        return client

    def test_chargement_refuse_deux_fois(self):
        self.assertTrue(donnees.deja_charge())

    def test_scenario_1_configuration_telechargee_au_premier_lancement(self):
        client = self.connecter("mere.voahangy")
        config = client.get("/api/sync/pull/").data["config_clinique"]
        self.assertEqual(config["version"], self.demo.config_version)
        contenu = config["mise_a_jour"]["contenu"]
        self.assertEqual(contenu["meta"]["langues"], ["mg", "fr"])
        self.assertEqual(contenu["meta"]["statut_validation"], "À VALIDER")

    def test_scenario_2_trois_cycles(self):
        client = self.connecter("mere.voahangy")
        cycles = client.get("/api/cycles/").data["results"]
        self.assertEqual(len(cycles), 3)
        self.assertEqual(sorted(c["duree_cycle"] for c in cycles), [28, 28, 29])
        contenu = client.get("/api/clinical-config/current/").data["contenu"]
        self.assertEqual(contenu["cycle"]["cycles_pour_prediction_fiable"], 3)
        self.assertIn("contraception", contenu["cycle"]["avertissement"]["fr"])

    def test_scenario_3_grossesse_a_12_sa(self):
        client = self.connecter("mere.lalao")
        grossesse = client.get("/api/pregnancies/").data["results"][0]
        aujourd_hui = timezone.localdate()
        ddr = timezone.datetime.fromisoformat(grossesse["ddr"]).date()
        dpa = timezone.datetime.fromisoformat(grossesse["dpa"]).date()
        self.assertEqual(divmod((aujourd_hui - ddr).days, 7), (12, 0))
        self.assertEqual(dpa, ddr + timedelta(days=280))
        contenu = client.get("/api/clinical-config/current/").data["contenu"]
        prochaines = [s for s in contenu["calendrier_cpn"]["contacts_semaines_amenorrhee"] if s > 12]
        self.assertEqual(prochaines[0], 20)
        saignement = client.get("/api/danger-types/").data["results"]
        type_id = next(t["id"] for t in saignement if t["description"] == "Saignement vaginal")
        reponse = client.post(
            f"/api/pregnancies/{grossesse['id']}/dangers/",
            {"type_danger_grossesse_id": type_id},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)

    def test_scenario_4_diversite_3_sur_8(self):
        client = self.connecter("mere.fara")
        journal = client.get("/api/food-logs/").data["results"][0]
        self.assertEqual(journal["score_diversite"], 3)
        self.assertFalse(journal["diversite_minimale_atteinte"])
        enfant = client.get(f"/api/children/{journal['enfant_id']}/").data
        naissance = timezone.datetime.fromisoformat(enfant["date_naissance"]).date()
        self.assertEqual(int((timezone.localdate() - naissance).days / 30.4375), 9)
        contenu = client.get("/api/clinical-config/current/").data["contenu"]
        conseil = next(
            c for c in contenu["alimentation_enfant"]["conseils"] if c["code"] == "ajouter_aliment_animal"
        )
        absents = {
            g["numero"]
            for g in contenu["alimentation_enfant"]["groupes"]
            if not journal[g["champ"]]
        }
        self.assertTrue(set(conseil["si_groupes_absents"]) <= absents)

    def test_scenarios_5_7_8(self):
        superviseur = self.connecter("sup.analamanga", "poste-sup")
        mas_avant = superviseur.get("/api/stats/").data["total"]["indicateurs"]["cas_mas"]
        self.assertIsNotNone(mas_avant)

        # 5. Screening offline: PB 112 mm at 18 months, no oedema.
        asc = self.connecter("ac.rasoa", "tel-rasoa")
        enfant_id = str(self.demo.enfant_scenario_5.pk)
        mesure_id, referencement_id = str(uuid.uuid4()), str(uuid.uuid4())
        lot = {
            "operations": [
                {
                    "cle_idempotence": str(uuid.uuid4()),
                    "table": "mesure",
                    "operation": "create",
                    "id": mesure_id,
                    "donnees": {
                        "enfant_id": enfant_id,
                        "date_mesure": str(timezone.localdate()),
                        "poids_kg": "8.60",
                        "taille_cm": "77.5",
                        "position": "couche",
                        "pb_mm": 112,
                        "oedemes_bilateraux": "aucun",
                        "alerte": "rouge",
                    },
                },
                {
                    "cle_idempotence": str(uuid.uuid4()),
                    "table": "referencement",
                    "operation": "create",
                    "id": referencement_id,
                    "donnees": {
                        "code_unique": "TRK-7F3K-92",
                        "origine": "enfant",
                        "enfant_id": enfant_id,
                        "mesure_id": mesure_id,
                        "csb_id": self.demo.centres["crenas"].pk,
                        "priorite": "haute",
                        "motif": "MAS – PB 112 mm",
                        "date_referencement": timezone.now().isoformat(),
                    },
                },
            ]
        }
        resultats = asc.post("/api/sync/push/", lot, format="json").data["resultats"]
        self.assertEqual([r["statut"] for r in resultats], ["applique", "applique"])
        mesure = resultats[0]["ligne"]
        self.assertEqual(
            (mesure["age_mois"], mesure["classification"], mesure["orientation_centre"], mesure["urgence"]),
            (18, "mas", "crenas", "orange"),
        )
        self.assertEqual(resultats[1]["ligne"]["status"], "envoye")

        # 7. Forced resend: no duplicate.
        renvoi = asc.post("/api/sync/push/", lot, format="json").data["resultats"]
        self.assertTrue(all(r["rejoue"] for r in renvoi))
        self.assertEqual(Referencement.objects.filter(code_unique="TRK-7F3K-92").count(), 1)

        # 7. Concurrent change of the same record: a conflict on the web.
        admin = self.connecter("admin.demo", "poste-admin")
        version = admin.get(f"/api/children/{enfant_id}/").data["version"]
        admin.patch(f"/api/children/{enfant_id}/", {"nom": "Soa Nirina", "version": version}, format="json")
        conflit = asc.post(
            "/api/sync/push/",
            {
                "operations": [
                    {
                        "cle_idempotence": str(uuid.uuid4()),
                        "table": "enfant",
                        "operation": "update",
                        "id": enfant_id,
                        "version": version,
                        "donnees": {"nom": "Soa Fanja"},
                    }
                ]
            },
            format="json",
        ).data["resultats"][0]
        self.assertEqual(conflit["statut"], "conflit")
        infirmier = self.connecter("inf.crenas", "poste-crenas")
        conflits = infirmier.get("/api/conflicts/?statut=a_verifier").data["results"]
        self.assertEqual([c["id"] for c in conflits], [conflit["conflit_id"]])

        # 8. The CRENAS nurse sees the referral first and marks the arrival.
        file = infirmier.get("/api/referrals/incoming/").data["results"]
        self.assertEqual(file[0]["code_unique"], "TRK-7F3K-92")
        arrivee = infirmier.post(
            f"/api/referrals/{referencement_id}/status/",
            {"status": "recu", "version": file[0]["version"]},
            format="json",
        )
        self.assertEqual(arrivee.status_code, 200, arrivee.data)

        # 8. The ASC sees « Reçu par le centre » at the next sync.
        tire = asc.get("/api/sync/pull/", {"tables": "referencement"}).data
        lignes = {l["id"]: l for l in tire["tables"]["referencement"]["lignes"]}
        self.assertEqual(lignes[referencement_id]["status"], "recu")

        # 8. The supervisor's MAS counter goes up by 1, with no name.
        stats = superviseur.get("/api/stats/").data
        self.assertEqual(stats["total"]["indicateurs"]["cas_mas"], mas_avant + 1)
        self.assertNotIn("Soa", str(stats))

    def test_relances_de_l_asc(self):
        asc = self.connecter("ac.rasoa")
        relances = asc.get("/api/follow-ups/").data
        self.assertEqual(len(relances["referencements_non_arrives"]), 1)
        self.assertEqual(len(relances["rendez_vous_manques"]), 1)
