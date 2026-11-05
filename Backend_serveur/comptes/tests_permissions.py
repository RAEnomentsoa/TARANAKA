"""RBAC matrix: every endpoint × every profile (spec §2).

A read is allowed when it answers 200, refused when 403. A write sent with an
empty body is allowed when it answers 400 (the data is then checked), refused
when 403. This table is also the one documented in docs/endpoint.md.
"""

from comptes.models import CodeProfile
from synchro.outils_tests import BaseApiTest

PROFILS = ("beneficiaire", "asc", "agent_csb", "superviseur", "admin")
OK, NON = 200, 403
VALIDE = 400  # allowed, then refused by the data checks

LECTURES = {
    "/api/children/": (OK, OK, OK, NON, OK),
    "/api/measurements/": (OK, OK, OK, NON, OK),
    "/api/pregnancies/": (OK, OK, OK, NON, OK),
    "/api/cycles/": (OK, NON, NON, NON, OK),
    "/api/food-logs/": (OK, OK, OK, NON, OK),
    "/api/referrals/": (OK, OK, OK, NON, OK),
    "/api/referrals/incoming/": (NON, NON, OK, NON, OK),
    "/api/appointments/": (OK, OK, OK, NON, OK),
    "/api/consultations/": (OK, OK, OK, NON, OK),
    "/api/follow-ups/": (NON, OK, OK, NON, OK),
    "/api/conflicts/": (OK, OK, OK, NON, OK),
    "/api/profiles/": (OK, OK, NON, OK, OK),
    "/api/audit/": (NON, NON, NON, NON, OK),
    "/api/stats/": (NON, NON, NON, OK, OK),
    "/api/stats/export/": (NON, NON, NON, OK, OK),
    "/api/clinical-config/": (OK, OK, OK, OK, OK),
    "/api/sync/pull/": (OK, OK, OK, OK, OK),
    "/api/facilities/": (OK, OK, OK, OK, OK),
    "/api/auth/me/": (OK, OK, OK, OK, OK),
    "/api/auth/my-data/": (OK, OK, OK, OK, OK),
    "/api/auth/2fa/": (OK, OK, OK, OK, OK),
}

ECRITURES = {
    "/api/children/": (NON, VALIDE, NON, NON, VALIDE),
    "/api/measurements/": (NON, VALIDE, NON, NON, VALIDE),
    "/api/pregnancies/": (VALIDE, VALIDE, NON, NON, VALIDE),
    "/api/cycles/": (VALIDE, NON, NON, NON, VALIDE),
    "/api/food-logs/": (VALIDE, VALIDE, NON, NON, VALIDE),
    "/api/referrals/": (NON, VALIDE, NON, NON, VALIDE),
    "/api/appointments/": (NON, VALIDE, VALIDE, NON, VALIDE),
    "/api/consultations/": (NON, NON, VALIDE, NON, VALIDE),
    "/api/clinical-config/": (NON, NON, NON, NON, VALIDE),
    "/api/profiles/": (NON, VALIDE, NON, VALIDE, VALIDE),
    "/api/sync/push/": (VALIDE, VALIDE, VALIDE, VALIDE, VALIDE),
    "/api/auth/my-data/erase/": (VALIDE, NON, NON, NON, NON),
    "/api/auth/2fa/activate/": (NON, NON, VALIDE, VALIDE, VALIDE),
}


class MatricePermissionsTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.utilisateurs = {
            "beneficiaire": self.femme,
            "asc": self.asc,
            "agent_csb": self.agent,
            "superviseur": self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region),
            "admin": self.admin,
        }

    def verifier(self, matrice, appel):
        for url, attendus in matrice.items():
            for profil, attendu in zip(PROFILS, attendus, strict=True):
                with self.subTest(url=url, profil=profil):
                    self.comme(self.utilisateurs[profil])
                    self.assertEqual(appel(url).status_code, attendu)

    def test_lectures(self):
        self.verifier(LECTURES, self.client.get)

    def test_ecritures(self):
        self.verifier(ECRITURES, lambda url: self.client.post(url, {}, format="json"))

    def test_sans_token_tout_est_refuse(self):
        self.client.force_authenticate(None)
        for url in {**LECTURES, **ECRITURES}:
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 401)

    def test_le_superviseur_ne_lit_aucune_ligne_individuelle(self):
        """Even by id: a supervisor never reaches a health record."""
        petit = self.enfant()
        ligne = self.referencement(enfant=petit)
        self.comme(self.utilisateurs["superviseur"])
        for url in (
            f"/api/children/{petit.pk}/",
            f"/api/referrals/{ligne.pk}/",
            f"/api/children/{petit.pk}/measurements/",
        ):
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 403)
