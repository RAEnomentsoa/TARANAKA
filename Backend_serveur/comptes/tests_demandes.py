from django.core.cache import cache

from comptes.models import CodeProfile, DemandeAcces, StatutDemande, User
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

DEMANDE = "/api/auth/access-request/"
OPTIONS = "/api/auth/access-request/options/"
DEMANDES = "/api/access-requests/"
LOGIN = "/api/auth/login/"


class DemandeAccesTest(BaseApiTest):
    """D15: a person asks for a web account, an admin approves or refuses."""

    def setUp(self):
        super().setUp()
        # The request is throttled per address: start every test from zero.
        cache.clear()
        self.client.credentials()

    def formulaire(self, **extra):
        return {
            "nom": "Rakoto",
            "prenom": "Hery",
            "email": "hery@example.org",
            "phone": "034 00 000 01",
            "identifiant": "hery.crenas",
            "pin": "2468",
            "profil_demande": "agent_csb",
            "csb_id": self.csb.pk,
            "fonction": "Infirmier",
            "message": "Nouvel infirmier du centre.",
            **extra,
        }

    def demander(self, **extra):
        self.client.credentials()
        return self.client.post(DEMANDE, self.formulaire(**extra), format="json")

    # ---------- Public form ----------

    def test_demande_publique_cree_une_demande_en_attente_sans_compte(self):
        reponse = self.demander()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["statut"], "en_attente")
        self.assertNotIn("pin", reponse.data)
        self.assertFalse(User.objects.filter(identifiant="hery.crenas").exists())
        demande = DemandeAcces.objects.get()
        self.assertNotEqual(demande.pin_hash, "2468")
        self.assertEqual(demande.region, self.csb.region)
        self.assertTrue(JournalAudit.objects.filter(action="demande_acces_creee").exists())

    def test_on_ne_peut_pas_se_connecter_avant_l_approbation(self):
        self.demander()
        reponse = self.client.post(
            LOGIN, {"identifiant": "hery.crenas", "pin": "2468"}, format="json"
        )
        self.assertEqual(reponse.status_code, 401)

    def test_profils_refuses(self):
        for code in ("asc", "admin", "beneficiaire", "inconnu"):
            with self.subTest(code=code):
                cache.clear()
                reponse = self.demander(profil_demande=code, identifiant=f"x-{code}")
                self.assertEqual(reponse.status_code, 400)
                self.assertIn("profil_demande", reponse.data)

    def test_agent_csb_sans_centre_refuse(self):
        reponse = self.demander(csb_id=None)
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("csb_id", reponse.data)

    def test_superviseur_regional_ou_national(self):
        reponse = self.demander(
            profil_demande="superviseur", csb_id=self.csb.pk, region_id=self.region.pk
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        demande = DemandeAcces.objects.get()
        self.assertIsNone(demande.csb)
        self.assertEqual(demande.region, self.region)
        cache.clear()
        reponse = self.demander(profil_demande="superviseur", identifiant="national")
        self.assertEqual(reponse.status_code, 201, reponse.data)

    def test_identifiant_deja_pris_par_un_compte_ou_une_demande(self):
        reponse = self.demander(identifiant=self.agent.identifiant)
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("identifiant", reponse.data)
        self.assertEqual(self.demander().status_code, 201)
        reponse = self.demander()
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("identifiant", reponse.data)

    def test_pin_et_telephone_verifies(self):
        reponse = self.demander(pin="12")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("pin", reponse.data)
        reponse = self.demander(phone="  ")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("phone", reponse.data)

    def test_limite_par_heure(self):
        statuts = [self.demander(identifiant=f"id{i}").status_code for i in range(6)]
        self.assertEqual(statuts[:5], [201] * 5)
        self.assertEqual(statuts[5], 429)

    def test_options_publiques_sans_donnee_personnelle(self):
        reponse = self.client.get(OPTIONS)
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(
            {r["nom"] for r in reponse.data["regions"]}, {"Analamanga", "Itasy"}
        )
        centre = next(c for c in reponse.data["centres"] if c["id"] == self.csb.pk)
        self.assertEqual(set(centre), {"id", "name", "type_centre", "region_id"})

    # ---------- Admin ----------

    def test_seul_l_admin_voit_les_demandes(self):
        self.demander()
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region)
        for user in (self.femme, self.asc, self.agent, superviseur):
            with self.subTest(profil=user.profile.code):
                self.comme(user)
                self.assertEqual(self.client.get(DEMANDES).status_code, 403)
        self.comme(self.admin)
        reponse = self.client.get(DEMANDES, {"statut": "en_attente"})
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.data["count"], 1)
        ligne = reponse.data["results"][0]
        self.assertEqual(ligne["csb_nom"], self.csb.name)
        self.assertNotIn("pin", ligne)
        self.assertNotIn("pin_hash", ligne)

    def test_approbation_cree_le_compte_avec_le_pin_choisi(self):
        demande_id = self.demander().data["id"]
        self.comme(self.admin)
        reponse = self.client.post(f"{DEMANDES}{demande_id}/approve/", {}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["statut"], "approuvee")
        self.assertEqual(reponse.data["traitee_par"]["id"], str(self.admin.pk))

        user = User.objects.get(identifiant="hery.crenas")
        self.assertEqual(user.profile.code, "agent_csb")
        self.assertEqual(user.csb, self.csb)
        self.assertEqual(user.phone, "034 00 000 01")
        self.assertTrue(user.check_password("2468"))
        self.assertEqual(DemandeAcces.objects.get().pin_hash, "")
        self.assertTrue(JournalAudit.objects.filter(action="demande_acces_approuvee").exists())

        self.client.credentials()
        reponse = self.client.post(
            LOGIN, {"identifiant": "hery.crenas", "pin": "2468"}, format="json"
        )
        self.assertEqual(reponse.status_code, 200)

    def test_l_admin_corrige_le_profil_ou_le_centre(self):
        demande_id = self.demander().data["id"]
        self.comme(self.admin)
        reponse = self.client.post(
            f"{DEMANDES}{demande_id}/approve/",
            {"csb_id": self.autre_csb.pk},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(User.objects.get(identifiant="hery.crenas").csb, self.autre_csb)

        cache.clear()
        demande_id = self.demander(identifiant="h2").data["id"]
        self.comme(self.admin)
        reponse = self.client.post(
            f"{DEMANDES}{demande_id}/approve/",
            {"profil_demande": "superviseur", "region_id": self.autre_region.pk},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        user = User.objects.get(identifiant="h2")
        self.assertEqual(user.profile.code, "superviseur")
        self.assertIsNone(user.csb)
        self.assertEqual(user.region, self.autre_region)

    def test_refus_ne_cree_rien(self):
        demande_id = self.demander().data["id"]
        self.comme(self.admin)
        reponse = self.client.post(
            f"{DEMANDES}{demande_id}/refuse/", {"motif": "Inconnu du centre"}, format="json"
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["statut"], "refusee")
        self.assertEqual(reponse.data["motif_refus"], "Inconnu du centre")
        self.assertFalse(User.objects.filter(identifiant="hery.crenas").exists())
        self.assertEqual(DemandeAcces.objects.get().pin_hash, "")
        # The identifiant is free again for a new request.
        cache.clear()
        self.assertEqual(self.demander().status_code, 201)

    def test_une_demande_traitee_ne_change_plus(self):
        demande_id = self.demander().data["id"]
        self.comme(self.admin)
        self.client.post(f"{DEMANDES}{demande_id}/refuse/", {}, format="json")
        for action in ("approve", "refuse"):
            with self.subTest(action=action):
                reponse = self.client.post(f"{DEMANDES}{demande_id}/{action}/", {}, format="json")
                self.assertEqual(reponse.status_code, 400)
        self.assertEqual(DemandeAcces.objects.get().statut, StatutDemande.REFUSEE)


class IdentifiantSansCasseTest(BaseApiTest):
    """"Rasoa" and "rasoa" are the same username everywhere."""

    def setUp(self):
        super().setUp()
        cache.clear()
        self.client.credentials()
        self.compte("Ac.Rasoa", CodeProfile.ASC, region=self.region)

    def test_connexion_quelle_que_soit_la_casse(self):
        for saisie in ("ac.rasoa", "AC.RASOA", "Ac.Rasoa"):
            with self.subTest(saisie=saisie):
                reponse = self.client.post(
                    LOGIN, {"identifiant": saisie, "pin": "1234"}, format="json"
                )
                self.assertEqual(reponse.status_code, 200, reponse.data)

    def test_la_base_refuse_un_doublon_a_la_casse_pres(self):
        from django.db import IntegrityError, transaction

        with self.assertRaises(IntegrityError), transaction.atomic():
            self.compte("ac.rasoa", CodeProfile.ASC, region=self.region)

    def test_creation_de_compte_refusee(self):
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region)
        self.comme(superviseur)
        reponse = self.client.post(
            "/api/profiles/",
            {"identifiant": "AC.RASOA", "nom": "X", "prenom": "Y", "pin": "4321"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(reponse.data["identifiant"], ["Cet identifiant est déjà utilisé."])

    def test_creation_refusee_si_une_demande_en_attente_le_reserve(self):
        self.client.post(
            DEMANDE,
            {
                "nom": "R", "prenom": "H", "phone": "1", "identifiant": "Hery.Crenas",
                "pin": "2468", "profil_demande": "agent_csb", "csb_id": self.csb.pk,
            },
            format="json",
        )
        self.comme(self.admin)
        reponse = self.client.post(
            "/api/profiles/",
            {
                "identifiant": "hery.crenas", "nom": "X", "prenom": "Y", "pin": "4321",
                "profile_code": "agent_csb", "csb_id": self.csb.pk,
            },
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("identifiant", reponse.data)

    def test_modifier_son_propre_identifiant_reste_possible(self):
        self.comme(self.admin)
        compte = User.objects.get(identifiant="Ac.Rasoa")
        reponse = self.client.patch(
            f"/api/profiles/{compte.pk}/", {"identifiant": "ac.rasoa"}, format="json"
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)

    def test_demande_d_acces_refusee_a_la_casse_pres(self):
        base = {
            "nom": "R", "prenom": "H", "phone": "1", "pin": "2468",
            "profil_demande": "agent_csb", "csb_id": self.csb.pk,
        }
        reponse = self.client.post(DEMANDE, {**base, "identifiant": "AC.rasoa"}, format="json")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("identifiant", reponse.data)
        self.assertEqual(
            self.client.post(DEMANDE, {**base, "identifiant": "Hery"}, format="json").status_code, 201
        )
        reponse = self.client.post(DEMANDE, {**base, "identifiant": "HERY"}, format="json")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("identifiant", reponse.data)
