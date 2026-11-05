from datetime import date, timedelta

from django.utils import timezone

from nutrition.models import Enfant
from referencement.models import Referencement, RendezVous
from referentiel.models import CSB
from synchro.outils_tests import BaseApiTest

REFERENCEMENTS = "/api/referrals/"


def url_status(ligne):
    return f"{REFERENCEMENTS}{ligne.pk}/status/"


class SortieTest(BaseApiTest):
    """Spec §7: only an authorised professional records a discharge."""

    def setUp(self):
        super().setUp()
        self.petit = self.enfant()
        self.ligne = self.referencement(enfant=self.petit, status="pris_en_charge")

    def sortir(self, issue="gueri", version=1, **extra):
        return self.client.post(
            url_status(self.ligne),
            {"status": "sortie", "version": version, "issue_sortie": issue, **extra},
            format="json",
        )

    def test_agent_du_centre_enregistre_la_sortie(self):
        self.comme(self.agent)
        reponse = self.sortir("decede")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.petit.refresh_from_db()
        self.assertEqual(self.petit.statut_prise_en_charge, "decede")

    def test_admin_ne_peut_pas_enregistrer_une_sortie(self):
        self.comme(self.admin)
        reponse = self.sortir()
        self.assertEqual(reponse.status_code, 403)
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.status, "pris_en_charge")

    def test_issue_obligatoire(self):
        self.comme(self.agent)
        reponse = self.sortir("")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("issue_sortie", reponse.data)

    def test_issue_seulement_pour_une_sortie(self):
        self.comme(self.agent)
        reponse = self.client.post(
            url_status(self.ligne),
            {"status": "en_suivi", "version": 1, "issue_sortie": "gueri"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)

    def test_sortie_possible_des_l_arrivee(self):
        Referencement.objects.filter(pk=self.ligne.pk).update(
            status="recu",
            date_reception=timezone.now(),
        )
        self.comme(self.agent)
        self.assertEqual(self.sortir("transfere").status_code, 200)

    def test_pas_de_sortie_avant_l_arrivee(self):
        Referencement.objects.filter(pk=self.ligne.pk).update(status="envoye")
        self.comme(self.agent)
        reponse = self.sortir()
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("recu", reponse.data["status"][0])

    def test_rien_apres_la_sortie(self):
        self.comme(self.agent)
        self.sortir()
        reponse = self.client.post(
            url_status(self.ligne),
            {"status": "en_suivi", "version": 2},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)


class StatutEnfantTest(BaseApiTest):
    """The child's care status follows the referral."""

    def test_statut_enfant_suit_le_referencement(self):
        petit = self.enfant()
        ligne = self.referencement(enfant=petit)
        self.comme(self.agent)
        attendus = [
            ("recu", "aucun"),
            ("pris_en_charge", "pris_en_charge"),
            ("en_suivi", "suivi"),
        ]
        for version, (status, statut_enfant) in enumerate(attendus, 1):
            with self.subTest(status=status):
                reponse = self.client.post(
                    url_status(ligne),
                    {"status": status, "version": version},
                    format="json",
                )
                self.assertEqual(reponse.status_code, 200, reponse.data)
                petit.refresh_from_db()
                self.assertEqual(petit.statut_prise_en_charge, statut_enfant)
        self.assertEqual(petit.version, 3)


class FileEntranteTest(BaseApiTest):
    """Spec §10: queue sorted by urgency (red, orange, yellow) then age."""

    def setUp(self):
        super().setUp()
        maintenant = timezone.now()
        petit = self.enfant()
        self.jaune_ancien = self.referencement(
            code="R-1",
            enfant=petit,
            priorite="normale",
            date_referencement=maintenant - timedelta(days=3),
        )
        self.orange_recent = self.referencement(
            code="R-2",
            enfant=petit,
            priorite="haute",
            date_referencement=maintenant - timedelta(hours=1),
        )
        self.orange_ancien = self.referencement(
            code="R-3",
            enfant=petit,
            priorite="haute",
            date_referencement=maintenant - timedelta(hours=5),
        )
        self.rouge = self.referencement(
            code="R-4",
            enfant=petit,
            priorite="urgente",
            date_referencement=maintenant,
        )
        self.pris = self.referencement(
            code="R-5",
            enfant=petit,
            priorite="urgente",
            status="pris_en_charge",
        )
        self.referencement(code="R-6", enfant=petit, csb=self.autre_csb)

    def test_ordre_de_la_file(self):
        self.comme(self.agent)
        reponse = self.client.get(f"{REFERENCEMENTS}incoming/")
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(
            [ligne["code_unique"] for ligne in reponse.data["results"]],
            ["R-4", "R-3", "R-2", "R-1"],
        )
        self.assertEqual(
            [ligne["urgence"] for ligne in reponse.data["results"]],
            ["rouge", "orange", "orange", "jaune"],
        )

    def test_reservee_aux_centres(self):
        for user in (self.asc, self.femme):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(
                    self.client.get(f"{REFERENCEMENTS}incoming/").status_code,
                    403,
                )

    def test_recherche_par_code(self):
        self.comme(self.agent)
        reponse = self.client.get(f"{REFERENCEMENTS}?code=r-3")
        self.assertEqual(self.ids(reponse), {str(self.orange_ancien.pk)})

    def test_non_arrives_apres_le_delai_de_la_configuration(self):
        self.publier_config()
        self.comme(self.agent)
        reponse = self.client.get(f"{REFERENCEMENTS}?en_retard=true")
        self.assertEqual(self.ids(reponse), {str(self.jaune_ancien.pk)})
        detail = self.client.get(f"{REFERENCEMENTS}{self.jaune_ancien.pk}/")
        self.assertTrue(detail.data["en_retard"])

    def test_delai_change_avec_la_configuration(self):
        contenu = self.config_exemple()
        contenu["malnutrition"]["suivi"]["delai_alerte_non_arrivee_heures"] = 2
        self.publier_config(contenu)
        self.comme(self.agent)
        reponse = self.client.get(f"{REFERENCEMENTS}?en_retard=true")
        self.assertEqual(
            self.ids(reponse),
            {str(self.jaune_ancien.pk), str(self.orange_ancien.pk)},
        )

    def test_date_de_referencement_du_telephone(self):
        self.comme(self.asc)
        reponse = self.client.post(
            REFERENCEMENTS,
            {
                "origine": "enfant",
                "enfant_id": str(self.enfant().pk),
                "csb_id": self.csb.pk,
                "priorite": "haute",
                "motif": "PB 112 mm",
                "code_unique": "TRK-7F3K-92",
                "date_referencement": "2026-11-01T08:00:00Z",
            },
            format="json",
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["date_referencement"], "2026-11-01T08:00:00Z")
        self.assertEqual(reponse.data["status"], "envoye")


class RendezVousTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.petit = self.enfant()
        self.ligne = self.referencement(enfant=self.petit)

    def creer(self, **extra):
        return self.client.post(
            "/api/appointments/",
            {
                "enfant_id": str(self.petit.pk),
                "date_prevue": "2026-11-20",
                "motif": "Contrôle PB",
                **extra,
            },
            format="json",
        )

    def test_agent_programme_un_controle_dans_son_centre(self):
        self.comme(self.agent)
        reponse = self.creer(csb_id=self.autre_csb.pk, referencement_id=str(self.ligne.pk))
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["csb_id"], self.csb.pk)
        self.assertEqual(reponse.data["statut"], "prevu")

    def test_asc_programme_un_depistage(self):
        self.comme(self.asc)
        reponse = self.creer(type_rendez_vous="depistage")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertIsNone(reponse.data["csb_id"])

    def test_enfant_hors_de_portee_refuse(self):
        self.comme(self.autre_agent)
        self.assertEqual(self.creer().status_code, 400)

    def test_referencement_d_un_autre_enfant_refuse(self):
        autre = self.referencement(code="R-X", enfant=self.enfant(nom="Autre"))
        self.comme(self.asc)
        reponse = self.creer(referencement_id=str(autre.pk))
        self.assertEqual(reponse.status_code, 400)

    def test_rendez_vous_manques(self):
        hier = timezone.localdate() - timedelta(days=1)
        manque = RendezVous.objects.create(enfant=self.petit, date_prevue=hier)
        RendezVous.objects.create(enfant=self.petit, date_prevue=hier, statut="honore")
        RendezVous.objects.create(
            enfant=self.petit,
            date_prevue=timezone.localdate() + timedelta(days=2),
        )
        self.comme(self.asc)
        reponse = self.client.get("/api/appointments/?manque=true")
        self.assertEqual(self.ids(reponse), {str(manque.pk)})
        detail = self.client.get(f"/api/appointments/{manque.pk}/")
        self.assertTrue(detail.data["manque"])

    def test_beneficiaire_lit_sans_ecrire(self):
        maman = self.enfant(nom="Avec maman", mere=self.femme)
        RendezVous.objects.create(enfant=maman, date_prevue=date(2026, 12, 1))
        self.comme(self.femme)
        self.assertEqual(self.client.get("/api/appointments/").data["count"], 1)
        reponse = self.client.post(
            "/api/appointments/",
            {"enfant_id": str(maman.pk), "date_prevue": "2026-12-02"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)


class RelancesTest(BaseApiTest):
    """Spec §10: referrals not arrived, missed visits, children to see again."""

    def test_liste_de_l_asc(self):
        self.publier_config()
        petit = self.enfant()
        en_retard = self.referencement(
            code="R-1",
            enfant=petit,
            date_referencement=timezone.now() - timedelta(hours=49),
        )
        self.referencement(code="R-2", enfant=petit)
        hier = timezone.localdate() - timedelta(days=1)
        manque = RendezVous.objects.create(enfant=petit, date_prevue=hier)
        self.mesure(
            petit,
            date_mesure=hier - timedelta(days=30),
            classification="mam",
            date_prochain_controle=hier,
        )
        a_jour = self.enfant(nom="A jour")
        self.mesure(a_jour, date_prochain_controle=timezone.localdate() + timedelta(days=10))
        self.comme(self.asc)
        reponse = self.client.get("/api/follow-ups/")
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["delai_non_arrivee_heures"], 48)
        self.assertEqual(
            [ligne["id"] for ligne in reponse.data["referencements_non_arrives"]],
            [str(en_retard.pk)],
        )
        self.assertEqual(
            [ligne["id"] for ligne in reponse.data["rendez_vous_manques"]],
            [str(manque.pk)],
        )
        self.assertEqual(
            [ligne["id"] for ligne in reponse.data["enfants_a_revoir"]],
            [str(petit.pk)],
        )
        self.assertEqual(reponse.data["enfants_a_revoir"][0]["derniere_classification"], "mam")

    def test_autre_asc_ne_voit_rien(self):
        self.publier_config()
        self.referencement(
            code="R-1",
            enfant=self.enfant(),
            date_referencement=timezone.now() - timedelta(days=3),
        )
        self.comme(self.asc_meme_region)
        reponse = self.client.get("/api/follow-ups/")
        self.assertEqual(reponse.data["referencements_non_arrives"], [])

    def test_sans_configuration_pas_de_delai(self):
        self.comme(self.asc)
        reponse = self.client.get("/api/follow-ups/")
        self.assertIsNone(reponse.data["delai_non_arrivee_heures"])

    def test_beneficiaire_et_superviseur_refuses(self):
        from comptes.models import CodeProfile

        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        for user in (self.femme, superviseur):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(self.client.get("/api/follow-ups/").status_code, 403)


class ConsultationTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.petit = self.enfant()
        self.ligne = self.referencement(enfant=self.petit)

    def creer(self, **extra):
        return self.client.post(
            "/api/consultations/",
            {
                "enfant_id": str(self.petit.pk),
                "referencement_id": str(self.ligne.pk),
                "date": "2026-11-04",
                "diagnostic": "MAS sans complication",
                "decision": "prise_en_charge",
                **extra,
            },
            format="json",
        )

    def test_agent_enregistre_la_prise_en_charge(self):
        self.comme(self.agent)
        reponse = self.creer(csb_id=self.autre_csb.pk)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["csb_id"], self.csb.pk)
        self.assertEqual(reponse.data["agent_medical_id"], self.agent.pk)

    def test_asc_lit_sans_ecrire(self):
        self.comme(self.asc)
        self.assertEqual(self.creer().status_code, 403)
        self.comme(self.agent)
        self.creer()
        self.comme(self.asc)
        self.assertEqual(self.client.get("/api/consultations/").data["count"], 1)

    def test_agent_d_un_autre_centre_refuse(self):
        self.comme(self.autre_agent)
        self.assertEqual(self.creer().status_code, 400)


class JournalAlimentaireTest(BaseApiTest):
    """Scenario 4: vary + anana + lait maternel = 3 groups out of 8."""

    def setUp(self):
        super().setUp()
        self.petit = self.enfant(mere=self.femme, date_naissance=date(2026, 2, 4))

    def creer(self, **extra):
        return self.client.post(
            "/api/food-logs/",
            {
                "enfant_id": str(self.petit.pk),
                "date_jour": "2026-11-04",
                "type_allaitement": "mixte",
                "g1_lait_maternel": True,
                "g2_cereales_tubercules": True,
                "g7_fruits_legumes_vit_a": True,
                **extra,
            },
            format="json",
        )

    def test_scenario_4_diversite_insuffisante(self):
        self.publier_config()
        self.comme(self.femme)
        reponse = self.creer(score_diversite=8)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["score_diversite"], 3)
        self.assertFalse(reponse.data["diversite_minimale_atteinte"])

    def test_un_journal_par_jour(self):
        self.comme(self.femme)
        self.creer()
        reponse = self.creer()
        self.assertEqual(reponse.status_code, 400)

    def test_agent_ne_l_ecrit_pas(self):
        self.comme(self.agent)
        self.assertEqual(self.creer().status_code, 403)


