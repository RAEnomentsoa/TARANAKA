"""Rights of access and erasure, loi malgache n° 2014-038."""

from datetime import date

from django.core.cache import cache

from comptes.models import CodeProfile, User
from nutrition.models import Enfant, JournalAlimentaire, Mesure
from sante_femme.models import Cycle, Grossesse
from synchro.models import JournalAudit, OperationSync
from synchro.outils_tests import BaseApiTest

MES_DONNEES = "/api/auth/my-data/"
EFFACER = "/api/auth/my-data/erase/"


class AccesTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        Cycle.objects.create(user=self.femme, date_debut=date(2026, 10, 1), intensite="moyenne")
        self.grossesse()
        self.petit = self.enfant(mere=self.femme)
        self.mesure(self.petit)
        self.referencement(enfant=self.petit)
        self.enfant(nom="Pas a elle")

    def test_la_beneficiaire_recoit_toutes_ses_donnees(self):
        self.comme(self.femme)
        reponse = self.client.get(MES_DONNEES, HTTP_X_DEVICE_ID="tel-femme")
        self.assertEqual(reponse.status_code, 200)
        donnees = reponse.data
        self.assertEqual(donnees["compte"]["identifiant"], "femme")
        self.assertNotIn("pin_hash", str(donnees))
        self.assertNotIn("password", donnees["compte"])
        self.assertEqual(len(donnees["cycles"]), 1)
        self.assertEqual(len(donnees["grossesses"]), 1)
        self.assertEqual([e["nom"] for e in donnees["enfants"]], ["Hery"])
        self.assertEqual(len(donnees["mesures"]), 1)
        self.assertEqual(len(donnees["referencements"]), 1)
        ligne = JournalAudit.objects.get(action="acces_donnees")
        self.assertEqual((ligne.user, ligne.ligne_id), (self.femme, self.femme.pk))
        self.assertEqual(ligne.details["device_id"], "tel-femme")

    def test_un_professionnel_recoit_son_compte_pas_ses_patients(self):
        self.comme(self.asc)
        donnees = self.client.get(MES_DONNEES).data
        self.assertEqual(donnees["compte"]["profile"], "asc")
        self.assertNotIn("enfants", donnees)

    def test_l_admin_repond_a_une_demande(self):
        self.comme(self.admin)
        reponse = self.client.get(f"/api/profiles/{self.femme.pk}/data/")
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(len(reponse.data["cycles"]), 1)
        ligne = JournalAudit.objects.get(action="acces_donnees")
        self.assertEqual((ligne.user, ligne.ligne_id), (self.admin, self.femme.pk))

    def test_seul_l_admin_exporte_les_donnees_d_un_autre(self):
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region)
        for user in (self.asc, superviseur, self.agent):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(
                    self.client.get(f"/api/profiles/{self.femme.pk}/data/").status_code,
                    403,
                )

    def test_sans_token(self):
        self.assertEqual(self.client.get(MES_DONNEES).status_code, 401)


class EffacementTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        cache.clear()
        self.cycle = Cycle.objects.create(
            user=self.femme,
            date_debut=date(2026, 10, 1),
            intensite="moyenne",
        )
        self.libre = self.grossesse()
        self.referee = self.grossesse()
        self.referencement(code="R-G", grossesse=self.referee)
        self.sans_suite = self.enfant(nom="Mamy", mere=self.femme)
        self.mesure(self.sans_suite)
        JournalAlimentaire.objects.create(
            enfant=self.sans_suite,
            date_jour=date(2026, 11, 1),
            type_allaitement="mixte",
        )
        self.suivi = self.enfant(nom="Tiana", mere=self.femme)
        self.referencement(code="R-E", enfant=self.suivi)
        OperationSync.objects.create(
            cle_idempotence="00000000-0000-0000-0000-000000000001",
            user=self.femme,
            table_nom="cycle",
            operation="create",
            ligne_id=self.cycle.pk,
            statut="applique",
            reponse={"ligne": {"date_debut": "2026-10-01"}},
        )

    def effacer(self, pin="1234", **extra):
        self.comme(self.femme)
        return self.client.post(EFFACER, {"pin": pin, **extra}, format="json")

    def test_pin_obligatoire_et_compte_comme_un_echec(self):
        reponse = self.effacer("9999")
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(reponse.data["code"], "pin_incorrect")
        self.femme.refresh_from_db()
        self.assertEqual(self.femme.tentatives_echouees, 1)
        self.assertTrue(Cycle.objects.filter(pk=self.cycle.pk).exists())

    def test_effacement_par_la_personne(self):
        reponse = self.effacer()
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(
            reponse.data["resume"],
            {
                "cycles_supprimes": 1,
                "grossesses_supprimees": 1,
                "grossesses_conservees_anonymes": 1,
                "enfants_detaches": 2,
                "enfants_supprimes": 0,
                "enfants_conserves_anonymes": 0,
            },
        )
        # Intimate data: gone for good.
        self.assertFalse(Cycle.all_objects.filter(pk=self.cycle.pk).exists())
        self.assertFalse(OperationSync.objects.filter(user=self.femme).exists())
        # Pregnancy without referral: deleted, so the other phones drop it.
        self.libre.refresh_from_db()
        self.assertIsNotNone(Grossesse.all_objects.get(pk=self.libre.pk).deleted_at)
        # Pregnancy with a referral: kept by the centre, but anonymous.
        self.assertTrue(Grossesse.objects.filter(pk=self.referee.pk).exists())
        # Children stay with their ASC, no longer linked to her.
        self.assertFalse(Enfant.objects.filter(mere=self.femme).exists())
        self.assertEqual(Enfant.objects.get(pk=self.sans_suite.pk).nom, "Mamy")

        compte = User.objects.get(pk=self.femme.pk)
        self.assertEqual((compte.nom, compte.prenom, compte.phone), ("Effacé", "Effacé", ""))
        self.assertTrue(compte.identifiant.startswith("efface-"))
        self.assertFalse(compte.is_active)
        self.assertFalse(compte.has_usable_password())
        self.assertIsNotNone(compte.efface_le)

        ligne = JournalAudit.objects.get(action="effacement_donnees")
        self.assertEqual(ligne.ligne_id, self.femme.pk)
        self.assertEqual(ligne.details["demande_par"], "personne")
        self.assertNotIn("Mamy", str(ligne.details))

    def test_plus_de_connexion_ensuite(self):
        self.effacer()
        self.client.force_authenticate(None)
        reponse = self.client.post(
            "/api/auth/login/",
            {"identifiant": "femme", "pin": "1234"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 401)

    def test_avec_les_enfants(self):
        reponse = self.effacer(inclure_enfants=True)
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["resume"]["enfants_supprimes"], 1)
        self.assertEqual(reponse.data["resume"]["enfants_conserves_anonymes"], 1)
        supprime = Enfant.all_objects.get(pk=self.sans_suite.pk)
        self.assertIsNotNone(supprime.deleted_at)
        self.assertEqual(supprime.nom, "Enfant effacé")
        self.assertFalse(Mesure.objects.filter(enfant=supprime).exists())
        self.assertFalse(JournalAlimentaire.objects.filter(enfant=supprime).exists())
        garde = Enfant.objects.get(pk=self.suivi.pk)
        self.assertEqual(garde.nom, "Enfant effacé")
        self.assertIsNone(garde.mere)

    def test_l_asc_apprend_l_effacement_a_la_synchronisation(self):
        self.suivre(self.asc)
        self.comme(self.asc)
        depuis = self.client.get("/api/sync/pull/").data["horodatage_serveur"]
        self.effacer(inclure_enfants=True)
        self.comme(self.asc)
        tables = self.client.get("/api/sync/pull/", {"depuis": depuis}).data["tables"]
        grossesses = {g["id"]: g for g in tables["grossesse"]["lignes"]}
        self.assertIsNotNone(grossesses[str(self.libre.pk)]["deleted_at"])
        self.assertEqual(grossesses[str(self.referee.pk)]["femme"]["nom"], "Effacé")
        enfants = {e["id"]: e for e in tables["enfant"]["lignes"]}
        self.assertIsNotNone(enfants[str(self.sans_suite.pk)]["deleted_at"])

    def test_compte_efface_absent_des_listes_de_l_asc(self):
        self.effacer()
        self.comme(self.asc)
        self.assertNotIn(str(self.femme.pk), self.ids(self.client.get("/api/profiles/")))

    def test_admin_efface_sur_demande(self):
        self.comme(self.admin)
        reponse = self.client.post(f"/api/profiles/{self.femme.pk}/erase/", {}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        ligne = JournalAudit.objects.get(action="effacement_donnees")
        self.assertEqual((ligne.user, ligne.details["demande_par"]), (self.admin, "admin"))
        again = self.client.post(f"/api/profiles/{self.femme.pk}/erase/", {}, format="json")
        self.assertEqual(again.status_code, 400)

    def test_compte_professionnel_non_effacable(self):
        self.comme(self.admin)
        reponse = self.client.post(f"/api/profiles/{self.asc.pk}/erase/", {}, format="json")
        self.assertEqual(reponse.status_code, 400)
        self.assertTrue(User.objects.get(pk=self.asc.pk).is_active)

    def test_seule_la_beneficiaire_efface_elle_meme(self):
        for user in (self.asc, self.agent):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(
                    self.client.post(EFFACER, {"pin": "1234"}, format="json").status_code,
                    403,
                )

    def test_autres_profils_refuses_cote_admin(self):
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        for user in (self.asc, self.agent, superviseur):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(
                    self.client.post(f"/api/profiles/{self.femme.pk}/erase/", {}, format="json").status_code,
                    403,
                )
