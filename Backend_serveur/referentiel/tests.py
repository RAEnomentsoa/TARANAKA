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
        self.comme(self.admin)
        for url in ("provinces", "regions", "facilities", "danger-types", "profile-types"):
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