class TypeCentreTest(BaseApiTest):
    def test_filtre_par_type(self):
        crenas = CSB.objects.create(
            name="CRENAS A",
            region=self.region,
            tel="3",
            type_centre="crenas",
        )
        self.comme(self.asc)
        reponse = self.client.get("/api/facilities/?type_centre=crenas")
        self.assertEqual([ligne["id"] for ligne in reponse.data["results"]], [crenas.pk])
        self.assertEqual(reponse.data["results"][0]["type_centre"], "crenas")
        self.assertEqual(Enfant.objects.count(), 0)


class ContactAgentTest(BaseApiTest):
    """Issue 4: who to call about a referral, for staff only."""

    def setUp(self):
        super().setUp()
        self.asc.phone = "034 00 000 01"
        self.asc.save()
        self.ligne = self.referencement(enfant=self.enfant(mere=self.femme))

    def contact(self, user):
        self.comme(user)
        return self.client.get(f"{REFERENCEMENTS}{self.ligne.pk}/").data["asc"]

    def test_le_centre_voit_le_nom_et_le_telephone(self):
        self.assertEqual(
            self.contact(self.agent),
            {"nom": "Asc", "prenom": "Test", "phone": "034 00 000 01"},
        )

    def test_asc_et_admin_aussi(self):
        for user in (self.asc, self.admin):
            with self.subTest(user=user.identifiant):
                self.assertEqual(self.contact(user)["phone"], "034 00 000 01")

    def test_pas_pour_la_beneficiaire(self):
        self.assertIsNone(self.contact(self.femme))

    def test_dans_la_file_et_a_la_synchronisation(self):
        self.comme(self.agent)
        file = self.client.get(f"{REFERENCEMENTS}incoming/").data["results"]
        self.assertEqual(file[0]["asc"]["nom"], "Asc")
        self.comme(self.femme)
        lignes = self.client.get("/api/sync/pull/", {"tables": "referencement"}).data
        self.assertIsNone(lignes["tables"]["referencement"]["lignes"][0]["asc"])


