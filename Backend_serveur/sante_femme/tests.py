import uuid
from datetime import date, timedelta

from django.utils import timezone

from referencement.models import Referencement
from sante_femme.models import Cycle, DangerGrossesse, Grossesse
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

CYCLES = "/api/cycles/"
GROSSESSES = "/api/pregnancies/"
SANS_REFERENCEMENT = f"{GROSSESSES}?danger_sans_referencement=true"


def dangers_url(grossesse):
    return f"{GROSSESSES}{grossesse.pk}/dangers/"


class CyclesTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.le_sien = Cycle.objects.create(
            user=self.femme,
            date_debut=date(2026, 1, 1),
            intensite="moyenne",
        )

    def donnees(self, **extra):
        return {"date_debut": "2026-02-01", "intensite": "forte", **extra}

    def test_asc_n_a_aucun_acces_aux_cycles(self):
        self.comme(self.asc)
        self.assertEqual(self.client.get(CYCLES).status_code, 403)
        self.assertEqual(self.client.get(f"{CYCLES}{self.le_sien.pk}/").status_code, 403)
        self.assertEqual(
            self.client.post(
                CYCLES,
                self.donnees(user_id=str(self.femme.pk)),
                format="json",
            ).status_code,
            403,
        )

    def test_agent_n_a_aucun_acces_aux_cycles(self):
        self.comme(self.agent)
        self.assertEqual(self.client.get(CYCLES).status_code, 403)

    def test_beneficiaire_cree_et_lit_les_siens(self):
        self.comme(self.femme)
        reponse = self.client.post(CYCLES, self.donnees(), format="json")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["user_id"], self.femme.pk)
        self.assertEqual(len(self.client.get(CYCLES).data["results"]), 2)

    def test_beneficiaire_ne_voit_pas_les_cycles_d_une_autre(self):
        self.comme(self.autre_femme)
        self.assertEqual(self.client.get(CYCLES).data["results"], [])
        self.assertEqual(self.client.get(f"{CYCLES}{self.le_sien.pk}/").status_code, 404)

    def test_beneficiaire_ne_cree_pas_pour_une_autre(self):
        self.comme(self.femme)
        reponse = self.client.post(
            CYCLES,
            self.donnees(user_id=str(self.autre_femme.pk)),
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("user_id", reponse.data)

    def test_mise_a_jour_et_suppression(self):
        self.comme(self.femme)
        url = f"{CYCLES}{self.le_sien.pk}/"
        reponse = self.client.patch(url, {"symptome": "Fatigue", "version": 1}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["version"], 2)
        self.assertEqual(
            self.client.patch(url, {"symptome": "X", "version": 1}, format="json").status_code,
            409,
        )
        self.assertEqual(self.client.delete(url).status_code, 204)
        self.assertEqual(self.client.get(url).status_code, 404)

    def test_admin_voit_tout(self):
        self.comme(self.admin)
        self.assertEqual(self.ids(self.client.get(CYCLES)), {str(self.le_sien.pk)})


class AccesGrossessesTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.dans_region = self.grossesse(self.femme)
        self.hors_region = self.grossesse(self.autre_femme)

    def test_asc_voit_les_grossesses_de_sa_region(self):
        for user in (self.asc, self.asc_meme_region):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(
                    self.ids(self.client.get(GROSSESSES)),
                    {str(self.dans_region.pk)},
                )
                self.assertEqual(
                    self.client.get(f"{GROSSESSES}{self.hors_region.pk}/").status_code,
                    404,
                )

    def test_asc_sans_region_ne_voit_pas_les_femmes_sans_region(self):
        self.grossesse(self.femme_sans_region)
        self.comme(self.asc_sans_region)
        self.assertEqual(self.client.get(GROSSESSES).data["results"], [])

    def test_asc_cree_pour_une_femme_de_sa_region_seulement(self):
        self.comme(self.asc)
        donnees = {"ddr": "2026-01-01", "dpa": "2026-10-08"}
        reponse = self.client.post(
            GROSSESSES,
            {**donnees, "user_id": str(self.femme.pk)},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        reponse = self.client.post(
            GROSSESSES,
            {**donnees, "user_id": str(self.autre_femme.pk)},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("user_id", reponse.data)
        reponse = self.client.post(GROSSESSES, donnees, format="json")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("user_id", reponse.data)

    def test_asc_modifie_une_grossesse_de_sa_region(self):
        self.comme(self.asc)
        reponse = self.client.patch(
            f"{GROSSESSES}{self.dans_region.pk}/",
            {"dpa": "2026-10-10", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)

    def test_la_femme_d_une_grossesse_ne_change_pas(self):
        self.comme(self.asc)
        autre = self.compte("femme4", "beneficiaire", region=self.region)
        reponse = self.client.patch(
            f"{GROSSESSES}{self.dans_region.pk}/",
            {"user_id": str(autre.pk), "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("user_id", reponse.data)

    def test_beneficiaire_acces_complet_aux_siennes(self):
        self.comme(self.femme)
        self.assertEqual(self.ids(self.client.get(GROSSESSES)), {str(self.dans_region.pk)})
        reponse = self.client.post(
            GROSSESSES,
            {"ddr": "2026-02-01", "dpa": "2026-11-08"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["user_id"], self.femme.pk)
        self.assertEqual(
            self.client.get(f"{GROSSESSES}{self.hors_region.pk}/").status_code,
            404,
        )

    def test_agent_lit_seulement_les_grossesses_referencees_a_son_csb(self):
        self.referencement(grossesse=self.dans_region, csb=self.csb)
        self.referencement(code="R-2", grossesse=self.hors_region, csb=self.autre_csb)
        self.comme(self.agent)
        reponse = self.client.get(GROSSESSES)
        self.assertEqual(self.ids(reponse), {str(self.dans_region.pk)})
        self.assertEqual(
            reponse.data["results"][0]["femme"],
            {"nom": "Femme", "prenom": "Test"},
        )
        self.assertEqual(
            self.client.get(f"{GROSSESSES}{self.hors_region.pk}/").status_code,
            404,
        )
        self.assertEqual(
            self.client.patch(
                f"{GROSSESSES}{self.dans_region.pk}/",
                {"dpa": "2026-10-10", "version": 1},
                format="json",
            ).status_code,
            403,
        )

    def test_agent_lit_les_signes_de_la_grossesse_referencee(self):
        self.referencement(grossesse=self.dans_region, csb=self.csb)
        DangerGrossesse.objects.create(
            grossesse=self.dans_region,
            type_danger_grossesse=self.type_danger,
            date_signalement=timezone.now(),
        )
        self.comme(self.agent)
        reponse = self.client.get(dangers_url(self.dans_region))
        self.assertEqual(len(reponse.data["results"]), 1)
        self.assertEqual(
            self.client.post(
                dangers_url(self.dans_region),
                {"type_danger_grossesse_id": self.type_danger.pk},
                format="json",
            ).status_code,
            403,
        )
        self.assertEqual(self.client.get(dangers_url(self.hors_region)).status_code, 404)

    def test_grossesse_avec_referencement_non_supprimable(self):
        self.referencement(grossesse=self.dans_region)
        self.comme(self.asc)
        reponse = self.client.delete(f"{GROSSESSES}{self.dans_region.pk}/")
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(reponse.data["code"], "referencement_existant")

    def test_suppression_emporte_les_signes(self):
        danger = DangerGrossesse.objects.create(
            grossesse=self.dans_region,
            type_danger_grossesse=self.type_danger,
            date_signalement=timezone.now(),
        )
        self.comme(self.asc)
        self.assertEqual(
            self.client.delete(f"{GROSSESSES}{self.dans_region.pk}/").status_code,
            204,
        )
        self.assertIsNotNone(Grossesse.all_objects.get(pk=self.dans_region.pk).deleted_at)
        self.assertIsNotNone(DangerGrossesse.all_objects.get(pk=danger.pk).deleted_at)


class DangersTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.ligne = self.grossesse()

    def signaler(self, grossesse=None, **extra):
        return self.client.post(
            dangers_url(grossesse or self.ligne),
            {
                "type_danger_grossesse_id": self.type_danger.pk,
                "date_signalement": "2026-03-01T08:00:00Z",
                **extra,
            },
            format="json",
        )

    def ids_sans_referencement(self):
        return self.ids(self.client.get(SANS_REFERENCEMENT))

    def test_asc_avec_csb_cree_un_referencement_urgent(self):
        self.comme(self.asc)
        reponse = self.signaler(csb_id=self.csb.pk)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        referencement = Referencement.objects.get()
        self.assertEqual(referencement.origine, "grossesse")
        self.assertEqual(referencement.priorite, "urgente")
        self.assertEqual(referencement.grossesse, self.ligne)
        self.assertEqual(referencement.asc, self.asc)
        self.assertEqual(referencement.csb, self.csb)
        self.assertIn("Saignement", referencement.motif)
        self.assertEqual(reponse.data["referencement_id"], referencement.pk)
        self.assertEqual(reponse.data["code_unique"], referencement.code_unique)
        self.assertIsNone(reponse.data["avertissement"])
        self.assertEqual(self.ids_sans_referencement(), set())

    def test_asc_sans_csb_garde_le_signe_avec_un_avertissement(self):
        self.comme(self.asc)
        reponse = self.signaler()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(DangerGrossesse.objects.count(), 1)
        self.assertEqual(Referencement.objects.count(), 0)
        self.assertIsNone(reponse.data["referencement_id"])
        self.assertEqual(
            reponse.data["avertissement"],
            "Référencement non créé : CSB manquant",
        )
        self.assertEqual(self.ids_sans_referencement(), {str(self.ligne.pk)})

    def test_csb_null_ou_illisible_garde_le_signe(self):
        self.comme(self.asc)
        for valeur in (None, "abc", [1]):
            with self.subTest(valeur=valeur):
                reponse = self.signaler(csb_id=valeur)
                self.assertEqual(reponse.status_code, 201, reponse.data)
                self.assertEqual(
                    reponse.data["avertissement"],
                    "Référencement non créé : CSB manquant",
                )

    def test_csb_inconnu_garde_le_signe(self):
        self.comme(self.asc)
        reponse = self.signaler(csb_id=999999)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(
            reponse.data["avertissement"],
            "Référencement non créé : CSB inconnu",
        )
        self.assertEqual(DangerGrossesse.objects.count(), 1)

    def test_beneficiaire_sans_referencement_ni_avertissement(self):
        self.comme(self.femme)
        reponse = self.signaler(csb_id=self.csb.pk)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(Referencement.objects.count(), 0)
        self.assertIsNone(reponse.data["avertissement"])
        self.comme(self.asc)
        self.assertEqual(self.ids_sans_referencement(), {str(self.ligne.pk)})

    def test_date_absente_remplacee_par_maintenant(self):
        self.comme(self.femme)
        reponse = self.client.post(
            dangers_url(self.ligne),
            {"type_danger_grossesse_id": self.type_danger.pk},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertIsNotNone(reponse.data["date_signalement"])

    def test_nouveau_signe_apres_un_ancien_referencement_reapparait(self):
        self.comme(self.asc)
        self.signaler(csb_id=self.csb.pk)
        self.assertEqual(self.ids_sans_referencement(), set())
        self.comme(self.femme)
        self.signaler()
        self.comme(self.asc)
        self.assertEqual(self.ids_sans_referencement(), {str(self.ligne.pk)})

    def test_le_referencement_fait_disparaitre_du_filtre(self):
        self.comme(self.femme)
        self.signaler()
        self.comme(self.asc)
        self.assertEqual(self.ids_sans_referencement(), {str(self.ligne.pk)})
        reponse = self.client.post(
            "/api/referrals/",
            {
                "origine": "grossesse",
                "grossesse_id": str(self.ligne.pk),
                "csb_id": self.csb.pk,
                "priorite": "urgente",
                "motif": "Saignement",
            },
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(self.ids_sans_referencement(), set())

    def test_filtre_false_et_signe_supprime(self):
        sans_signe = self.grossesse()
        self.comme(self.asc)
        reponse = self.signaler()
        self.assertEqual(
            self.ids(self.client.get(f"{GROSSESSES}?danger_sans_referencement=false")),
            {str(sans_signe.pk)},
        )
        url = f"{dangers_url(self.ligne)}{reponse.data['id']}/"
        self.assertEqual(self.client.delete(url).status_code, 204)
        self.assertEqual(self.ids_sans_referencement(), set())

    def test_le_filtre_reste_limite_a_la_region(self):
        hors_region = self.grossesse(self.autre_femme)
        DangerGrossesse.objects.create(
            grossesse=hors_region,
            type_danger_grossesse=self.type_danger,
            date_signalement=timezone.now(),
        )
        self.comme(self.asc)
        self.assertEqual(self.ids_sans_referencement(), set())

    def test_renvoi_du_meme_signe_ne_cree_pas_de_doublon(self):
        self.comme(self.asc)
        identifiant = str(uuid.uuid4())
        self.signaler(id=identifiant, csb_id=self.csb.pk)
        reponse = self.signaler(id=identifiant, csb_id=self.csb.pk)
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(DangerGrossesse.objects.count(), 1)
        self.assertEqual(Referencement.objects.count(), 1)

    def test_grossesse_hors_region_refusee(self):
        hors_region = self.grossesse(self.autre_femme)
        self.comme(self.asc)
        self.assertEqual(self.signaler(grossesse=hors_region).status_code, 404)
        self.assertEqual(DangerGrossesse.objects.count(), 0)

    def test_type_inconnu_refuse(self):
        self.comme(self.asc)
        reponse = self.client.post(
            dangers_url(self.ligne),
            {"type_danger_grossesse_id": 999999},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("type_danger_grossesse_id", reponse.data)

    def test_mise_a_jour_avec_version_sans_nouveau_referencement(self):
        self.comme(self.asc)
        creation = self.signaler(csb_id=self.csb.pk)
        url = f"{dangers_url(self.ligne)}{creation.data['id']}/"
        nouvelle_date = (timezone.now() - timedelta(days=1)).isoformat()
        reponse = self.client.patch(
            url,
            {"date_signalement": nouvelle_date, "version": 1, "csb_id": self.csb.pk},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["version"], 2)
        self.assertEqual(Referencement.objects.count(), 1)
        self.assertEqual(
            self.client.patch(url, {"version": 1}, format="json").status_code,
            409,
        )

    def test_creation_journalisee(self):
        self.comme(self.asc)
        self.signaler(csb_id=self.csb.pk)
        self.assertEqual(
            set(
                JournalAudit.objects.filter(action="create").values_list(
                    "table_nom",
                    flat=True,
                )
            ),
            {"danger_grossesse", "referencement"},
        )
