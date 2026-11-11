from decimal import Decimal

from django.test import override_settings

from referentiel.models import ReferenceOms
from synchro.outils_tests import BaseApiTest


class ListesTest(BaseApiTest):
    def test_chaque_profil_lit_les_listes(self):
        self.comme(self.femme)
        for url in ("provinces", "regions", "facilities", "danger-types", "profile-types"):
            with self.subTest(url=url):
                reponse = self.client.get(f"/api/{url}/")
                self.assertEqual(reponse.status_code, 200)
                self.assertGreater(reponse.data["count"], 0)

    def test_sans_token_refuse(self):
        self.assertEqual(self.client.get("/api/regions/").status_code, 401)

    def test_lecture_seule(self):
        # Provinces, regions and centres are edited by the admin (tests_territoire).
        self.comme(self.admin)
        for url in ("danger-types", "profile-types"):
            with self.subTest(url=url):
                self.assertEqual(
                    self.client.post(f"/api/{url}/", {}, format="json").status_code,
                    405,
                )

    def test_csb_filtres_par_region(self):
        self.comme(self.asc)
        reponse = self.client.get(f"/api/facilities/?region={self.region.pk}")
        self.assertEqual(
            [ligne["id"] for ligne in reponse.data["results"]],
            [self.csb.pk],
        )

    def test_champs(self):
        self.comme(self.asc)
        reponse = self.client.get(f"/api/regions/{self.region.pk}/")
        self.assertEqual(
            reponse.data,
            {
                "id": self.region.pk,
                "nom": "Analamanga",
                "province_id": self.region.province_id,
            },
        )


class ReferenceOmsTest(BaseApiTest):
    """Issue 6: WHO curves, from the loaded official tables only."""

    URL = "/api/who-reference/"

    def setUp(self):
        super().setUp()
        # Official WHO 2006 rows, boys' weight-for-length 75.0 and 75.5 cm.
        for cle, l, m, s in (
            ("75.0", "-0.3521", "9.5032", "0.08295"),
            ("75.5", "-0.3521", "9.6255", "0.08289"),
        ):
            ReferenceOms.objects.create(
                indicateur="wfl",
                sexe="M",
                cle=Decimal(cle),
                valeur_l=Decimal(l),
                valeur_m=Decimal(m),
                valeur_s=Decimal(s),
                mesure_type="L",
            )

    def test_courbes_calculees_depuis_les_lms_officiels(self):
        self.comme(self.agent)
        reponse = self.client.get(self.URL, {"indicateur": "wfl", "sexe": "M"})
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["unite_cle"], "cm")
        point = reponse.data["points"][0]
        self.assertEqual(point["m"], Decimal("9.5032"))
        # WHO's published SD weights at 75 cm (boys): 7.5, 8.1, 9.5, 11.3, 12.3 kg.
        publies = {"-3": 7.5, "-2": 8.1, "0": 9.5, "2": 11.3, "3": 12.3}
        for z, poids in publies.items():
            self.assertAlmostEqual(point["courbes"][z], poids, delta=0.05)

    def test_filtres_et_pas(self):
        self.comme(self.asc)
        reponse = self.client.get(self.URL, {"indicateur": "wfl", "sexe": "M", "cle_min": "75.5"})
        self.assertEqual([p["cle"] for p in reponse.data["points"]], [Decimal("75.5")])
        reponse = self.client.get(self.URL, {"indicateur": "wfl", "sexe": "M", "pas": "1"})
        self.assertEqual([p["cle"] for p in reponse.data["points"]], [Decimal("75.0")])

    def test_table_non_chargee(self):
        self.comme(self.agent)
        for parametres in ({"indicateur": "wfa", "sexe": "M"}, {"indicateur": "wfl", "sexe": "F"}):
            with self.subTest(**parametres):
                self.assertEqual(self.client.get(self.URL, parametres).status_code, 404)

    def test_parametres_obligatoires(self):
        self.comme(self.agent)
        self.assertEqual(self.client.get(self.URL, {"indicateur": "xyz", "sexe": "M"}).status_code, 400)
        self.assertEqual(self.client.get(self.URL).status_code, 400)

    def test_donnee_de_reference_lisible_par_tous(self):
        from comptes.models import CodeProfile

        for user in (self.femme, self.asc, self.compte("sup", CodeProfile.SUPERVISEUR)):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(
                    self.client.get(self.URL, {"indicateur": "wfl", "sexe": "M"}).status_code,
                    200,
                )
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get(self.URL, {"indicateur": "wfl", "sexe": "M"}).status_code, 401)


@override_settings(
    CORS_ALLOWED_ORIGINS=["https://tableau.taranaka.example"],
    USE_X_FORWARDED_HOST=True,
    ALLOWED_HOSTS=["api.taranaka.example", "testserver"],
)
class DeploiementTest(BaseApiTest):
    """Issues 7 and 8: settings for the reverse proxy and the dashboard."""

    def test_cors_pour_l_origine_du_tableau_de_bord(self):
        reponse = self.client.options(
            "/api/referrals/",
            HTTP_ORIGIN="https://tableau.taranaka.example",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS="authorization, x-device-id",
        )
        self.assertEqual(
            reponse["Access-Control-Allow-Origin"],
            "https://tableau.taranaka.example",
        )
        self.assertIn("x-device-id", reponse["Access-Control-Allow-Headers"])

    def test_pas_de_cors_pour_une_autre_origine(self):
        reponse = self.client.options(
            "/api/referrals/",
            HTTP_ORIGIN="https://ailleurs.example",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET",
        )
        self.assertNotIn("Access-Control-Allow-Origin", reponse)

    def test_liens_avec_l_hote_public(self):
        for numero in range(51):
            self.enfant(nom=f"Enfant {numero}")
        self.comme(self.asc)
        reponse = self.client.get(
            "/api/children/",
            HTTP_X_FORWARDED_HOST="api.taranaka.example",
        )
        self.assertTrue(reponse.data["next"].startswith("http://api.taranaka.example/api/children/"))
