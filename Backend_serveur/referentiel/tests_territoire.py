"""The admin manages the territory (provinces, regions, centres); the others read it."""

from comptes.models import CodeProfile
from referentiel.models import CSB, Province, Region
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

PROVINCES = "/api/provinces/"
REGIONS = "/api/regions/"
CENTRES = "/api/facilities/"


class TerritoireTest(BaseApiTest):
    def test_admin_cree_modifie_supprime(self):
        self.comme(self.admin)
        reponse = self.client.post(PROVINCES, {"nom": "  Toamasina "}, format="json")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["nom"], "Toamasina")
        province = reponse.data["id"]

        reponse = self.client.post(REGIONS, {"nom": "Atsinanana", "province_id": province}, format="json")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        region = reponse.data["id"]

        reponse = self.client.post(
            CENTRES,
            {"name": "CSB2 Tamatave", "type_centre": "csb", "region_id": region, "tel": "034"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        centre = reponse.data["id"]

        reponse = self.client.patch(f"{REGIONS}{region}/", {"nom": "Atsinanana Nord"}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)

        for url in (f"{CENTRES}{centre}/", f"{REGIONS}{region}/", f"{PROVINCES}{province}/"):
            self.assertEqual(self.client.delete(url).status_code, 204, url)
        self.assertFalse(Province.objects.filter(pk=province).exists())
        self.assertEqual(
            JournalAudit.objects.filter(action__startswith="territoire_").count(), 7
        )

    def test_les_autres_lisent_seulement(self):
        for user in (
            self.asc,
            self.agent,
            self.femme,
            self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region),
        ):
            with self.subTest(profil=user.profile.code):
                self.comme(user)
                self.assertEqual(self.client.get(REGIONS).status_code, 200)
                self.assertEqual(
                    self.client.post(PROVINCES, {"nom": "X"}, format="json").status_code, 403
                )
                self.assertEqual(self.client.delete(f"{CENTRES}{self.csb.pk}/").status_code, 403)

    def test_suppression_refusee_si_encore_utilise(self):
        self.comme(self.admin)
        # The province has regions; the region has centres and accounts;
        # the centre has an agent.
        for url in (
            f"{PROVINCES}{self.region.province_id}/",
            f"{REGIONS}{self.region.pk}/",
            f"{CENTRES}{self.csb.pk}/",
        ):
            with self.subTest(url=url):
                reponse = self.client.delete(url)
                self.assertEqual(reponse.status_code, 400)
                self.assertIn("detail", reponse.data)
        self.assertTrue(Region.objects.filter(pk=self.region.pk).exists())
        self.assertTrue(CSB.objects.filter(pk=self.csb.pk).exists())

    def test_region_avec_seulement_des_comptes_refusee(self):
        """A user's region is SET_NULL: the delete must still be refused."""
        self.comme(self.admin)
        vide = Region.objects.create(nom="Vide", province=self.region.province)
        femme = self.compte("f-vide", CodeProfile.BENEFICIAIRE, region=vide)
        self.assertEqual(self.client.delete(f"{REGIONS}{vide.pk}/").status_code, 400)
        femme.refresh_from_db()
        self.assertEqual(femme.region_id, vide.pk)

    def test_doublons_refuses(self):
        self.comme(self.admin)
        reponse = self.client.post(
            REGIONS, {"nom": "analamanga", "province_id": self.region.province_id}, format="json"
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("nom", reponse.data)
        reponse = self.client.post(PROVINCES, {"nom": "   "}, format="json")
        self.assertEqual(reponse.status_code, 400)