class DateSuiviTest(BaseApiTest):
    """Issue 5: the date of the « En suivi » step."""

    def test_date_remplie_au_passage_en_suivi_seulement(self):
        ligne = self.referencement(enfant=self.enfant())
        self.comme(self.agent)
        for version, status in enumerate(("recu", "pris_en_charge"), 1):
            self.client.post(url_status(ligne), {"status": status, "version": version}, format="json")
        sortie_directe = self.client.post(
            url_status(ligne),
            {"status": "sortie", "version": 3, "issue_sortie": "transfere"},
            format="json",
        )
        self.assertIsNone(sortie_directe.data["date_suivi"])

        autre = self.referencement(code="R-2", enfant=self.enfant(nom="Autre"))
        for version, status in enumerate(("recu", "pris_en_charge", "en_suivi"), 1):
            reponse = self.client.post(url_status(autre), {"status": status, "version": version}, format="json")
        self.assertIsNotNone(reponse.data["date_suivi"])

    def test_migration_retrouve_la_date_dans_le_journal(self):
        from importlib import import_module

        from django.apps import apps

        from synchro.models import JournalAudit

        ligne = self.referencement(enfant=self.enfant(), status="en_suivi")
        passage = JournalAudit.objects.create(
            action="status_change",
            table_nom="referencement",
            ligne_id=ligne.pk,
            details={"ancien": "pris_en_charge", "nouveau": "en_suivi"},
        )
        import_module("referencement.migrations.0003_date_suivi").remplir_date_suivi(apps, None)
        ligne.refresh_from_db()
        self.assertEqual(ligne.date_suivi, passage.date_creation)
