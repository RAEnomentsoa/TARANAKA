from comptes.models import CodeProfile, User
from synchro.models import JournalAudit, JournalImmuable
from synchro.outils_tests import BaseApiTest

PROFILES = "/api/profiles/"


class SuperviseurComptesTest(BaseApiTest):
    """The supervisor creates the ASC accounts of their zone and resets their PIN."""

    def setUp(self):
        super().setUp()
        self.superviseur = self.compte(
            "sup",
            CodeProfile.SUPERVISEUR,
            region=self.region,
        )
        self.comme(self.superviseur)

    def test_cree_un_asc_dans_sa_region(self):
        reponse = self.client.post(
            PROFILES,
            {"identifiant": "asc9", "nom": "Rabe", "prenom": "Koto", "pin": "4321"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["profile"]["code"], "asc")
        self.assertEqual(reponse.data["region_id"], self.region.pk)

    def test_ne_cree_pas_d_autre_profil(self):
        for code in ("beneficiaire", "agent_csb", "admin", "superviseur"):
            with self.subTest(code=code):
                reponse = self.client.post(
                    PROFILES,
                    {
                        "identifiant": f"x-{code}",
                        "nom": "X",
                        "prenom": "Y",
                        "pin": "4321",
                        "profile_code": code,
                        "csb_id": self.csb.pk,
                        "region_id": self.region.pk,
                    },
                    format="json",
                )
                self.assertEqual(reponse.status_code, 403)

    def test_lit_seulement_les_asc_de_sa_region(self):
        reponse = self.client.get(PROFILES)
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(
            self.ids(reponse),
            {str(self.asc.pk), str(self.asc_meme_region.pk)},
        )

    def test_superviseur_national_lit_tous_les_asc(self):
        national = self.compte("sup-nat", CodeProfile.SUPERVISEUR)
        self.comme(national)
        attendus = {
            str(pk)
            for pk in User.objects.filter(profile__code="asc").values_list("pk", flat=True)
        }
        self.assertEqual(self.ids(self.client.get(PROFILES)), attendus)

    def test_ne_modifie_pas_un_compte(self):
        reponse = self.client.patch(
            f"{PROFILES}{self.asc.pk}/",
            {"nom": "Autre"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)

    def test_reinitialise_le_pin_d_un_asc_bloque(self):
        self.asc.tentatives_echouees = 15
        self.asc.save()
        reponse = self.client.post(
            f"{PROFILES}{self.asc.pk}/reset-pin/",
            {"nouveau_pin": "9876"},
            format="json",
            HTTP_X_DEVICE_ID="poste-sup",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.asc.refresh_from_db()
        self.assertTrue(self.asc.check_password("9876"))
        self.assertEqual(self.asc.tentatives_echouees, 0)
        ligne = JournalAudit.objects.get(action="reinitialiser_pin")
        self.assertEqual(ligne.user, self.superviseur)
        self.assertEqual(ligne.ligne_id, self.asc.pk)
        self.assertEqual(ligne.details["device_id"], "poste-sup")

    def test_ne_reinitialise_pas_hors_de_sa_zone(self):
        for cible in (self.autre_asc, self.femme, self.agent):
            with self.subTest(cible=cible.identifiant):
                reponse = self.client.post(
                    f"{PROFILES}{cible.pk}/reset-pin/",
                    {"nouveau_pin": "9876"},
                    format="json",
                )
                self.assertEqual(reponse.status_code, 404)

    def test_asc_reinitialise_seulement_une_beneficiaire(self):
        """D16: the woman in front of her ASC gets a new PIN; never a colleague."""
        self.comme(self.asc)
        reponse = self.client.post(
            f"{PROFILES}{self.femme.pk}/reset-pin/",
            {"nouveau_pin": "9876"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.femme.refresh_from_db()
        self.assertTrue(self.femme.check_password("9876"))
        reponse = self.client.post(
            f"{PROFILES}{self.asc_meme_region.pk}/reset-pin/",
            {"nouveau_pin": "9876"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 404)

    def test_format_du_pin(self):
        reponse = self.client.post(
            f"{PROFILES}{self.asc.pk}/reset-pin/",
            {"nouveau_pin": "12"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)


class JournalAuditTest(BaseApiTest):
    def test_lecture_reservee_a_l_admin(self):
        JournalAudit.objects.create(action="test", details={})
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        for user in (self.asc, self.agent, self.femme, superviseur):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(self.client.get("/api/audit/").status_code, 403)
        self.comme(self.admin)
        reponse = self.client.get("/api/audit/?action=test")
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.data["count"], 1)

    def test_lecture_seule(self):
        self.comme(self.admin)
        self.assertEqual(self.client.post("/api/audit/", {}).status_code, 405)

    def test_ligne_immuable(self):
        ligne = JournalAudit.objects.create(action="test", details={})
        ligne.action = "autre"
        with self.assertRaises(JournalImmuable):
            ligne.save()
        with self.assertRaises(JournalImmuable):
            ligne.delete()

    def test_connexion_enregistre_l_appareil(self):
        self.client.post(
            "/api/auth/login/",
            {"identifiant": "asc", "pin": "1234"},
            format="json",
            HTTP_X_DEVICE_ID="tel-42",
        )
        ligne = JournalAudit.objects.get(action="login_succes")
        self.assertEqual(ligne.details["device_id"], "tel-42")
