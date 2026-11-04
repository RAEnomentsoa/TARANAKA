"""Two-factor login (TOTP) for web accounts, spec §2."""

import base64
from unittest import mock

from django.core.cache import cache
from django.test import SimpleTestCase, override_settings

from comptes import totp
from comptes.models import CodeProfile
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

LOGIN = "/api/auth/login/"
INSTANT = 1_800_000_000  # a fixed time, so codes are predictable


class Rfc6238Test(SimpleTestCase):
    """Reference values of RFC 6238, appendix B (SHA-1, 8 digits)."""

    CLE = b"12345678901234567890"
    VECTEURS = {
        59: "94287082",
        1111111109: "07081804",
        1111111111: "14050471",
        1234567890: "89005924",
        2000000000: "69279037",
        20000000000: "65353130",
    }

    def test_vecteurs_de_reference(self):
        for instant, attendu in self.VECTEURS.items():
            with self.subTest(instant=instant):
                pas = totp.pas_courant(instant)
                self.assertEqual(totp.code_au_pas(self.CLE, pas, chiffres=8), attendu)

    def test_verification_en_6_chiffres(self):
        secret = base64.b32encode(self.CLE).decode()
        self.assertIsNotNone(totp.verifier(secret, "287082", instant=59))
        self.assertIsNone(totp.verifier(secret, "287083", instant=59))

    def test_fenetre_d_un_pas_et_pas_plus(self):
        secret = totp.nouveau_secret()
        cle = base64.b32decode(secret + "=" * (-len(secret) % 8))
        pas = totp.pas_courant(INSTANT)
        for decalage, accepte in ((-2, False), (-1, True), (0, True), (1, True), (2, False)):
            with self.subTest(decalage=decalage):
                code = totp.code_au_pas(cle, pas + decalage)
                self.assertEqual(totp.verifier(secret, code, instant=INSTANT) is not None, accepte)

    def test_pas_de_rejeu(self):
        secret = totp.nouveau_secret()
        code = totp.code_au_pas(totp._cle(secret), totp.pas_courant(INSTANT))
        pas = totp.verifier(secret, code, instant=INSTANT)
        self.assertIsNone(totp.verifier(secret, code, dernier_pas=pas, instant=INSTANT))

    def test_formats_refuses(self):
        secret = totp.nouveau_secret()
        for code in ("", "12345", "1234567", "abcdef", None):
            with self.subTest(code=code):
                self.assertIsNone(totp.verifier(secret, code, instant=INSTANT))

    def test_uri_pour_les_applications(self):
        uri = totp.uri_provisionnement("JBSWY3DPEHPK3PXP", "inf.crenas")
        self.assertTrue(uri.startswith("otpauth://totp/TARANAKA%3Ainf.crenas?"))
        self.assertIn("secret=JBSWY3DPEHPK3PXP", uri)
        self.assertIn("issuer=TARANAKA", uri)


def code_pour(user, decalage=0):
    user.refresh_from_db()
    return totp.code_au_pas(totp._cle(user.totp_secret), totp.pas_courant(INSTANT) + decalage)


