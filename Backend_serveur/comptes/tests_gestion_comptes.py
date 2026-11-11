"""The admin's « Comptes » page: filters, edits, deactivation."""

from comptes.models import CodeProfile
from synchro.outils_tests import BaseApiTest

COMPTES = "/api/profiles/"


class GestionComptesTest(BaseApiTest):
    def test_filtres(self):
        self.comme(self.admin)
        cas = (
            ("profil=asc", {self.asc, self.asc_meme_region, self.autre_asc, self.asc_sans_region}),
            ("profil=agent_csb", {self.agent, self.autre_agent}),
            (f"profil=asc&region={self.autre_region.pk}", {self.autre_asc}),
            ("q=agent2", {self.autre_agent}),
        )
        for filtre, attendus in cas:
            with self.subTest(filtre=filtre):
                reponse = self.client.get(f"{COMPTES}?{filtre}")
                self.assertEqual(self.ids(reponse), {str(u.pk) for u in attendus})

    def test_desactiver_puis_reactiver(self):
        self.comme(self.admin)
        url = f"{COMPTES}{self.agent.pk}/"
        self.assertEqual(self.client.patch(url, {"is_active": False}, format="json").status_code, 200)
        self.assertEqual(self.ids(self.client.get(f"{COMPTES}?profil=agent_csb&actif=false")), {str(self.agent.pk)})
        reponse = self.client.post("/api/auth/login/", {"identifiant": "agent", "pin": "1234"}, format="json")
        self.assertEqual(reponse.status_code, 401)
        self.assertEqual(self.client.patch(url, {"is_active": True}, format="json").status_code, 200)

    def test_changer_le_centre_d_un_agent(self):
        self.comme(self.admin)
        reponse = self.client.patch(
            f"{COMPTES}{self.agent.pk}/", {"csb_id": self.autre_csb.pk, "nom": "Rabe"}, format="json"
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.agent.refresh_from_db()
        self.assertEqual((self.agent.csb_id, self.agent.nom), (self.autre_csb.pk, "Rabe"))

    def test_l_admin_ne_se_bloque_pas_lui_meme(self):
        self.comme(self.admin)
        url = f"{COMPTES}{self.admin.pk}/"
        for donnees in ({"is_active": False}, {"profile_code": CodeProfile.SUPERVISEUR}):
            with self.subTest(donnees=donnees):
                self.assertEqual(self.client.patch(url, donnees, format="json").status_code, 400)
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.is_active)
        # Their own name is fine.
        self.assertEqual(self.client.patch(url, {"prenom": "Nouveau"}, format="json").status_code, 200)
