"""Connected beneficiary (D16): registration, cycle sharing, the file a
health worker opens, and the sync of her own data."""


import uuid
from datetime import UTC, date, datetime
from decimal import Decimal

from comptes.models import CodeProfile, SuiviBeneficiaire, User
from nutrition.models import Tetee, VaccinFait
from sante_femme.models import (
    AlimentationFemme,
    ContactSoin,
    Cycle,
    CycleJour,
    MouvementBebe,
    SuiviGrossesse,
)
from sante_femme.models import DangerGrossesse
from statistiques.services import calculer, masquer
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

INSCRIPTION = "/api/auth/register-beneficiary/"
ME = "/api/auth/me/"
BENEFICIAIRES = "/api/beneficiaries/"
LOOKUP = f"{BENEFICIAIRES}lookup/"
PUSH = "/api/sync/push/"
PULL = "/api/sync/pull/"


def operation(table, donnees, ligne_id=None, op="create", **extra):
    return {
        "cle_idempotence": str(uuid.uuid4()),
        "table": table,
        "operation": op,
        "id": str(ligne_id or uuid.uuid4()),
        "donnees": donnees,
        **extra,
    }


class InscriptionTest(BaseApiTest):
    def donnees(self, **extra):
        return {
            "prenom": "Voahangy",
            "region_id": self.region.pk,
            "pin": "4821",
            "consentement": True,
            **extra,
        }

    def test_compte_cree_et_connecte_sans_validation(self):
        self.client.force_authenticate(None)
        reponse = self.client.post(
            INSCRIPTION, self.donnees(phone="034 00 000 09"), format="json",
            HTTP_X_DEVICE_ID="tel-voa",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        utilisateur = reponse.data["utilisateur"]
        self.assertRegex(utilisateur["identifiant"], r"^voahangy\.\d{4}$")
        self.assertRegex(utilisateur["code_beneficiaire"], r"^[A-HJ-KM-NP-Z2-9]{6}$")
        self.assertEqual(utilisateur["profile"]["code"], CodeProfile.BENEFICIAIRE)
        self.assertFalse(utilisateur["partage_cycle"])
        user = User.objects.get(pk=utilisateur["id"])
        self.assertTrue(user.consentement)
        self.assertTrue(user.check_password("4821"))
        ligne = JournalAudit.objects.get(action="inscription_beneficiaire")
        self.assertEqual(ligne.details["device_id"], "tel-voa")
        # The tokens work straight away.
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {reponse.data['access']}")
        self.assertEqual(str(self.client.get(ME).data["id"]), str(user.pk))
        # And she can sign in again with the generated username, any case.
        self.client.credentials()
        connexion = self.client.post(
            "/api/auth/login/",
            {"identifiant": utilisateur["identifiant"].upper(), "pin": "4821"},
            format="json",
        )
        self.assertEqual(connexion.status_code, 200, connexion.data)

    def test_prenom_accentue_et_identifiants_distincts(self):
        self.client.force_authenticate(None)
        premier = self.client.post(INSCRIPTION, self.donnees(prenom="Héry"), format="json")
        second = self.client.post(INSCRIPTION, self.donnees(prenom="Héry"), format="json")
        a, b = premier.data["utilisateur"], second.data["utilisateur"]
        self.assertTrue(a["identifiant"].startswith("hery."))
        self.assertNotEqual(a["identifiant"], b["identifiant"])
        self.assertNotEqual(a["code_beneficiaire"], b["code_beneficiaire"])

    def test_refus(self):
        self.client.force_authenticate(None)
        cas = {
            "consentement": self.donnees(consentement=False),
            "region_id": {k: v for k, v in self.donnees().items() if k != "region_id"},
            "pin": self.donnees(pin="12"),
            "prenom": self.donnees(prenom=""),
        }
        for champ, donnees in cas.items():
            with self.subTest(champ=champ):
                reponse = self.client.post(INSCRIPTION, donnees, format="json")
                self.assertEqual(reponse.status_code, 400)
                self.assertIn(champ, reponse.data)
        self.assertFalse(User.objects.filter(prenom="Voahangy").exists())

    def test_le_profil_n_est_pas_choisi_par_le_telephone(self):
        self.client.force_authenticate(None)
        reponse = self.client.post(
            INSCRIPTION, self.donnees(profile_code="admin", is_staff=True), format="json"
        )
        self.assertEqual(reponse.status_code, 201)
        user = User.objects.get(pk=reponse.data["utilisateur"]["id"])
        self.assertEqual(user.profile.code, CodeProfile.BENEFICIAIRE)
        self.assertFalse(user.is_staff)


class PartageCycleTest(BaseApiTest):
    def test_activer_puis_arreter_efface_le_cycle_du_serveur(self):
        self.comme(self.femme)
        reponse = self.client.patch(ME, {"partage_cycle": True}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertTrue(reponse.data["utilisateur"]["partage_cycle"])
        self.assertEqual(
            self.client.post(
                "/api/cycles/", {"date_debut": "2026-10-01"}, format="json"
            ).status_code,
            201,
        )
        CycleJour.objects.create(user=self.femme, date_jour=date(2026, 10, 2), flux="moyen")
        reponse = self.client.patch(ME, {"partage_cycle": False}, format="json")
        self.assertEqual(reponse.data["lignes_supprimees"], 2)
        self.assertFalse(Cycle.all_objects.filter(user=self.femme).exists())
        self.assertFalse(CycleJour.all_objects.filter(user=self.femme).exists())
        self.assertTrue(JournalAudit.objects.filter(action="partage_cycle_desactive").exists())

    def test_reserve_a_la_beneficiaire(self):
        self.comme(self.asc)
        reponse = self.client.patch(ME, {"partage_cycle": True}, format="json")
        self.assertEqual(reponse.status_code, 403)


class DossierTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.femme.code_beneficiaire = "K7QM4Z"
        self.femme.phone = "034 11 111 11"
        self.femme.save()
        self.autre_femme.code_beneficiaire = "P3RT8W"
        self.autre_femme.save()
        self.grossesse_femme = self.grossesse(self.femme)
        self.petit = self.enfant(mere=self.femme, asc=self.autre_asc, nom="Soa")
        self.mesure(self.petit)
        Cycle.objects.create(user=self.femme, date_debut=date(2026, 10, 1))

    def test_liste_de_la_zone_avec_recherche(self):
        self.comme(self.asc)
        reponse = self.client.get(BENEFICIAIRES)
        self.assertEqual(reponse.status_code, 200)
        lignes = {ligne["id"]: ligne for ligne in reponse.data["results"]}
        self.assertEqual(set(lignes), {str(self.femme.pk)})
        ligne = lignes[str(self.femme.pk)]
        self.assertFalse(ligne["suivie"])
        self.assertTrue(ligne["grossesse_en_cours"])
        self.assertEqual(ligne["nb_enfants"], 1)
        self.assertNotIn("grossesses", ligne)
        for texte, attendu in (("Femme", 1), ("k7q-m4z", 1), ("0341", 0), ("Inconnue", 0)):
            with self.subTest(q=texte):
                reponse = self.client.get(BENEFICIAIRES, {"q": texte})
                self.assertEqual(len(reponse.data["results"]), attendu)

    def test_ouvrir_le_dossier_fait_suivre_et_journalise(self):
        self.comme(self.asc)
        self.assertEqual(self.client.get("/api/pregnancies/").data["results"], [])
        reponse = self.client.get(f"{BENEFICIAIRES}{self.femme.pk}/", HTTP_X_DEVICE_ID="tel-asc")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["beneficiaire"]["code_beneficiaire"], "K7QM4Z")
        self.assertEqual(len(reponse.data["grossesses"]), 1)
        self.assertEqual([e["nom"] for e in reponse.data["enfants"]], ["Soa"])
        self.assertEqual(len(reponse.data["mesures"]), 1)
        # Her cycle is not shared.
        self.assertEqual(reponse.data["cycles"], [])
        self.assertTrue(
            SuiviBeneficiaire.objects.filter(agent=self.asc, beneficiaire=self.femme).exists()
        )
        ligne = JournalAudit.objects.get(action="consultation_dossier")
        self.assertEqual((ligne.user, ligne.ligne_id), (self.asc, self.femme.pk))
        # From now on, the ASC's pull carries her file.
        tables = self.client.get(PULL).data["tables"]
        self.assertEqual(
            [g["id"] for g in tables["grossesse"]["lignes"]], [str(self.grossesse_femme.pk)]
        )
        self.assertIn(str(self.petit.pk), [e["id"] for e in tables["enfant"]["lignes"]])
        self.assertTrue(self.client.get(BENEFICIAIRES).data["results"][0]["suivie"])

    def test_cycle_dans_le_dossier_si_partage(self):
        self.femme.partage_cycle = True
        self.femme.save()
        self.comme(self.asc)
        reponse = self.client.get(f"{BENEFICIAIRES}{self.femme.pk}/")
        self.assertEqual(len(reponse.data["cycles"]), 1)

    def test_hors_zone_seulement_par_le_code(self):
        self.comme(self.asc)
        self.assertEqual(
            self.client.get(f"{BENEFICIAIRES}{self.autre_femme.pk}/").status_code, 404
        )
        reponse = self.client.post(LOOKUP, {"code": "p3r-t8w"}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["beneficiaire"]["id"], self.autre_femme.pk)
        # Followed: her file now opens directly.
        self.assertEqual(
            self.client.get(f"{BENEFICIAIRES}{self.autre_femme.pk}/").status_code, 200
        )
        reponse = self.client.post(LOOKUP, {"code": "AAAAAA"}, format="json")
        self.assertEqual(reponse.status_code, 404)

    def test_agent_csb_zone_du_centre(self):
        self.comme(self.agent)
        self.assertEqual(self.ids(self.client.get(BENEFICIAIRES)), {str(self.femme.pk)})
        self.assertEqual(self.client.get("/api/children/").data["results"], [])
        self.client.get(f"{BENEFICIAIRES}{self.femme.pk}/")
        self.assertEqual(self.ids(self.client.get("/api/children/")), {str(self.petit.pk)})
        # Reading only: the centre doesn't write her pregnancy.
        reponse = self.client.patch(
            f"/api/pregnancies/{self.grossesse_femme.pk}/",
            {"terminee": True, "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)

    def test_agent_csb_ouvre_une_femme_referee_a_son_centre(self):
        """Out of the centre's region, but her pregnancy was referred to it."""
        grossesse = self.grossesse(self.autre_femme)
        self.comme(self.agent)
        url = f"{BENEFICIAIRES}{self.autre_femme.pk}/"
        self.assertEqual(self.client.get(url).status_code, 404)
        self.referencement(code="R-G", grossesse=grossesse, csb=self.csb)
        reponse = self.client.get(url)
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(len(reponse.data["referencements"]), 1)
        # Opening her file made the centre follow her: she is in its list now.
        self.assertIn(str(self.autre_femme.pk), self.ids(self.client.get(BENEFICIAIRES)))
        # The other centre still can't.
        self.comme(self.autre_agent)
        self.assertEqual(self.client.get(f"{BENEFICIAIRES}{self.femme.pk}/").status_code, 404)

    def test_la_fiche_enfant_donne_la_mere(self):
        self.suivre(self.agent)
        self.comme(self.agent)
        reponse = self.client.get(f"/api/children/{self.petit.pk}/")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(
            reponse.data["mere"],
            {"id": str(self.femme.pk), "nom": "Femme", "prenom": "Test"},
        )

    def test_ne_plus_suivre(self):
        self.suivre(self.asc)
        self.comme(self.asc)
        reponse = self.client.post(f"{BENEFICIAIRES}{self.femme.pk}/unfollow/")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(self.client.get("/api/pregnancies/").data["results"], [])
        self.assertEqual(
            self.client.post(f"{BENEFICIAIRES}{self.femme.pk}/unfollow/").status_code, 404
        )

    def test_refuse_aux_autres_profils(self):
        for user in (self.femme, self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region)):
            with self.subTest(profil=user.profile.code):
                self.comme(user)
                self.assertEqual(self.client.get(BENEFICIAIRES).status_code, 403)
                self.assertEqual(
                    self.client.post(LOOKUP, {"code": "K7QM4Z"}, format="json").status_code,
                    403,
                )

    def test_compte_efface_introuvable(self):
        self.suivre(self.asc)
        self.comme(self.femme)
        self.client.post("/api/auth/my-data/erase/", {"pin": "1234"}, format="json")
        self.comme(self.asc)
        self.assertEqual(self.client.get(BENEFICIAIRES).data["results"], [])
        self.assertEqual(self.client.get(f"{BENEFICIAIRES}{self.femme.pk}/").status_code, 404)


class InscriptionParAscTest(BaseApiTest):
    def test_asc_inscrit_une_femme_sans_telephone(self):
        """Cahier §3.2.A: the username and code are generated, the ASC follows her."""
        self.comme(self.asc)
        reponse = self.client.post(
            "/api/profiles/",
            {"prenom": "Lalao", "pin": "2468", "consentement": True},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertRegex(reponse.data["identifiant"], r"^lalao\.\d{4}$")
        self.assertTrue(reponse.data["code_beneficiaire"])
        femme = User.objects.get(pk=reponse.data["id"])
        self.assertEqual(femme.region, self.region)
        self.assertTrue(SuiviBeneficiaire.objects.filter(agent=self.asc, beneficiaire=femme).exists())

    def test_identifiant_toujours_obligatoire_pour_un_professionnel(self):
        self.comme(self.admin)
        reponse = self.client.post(
            "/api/profiles/",
            {"prenom": "Rado", "nom": "R", "pin": "2468", "profile_code": "asc"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("identifiant", reponse.data)


class SynchronisationBeneficiaireTest(BaseApiTest):
    """Her phone pushes everything; the health worker who follows her pulls it."""

    def setUp(self):
        super().setUp()
        self.ma_grossesse = self.grossesse(self.femme)
        self.mon_enfant = self.enfant(mere=self.femme, asc=self.autre_asc)

    def pousser(self, *operations):
        self.comme(self.femme)
        reponse = self.client.post(PUSH, {"operations": list(operations)}, format="json")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        return reponse.data["resultats"]

    def test_toutes_ses_tables(self):
        g, e = str(self.ma_grossesse.pk), str(self.mon_enfant.pk)
        resultats = self.pousser(
            operation("contact_soin", {"grossesse_id": g, "type": "cpn", "numero": 1,
                                       "date_faite": "2026-03-01"}),
            operation("suivi_grossesse", {"grossesse_id": g, "date_jour": "2026-03-01",
                                          "poids_kg": "61.50", "tension_sys": 120,
                                          "tension_dia": 80, "source": "professionnel"}),
            operation("mouvement_bebe", {"grossesse_id": g, "date_jour": "2026-06-01",
                                         "mouvements": 12}),
            operation("mouvement_evenement", {"grossesse_id": g, "type": "coup_pied",
                                              "horodatage": "2026-06-01T08:00:00Z"}),
            operation("alimentation_femme", {"date_jour": "2026-06-01",
                                             "groupes": ["feuilles", "proteines"]}),
            operation("vaccin_fait", {"enfant_id": e, "code": "bcg",
                                      "date_faite": "2025-01-02", "confirme_carnet": True}),
            operation("tetee", {"enfant_id": e, "type": "sein", "duree_min": 15,
                                "horodatage": "2025-01-02T06:00:00Z"}),
            operation("journal_alimentaire", {"enfant_id": e, "date_jour": "2025-08-01",
                                              "type_allaitement": "mixte",
                                              "aliments": ["riz", "oeuf"], "repas": 3,
                                              "laits": 1, "g2_cereales_tubercules": True,
                                              "g6_oeufs": True}),
        )
        self.assertEqual([r["statut"] for r in resultats], ["applique"] * 8, resultats)
        self.assertEqual(SuiviGrossesse.objects.get().poids_kg, Decimal("61.50"))
        self.assertEqual(VaccinFait.objects.get().code, "bcg")

        # Twice the same dose: refused, not duplicated.
        doublon = self.pousser(
            operation("vaccin_fait", {"enfant_id": e, "code": "bcg", "date_faite": "2025-01-03"})
        )[0]
        self.assertEqual(doublon["statut"], "erreur", doublon)
        self.assertEqual(VaccinFait.objects.count(), 1)

        # An ASC who doesn't follow her sees none of it...
        self.comme(self.asc)
        tables = self.client.get(PULL).data["tables"]
        self.assertEqual(tables["contact_soin"]["lignes"], [])
        self.assertEqual(tables["tetee"]["lignes"], [])
        # ...until he follows her.
        self.suivre(self.asc)
        tables = self.client.get(PULL).data["tables"]
        for table in (
            "contact_soin",
            "suivi_grossesse",
            "mouvement_bebe",
            "mouvement_evenement",
            "alimentation_femme",
            "vaccin_fait",
            "tetee",
            "journal_alimentaire",
        ):
            with self.subTest(table=table):
                self.assertEqual(len(tables[table]["lignes"]), 1)
        # The ASC never writes her baby's feeds.
        refuse = self.client.post(
            PUSH,
            {"operations": [operation("tetee", {"enfant_id": e, "type": "sein",
                                                "horodatage": "2025-01-03T06:00:00Z"})]},
            format="json",
        ).data["resultats"][0]
        self.assertEqual(refuse["statut"], "refuse", refuse)

    def test_pas_sur_la_grossesse_d_une_autre(self):
        autre = self.grossesse(self.autre_femme)
        resultat = self.pousser(
            operation("contact_soin", {"grossesse_id": str(autre.pk), "type": "cpn",
                                       "numero": 1, "date_faite": "2026-03-01"})
        )[0]
        self.assertNotEqual(resultat["statut"], "applique")
        self.assertFalse(ContactSoin.objects.exists())

    def test_effacement_emporte_les_nouvelles_tables(self):
        AlimentationFemme.objects.create(user=self.femme, date_jour=date(2026, 6, 1))
        MouvementBebe.objects.create(grossesse=self.ma_grossesse, date_jour=date(2026, 6, 1),
                                     mouvements=10)
        Tetee.objects.create(enfant=self.mon_enfant, type="sein",
                             horodatage="2025-01-02T06:00:00Z")
        self.comme(self.femme)
        reponse = self.client.post(
            "/api/auth/my-data/erase/", {"pin": "1234", "inclure_enfants": True}, format="json"
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertFalse(AlimentationFemme.all_objects.exists())
        self.assertFalse(MouvementBebe.objects.exists())
        self.assertFalse(Tetee.objects.exists())


class StatistiquesTest(BaseApiTest):
    def test_une_pesee_a_la_maison_n_est_pas_un_depistage(self):
        enfant = self.enfant(mere=self.femme)
        self.mesure(enfant, date_mesure=date(2026, 3, 1))
        self.mesure(enfant, asc=None, date_mesure=date(2026, 3, 2))
        indicateurs = calculer(date(2026, 3, 1), date(2026, 3, 31))
        self.assertEqual(indicateurs["depistages"], 1)


class IndicateursBeneficiairesTest(BaseApiTest):
    """The supervisor's indicators on the connected beneficiaries (D16)."""

    DEBUT, FIN = date(2026, 11, 1), date(2026, 11, 30)

    def setUp(self):
        super().setUp()
        self.femmes = [
            self.compte(f"mere{n}", CodeProfile.BENEFICIAIRE, region=self.region)
            for n in range(6)
        ]
        for n, femme in enumerate(self.femmes):
            grossesse = self.grossesse(femme)
            DangerGrossesse.objects.create(
                grossesse=grossesse,
                code="saignement_vaginal",
                date_signalement=datetime(2026, 11, 3 + n, tzinfo=UTC),
            )
            self.referencement(
                code=f"RG-{n}",
                grossesse=grossesse,
                date_referencement=datetime(2026, 11, 3 + n, tzinfo=UTC),
                date_reception=datetime(2026, 11, 4 + n, tzinfo=UTC),
            )
            # Aged 12 to 23 months on the last day; all had penta 3.
            enfant = self.enfant(
                mere=femme, nom=f"Bebe {n}", date_naissance=date(2025, 6, 1)
            )
            VaccinFait.objects.create(
                enfant=enfant, code="penta3", date_faite=date(2026, 11, 2)
            )

    def indicateurs(self):
        return masquer(calculer(self.DEBUT, self.FIN, None))["indicateurs"]

    def test_compteurs(self):
        indicateurs = self.indicateurs()
        self.assertEqual(indicateurs["beneficiaires_actives"], 6)
        self.assertEqual(indicateurs["grossesses_suivies"], 6)
        self.assertEqual(indicateurs["signes_danger"], 6)
        self.assertEqual(indicateurs["referencements_grossesse"], 6)
        self.assertEqual(indicateurs["referencements_grossesse_arrives"], 6)
        self.assertEqual(indicateurs["taux_arrivee_grossesse_pct"], 100.0)
        self.assertEqual(indicateurs["enfants_vaccines"], 6)
        self.assertEqual(indicateurs["couverture_vaccinale_pct"], 100.0)

    def test_couverture_masquee_si_un_a_quatre_enfants_sans_vaccin(self):
        VaccinFait.objects.filter(enfant__nom="Bebe 0").delete()
        brut = calculer(self.DEBUT, self.FIN, None)
        self.assertEqual(brut["couverture_vaccinale_pct"], 83.3)
        resultat = masquer(brut)
        self.assertIsNone(resultat["indicateurs"]["couverture_vaccinale_pct"])
        self.assertIn("couverture_vaccinale_pct", resultat["masques"])

    def test_referencements_enfant_de_un_a_quatre_cachent_ceux_de_grossesse(self):
        """Total − pregnancy = 1 child referral: one of the two is hidden."""
        self.referencement(
            code="RE-1", enfant=self.enfant(nom="Ref"),
            date_referencement=datetime(2026, 11, 5, tzinfo=UTC),
        )
        indicateurs = self.indicateurs()
        self.assertEqual(indicateurs["referencements"], 7)
        self.assertIsNone(indicateurs["referencements_grossesse"])
        self.assertIsNone(indicateurs["taux_arrivee_grossesse_pct"])

    def test_petits_effectifs(self):
        DangerGrossesse.objects.exclude(grossesse__user=self.femmes[0]).delete()
        self.assertIsNone(self.indicateurs()["signes_danger"])


class UnJourParFemmeTest(BaseApiTest):
    def test_meme_jour_refuse_sans_envoyer_user_id(self):
        self.comme(self.femme)
        donnees = {"date_jour": "2026-06-01", "groupes": ["feuilles"]}
        premier = self.client.post("/api/women-food-logs/", donnees, format="json")
        self.assertEqual(premier.status_code, 201, premier.data)
        second = self.client.post("/api/women-food-logs/", donnees, format="json")
        self.assertEqual(second.status_code, 400)
        self.assertIn("non_field_errors", second.data)
        # Another woman, same day: fine.
        self.comme(self.autre_femme)
        autre = self.client.post("/api/women-food-logs/", donnees, format="json")
        self.assertEqual(autre.status_code, 201, autre.data)