@mock.patch("comptes.totp.time.time", return_value=INSTANT)
class TotpApiTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        cache.clear()

    def activer(self, user):
        self.comme(user)
        self.client.post("/api/auth/2fa/setup/")
        reponse = self.client.post(
            "/api/auth/2fa/activate/",
            {"code": code_pour(user)},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.client.force_authenticate(None)
        return reponse

    def login(self, identifiant, code=None, pin="1234"):
        donnees = {"identifiant": identifiant, "pin": pin}
        if code is not None:
            donnees["code_totp"] = code
        return self.client.post(LOGIN, donnees, format="json")

    def test_mise_en_place(self, _horloge):
        self.comme(self.agent)
        preparation = self.client.post("/api/auth/2fa/setup/")
        self.assertEqual(preparation.status_code, 200)
        self.assertIn(preparation.data["secret"], preparation.data["uri"])
        self.assertFalse(self.client.get("/api/auth/2fa/").data["active"])
        refuse = self.client.post("/api/auth/2fa/activate/", {"code": "000000"}, format="json")
        self.assertEqual(refuse.status_code, 400)
        self.assertEqual(refuse.data["code"], "totp_invalide")
        active = self.client.post(
            "/api/auth/2fa/activate/",
            {"code": code_pour(self.agent)},
            format="json",
        )
        self.assertEqual(active.status_code, 200, active.data)
        self.assertIn("access", active.data)
        self.agent.refresh_from_db()
        self.assertTrue(self.client.get("/api/auth/2fa/").data["active"])
        self.assertTrue(JournalAudit.objects.filter(action="totp_active", user=self.agent).exists())

    def test_reserve_aux_comptes_web(self, _horloge):
        for user in (self.asc, self.femme):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                reponse = self.client.post("/api/auth/2fa/setup/")
                self.assertEqual(reponse.status_code, 403)
                self.assertEqual(reponse.data["code"], "totp_non_disponible")

    def test_superviseur_et_admin_peuvent_l_activer(self, _horloge):
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        for user in (superviseur, self.admin):
            with self.subTest(user=user.identifiant):
                self.activer(user)
                self.assertEqual(self.login(user.identifiant).data["code"], "totp_requis")

    def test_connexion_en_deux_etapes(self, _horloge):
        self.activer(self.agent)
        sans_code = self.login("agent")
        self.assertEqual(sans_code.status_code, 401)
        self.assertEqual(sans_code.data["code"], "totp_requis")
        self.assertNotIn("access", sans_code.data)
        avec_code = self.login("agent", code_pour(self.agent, 1))
        self.assertEqual(avec_code.status_code, 200, avec_code.data)
        self.assertFalse(avec_code.data["totp_a_configurer"])

    def test_code_rejoue_refuse(self, _horloge):
        self.activer(self.agent)
        code = code_pour(self.agent, 1)
        self.assertEqual(self.login("agent", code).status_code, 200)
        reponse = self.login("agent", code)
        self.assertEqual(reponse.status_code, 401)
        self.assertEqual(reponse.data["code"], "totp_invalide")

    def test_mauvais_code_compte_comme_un_echec(self, _horloge):
        self.activer(self.agent)
        for _ in range(4):
            self.assertEqual(self.login("agent", "000000").data["code"], "totp_invalide")
        self.assertEqual(self.login("agent", "000000").status_code, 423)
        # Blocked: even the right PIN and code are refused.
        self.assertEqual(self.login("agent", code_pour(self.agent, 1)).status_code, 423)

    def test_bon_pin_sans_code_ne_remet_pas_le_compteur_a_zero(self, _horloge):
        self.activer(self.agent)
        self.login("agent", "000000")
        self.login("agent")
        self.agent.refresh_from_db()
        self.assertEqual(self.agent.tentatives_echouees, 1)

    def test_comptes_sans_double_authentification_inchanges(self, _horloge):
        reponse = self.login("asc")
        self.assertEqual(reponse.status_code, 200)
        self.assertFalse(reponse.data["totp_a_configurer"])

    def test_desactivation(self, _horloge):
        self.activer(self.agent)
        self.comme(self.agent)
        refuse = self.client.post(
            "/api/auth/2fa/disable/",
            {"pin": "9999", "code": code_pour(self.agent, 1)},
            format="json",
        )
        self.assertEqual(refuse.status_code, 401)
        reponse = self.client.post(
            "/api/auth/2fa/disable/",
            {"pin": "1234", "code": code_pour(self.agent, 1)},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.client.force_authenticate(None)
        self.assertEqual(self.login("agent").status_code, 200)

    def test_admin_reinitialise_apres_perte_du_telephone(self, _horloge):
        self.activer(self.agent)
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        self.comme(superviseur)
        self.assertEqual(self.client.post(f"/api/profiles/{self.agent.pk}/reset-2fa/").status_code, 403)
        self.comme(self.admin)
        reponse = self.client.post(f"/api/profiles/{self.agent.pk}/reset-2fa/")
        self.assertEqual(reponse.status_code, 200)
        self.agent.refresh_from_db()
        self.assertFalse(self.agent.totp_active)
        self.assertEqual(self.agent.totp_secret, "")
        ligne = JournalAudit.objects.get(action="totp_reinitialise")
        self.assertEqual((ligne.user, ligne.ligne_id), (self.admin, self.agent.pk))


@override_settings(TARANAKA_TOTP_OBLIGATOIRE=True)
@mock.patch("comptes.totp.time.time", return_value=INSTANT)
class TotpObligatoireTest(BaseApiTest):
    """Production: a web account must set up 2FA before anything else."""

    def setUp(self):
        super().setUp()
        cache.clear()

    def jeton(self, identifiant):
        reponse = self.client.post(LOGIN, {"identifiant": identifiant, "pin": "1234"}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        return reponse.data

    def test_jeton_limite_a_la_mise_en_place(self, _horloge):
        donnees = self.jeton("agent")
        self.assertTrue(donnees["totp_a_configurer"])
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {donnees['access']}")
        bloque = self.client.get("/api/referrals/")
        self.assertEqual(bloque.status_code, 403)
        self.assertIn("double authentification", bloque.data["detail"])
        self.assertEqual(self.client.get("/api/auth/me/").status_code, 200)
        self.assertTrue(self.client.get("/api/auth/2fa/").data["a_configurer"])
        self.assertEqual(self.client.post("/api/auth/2fa/setup/").status_code, 200)
        active = self.client.post(
            "/api/auth/2fa/activate/",
            {"code": code_pour(self.agent)},
            format="json",
        )
        self.assertEqual(active.status_code, 200, active.data)
        # The restricted token was revoked; the new one opens everything.
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {active.data['access']}")
        self.assertEqual(self.client.get("/api/referrals/").status_code, 200)

    def test_le_rafraichissement_garde_la_limite(self, _horloge):
        donnees = self.jeton("agent")
        rafraichi = self.client.post("/api/auth/refresh/", {"refresh": donnees["refresh"]}, format="json")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {rafraichi.data['access']}")
        self.assertEqual(self.client.get("/api/referrals/").status_code, 403)

    def test_l_asc_n_est_pas_concerne(self, _horloge):
        donnees = self.jeton("asc")
        self.assertFalse(donnees["totp_a_configurer"])
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {donnees['access']}")
        self.assertEqual(self.client.get("/api/children/").status_code, 200)

    def test_desactivation_refusee(self, _horloge):
        self.comme(self.agent)
        self.client.post("/api/auth/2fa/setup/")
        self.client.post("/api/auth/2fa/activate/", {"code": code_pour(self.agent)}, format="json")
        reponse = self.client.post(
            "/api/auth/2fa/disable/",
            {"pin": "1234", "code": code_pour(self.agent, 1)},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)
        self.assertEqual(reponse.data["code"], "totp_obligatoire")
