import re
from unittest import mock

from django.utils import timezone

from referencement.models import Referencement
from referencement.services import generer_code
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

REFERENCEMENTS = "/api/referrals/"


def url(referencement):
    return f"{REFERENCEMENTS}{referencement.pk}/"


def url_status(referencement):
    return f"{url(referencement)}status/"


class CreationTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.le_mien = self.enfant()
        self.comme(self.asc)

    def donnees(self, **extra):
        return {
            "origine": "enfant",
            "enfant_id": str(self.le_mien.pk),
            "csb_id": self.csb.pk,
            "priorite": "haute",
            "motif": "PB bas",
            **extra,
        }

    def creer(self, **extra):
        return self.client.post(REFERENCEMENTS, self.donnees(**extra), format="json")

    def test_code_du_telephone_garde(self):
        reponse = self.creer(code_unique="R-TEL-1")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["code_unique"], "R-TEL-1")
        self.assertEqual(reponse.data["asc_id"], self.asc.pk)
        self.assertEqual(reponse.data["status"], "envoye")

    def test_code_en_double_refuse(self):
        self.creer(code_unique="R-TEL-1")
        reponse = self.creer(code_unique="R-TEL-1")
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(
            reponse.data["code_unique"],
            ["Ce code de référencement existe déjà."],
        )

    def test_code_d_une_ligne_supprimee_reste_pris(self):
        self.referencement(code="R-TEL-1", enfant=self.le_mien).soft_delete()
        reponse = self.creer(code_unique="R-TEL-1")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("code_unique", reponse.data)

    def test_code_genere_par_le_serveur(self):
        reponse = self.creer()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        prefixe = str(self.asc.pk)[:4]
        date_du_jour = f"{timezone.localdate():%m%d}"
        self.assertEqual(
            reponse.data["code_unique"],
            f"R-{prefixe}-{date_du_jour}-01",
        )
        self.assertTrue(
            re.fullmatch(r"R-[0-9a-f]{4}-[0-9]{4}-01", reponse.data["code_unique"])
        )

    def test_numero_suivant_y_compris_apres_suppression(self):
        premier = self.creer().data["code_unique"]
        Referencement.objects.get(code_unique=premier).soft_delete()
        deuxieme = self.creer().data["code_unique"]
        self.assertEqual(deuxieme, f"{premier[:-2]}02")

    def test_collision_de_code_prend_le_suivant(self):
        premier = generer_code(self.asc)
        self.referencement(code=premier, enfant=self.le_mien)
        reel = generer_code
        appels = []

        def collision_puis_reel(asc):
            appels.append(asc)
            return premier if len(appels) == 1 else reel(asc)

        with mock.patch(
            "referencement.services.generer_code",
            collision_puis_reel,
        ):
            reponse = self.creer()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(len(appels), 2)
        self.assertNotEqual(reponse.data["code_unique"], premier)

    def test_referencement_enfant_passe_l_enfant_a_refere(self):
        self.assertEqual(self.creer().status_code, 201)
        self.le_mien.refresh_from_db()
        self.assertEqual(self.le_mien.statut_prise_en_charge, "refere")
        self.assertEqual(self.le_mien.version, 2)

    def test_lien_obligatoire_selon_l_origine(self):
        reponse = self.creer(enfant_id=None)
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(
            reponse.data["non_field_errors"],
            [
                "Un référencement enfant doit indiquer l'enfant, "
                "et un référencement grossesse doit indiquer la grossesse."
            ],
        )

    def test_lien_de_l_autre_origine_refuse(self):
        grossesse = self.grossesse()
        reponse = self.creer(grossesse_id=str(grossesse.pk))
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("grossesse_id", reponse.data)

    def test_mesure_d_un_autre_enfant_refusee(self):
        mesure = self.mesure(self.enfant(nom="Autre"))
        reponse = self.creer(mesure_id=str(mesure.pk))
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("mesure_id", reponse.data)

    def test_asc_ne_peut_pas_referer_l_enfant_d_un_autre(self):
        sien = self.enfant(asc=self.autre_asc)
        reponse = self.creer(enfant_id=str(sien.pk))
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("enfant_id", reponse.data)

    def test_asc_ne_peut_pas_referer_une_grossesse_hors_region(self):
        grossesse = self.grossesse(self.autre_femme)
        reponse = self.creer(
            origine="grossesse",
            enfant_id=None,
            grossesse_id=str(grossesse.pk),
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("grossesse_id", reponse.data)

    def test_beneficiaire_et_agent_ne_creent_pas(self):
        for user in (self.femme, self.agent):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(self.creer().status_code, 403)

    def test_asc_ne_modifie_ni_ne_supprime(self):
        referencement = self.referencement(enfant=self.le_mien)
        self.assertEqual(
            self.client.patch(
                url(referencement),
                {"motif": "X", "version": 1},
                format="json",
            ).status_code,
            403,
        )
        self.assertEqual(self.client.delete(url(referencement)).status_code, 403)


class AccesTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.enfant_femme = self.enfant(mere=self.femme)
        self.enfant_autre = self.enfant(asc=self.autre_asc, mere=self.autre_femme)
        self.vers_mon_csb = self.referencement(
            code="R-1",
            enfant=self.enfant_femme,
            csb=self.csb,
        )
        self.vers_autre_csb = self.referencement(
            code="R-2",
            enfant=self.enfant_autre,
            csb=self.autre_csb,
            asc=self.autre_asc,
        )

    def test_agent_ne_voit_que_son_csb(self):
        self.comme(self.agent)
        self.assertEqual(
            self.ids(self.client.get(REFERENCEMENTS)),
            {str(self.vers_mon_csb.pk)},
        )
        self.assertEqual(self.client.get(url(self.vers_autre_csb)).status_code, 404)
        reponse = self.client.get(f"{REFERENCEMENTS}?csb={self.autre_csb.pk}")
        self.assertEqual(reponse.data["results"], [])

    def test_beneficiaire_voit_les_siens_et_ceux_de_ses_enfants(self):
        grossesse = self.grossesse()
        sa_grossesse = self.referencement(code="R-3", grossesse=grossesse)
        self.comme(self.femme)
        self.assertEqual(
            self.ids(self.client.get(REFERENCEMENTS)),
            {str(self.vers_mon_csb.pk), str(sa_grossesse.pk)},
        )
        self.assertEqual(self.client.get(url(self.vers_autre_csb)).status_code, 404)

    def test_asc_voit_les_siens_et_les_grossesses_des_femmes_suivies(self):
        grossesse = self.grossesse()
        self.suivre(self.asc)
        par_collegue = self.referencement(
            code="R-3",
            grossesse=grossesse,
            asc=self.asc_meme_region,
        )
        self.comme(self.asc)
        self.assertEqual(
            self.ids(self.client.get(REFERENCEMENTS)),
            {str(self.vers_mon_csb.pk), str(par_collegue.pk)},
        )
        self.assertEqual(self.client.get(url(self.vers_autre_csb)).status_code, 404)

    def test_filtres(self):
        urgent = self.referencement(
            code="R-3",
            enfant=self.enfant_femme,
            priorite="urgente",
            status="pris_en_charge",
        )
        grossesse = self.referencement(code="R-4", grossesse=self.grossesse())
        self.comme(self.admin)
        cas = [
            ("priorite=urgente", {urgent}),
            ("status=pris_en_charge", {urgent}),
            ("origine=grossesse", {grossesse}),
            (f"csb={self.autre_csb.pk}", {self.vers_autre_csb}),
        ]
        for filtre, attendu in cas:
            with self.subTest(filtre=filtre):
                self.assertEqual(
                    self.ids(self.client.get(f"{REFERENCEMENTS}?{filtre}")),
                    {str(ligne.pk) for ligne in attendu},
                )

    def test_nom_de_la_femme_visible_sur_un_referencement_grossesse(self):
        ligne = self.referencement(code="R-3", grossesse=self.grossesse())
        self.comme(self.agent)
        reponse = self.client.get(url(ligne))
        self.assertEqual(reponse.data["femme"], {"nom": "Femme", "prenom": "Test"})
        self.assertIsNone(self.client.get(url(self.vers_mon_csb)).data["femme"])

    def test_suppression_par_admin_cache_la_ligne(self):
        self.comme(self.admin)
        self.assertEqual(self.client.delete(url(self.vers_mon_csb)).status_code, 204)
        self.assertEqual(self.client.get(url(self.vers_mon_csb)).status_code, 404)


class StatusTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.ligne = self.referencement(enfant=self.enfant())

    def changer(self, status, version=1, ligne=None):
        return self.client.post(
            url_status(ligne or self.ligne),
            {"status": status, "version": version},
            format="json",
            headers={"X-Device-Id": "csb-1"},
        )

    def test_agent_avance_le_statut_etape_par_etape(self):
        self.comme(self.agent)
        etapes = ("recu", "pris_en_charge", "en_suivi")
        for version, status in enumerate(etapes, 1):
            reponse = self.changer(status, version)
            self.assertEqual(reponse.status_code, 200, reponse.data)
            self.assertEqual(reponse.data["status"], status)
            self.assertEqual(reponse.data["version"], version + 1)
        reponse = self.client.post(
            url_status(self.ligne),
            {"status": "sortie", "version": 4, "issue_sortie": "gueri"},
            format="json",
            headers={"X-Device-Id": "csb-1"},
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["issue_sortie"], "gueri")
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.device_id, "csb-1")
        self.assertIsNotNone(self.ligne.date_reception)
        self.assertIsNotNone(self.ligne.date_prise_en_charge)
        self.assertIsNotNone(self.ligne.date_sortie)

    def test_retour_en_arriere_refuse(self):
        Referencement.objects.filter(pk=self.ligne.pk).update(status="pris_en_charge")
        self.comme(self.agent)
        for status in ("recu", "envoye", "pris_en_charge"):
            with self.subTest(status=status):
                reponse = self.changer(status)
                self.assertEqual(reponse.status_code, 400)
                self.assertEqual(
                    reponse.data["status"],
                    ["Le statut ne peut pas revenir en arrière."],
                )
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.status, "pris_en_charge")

    def test_sauter_une_etape_refuse(self):
        self.comme(self.agent)
        reponse = self.changer("pris_en_charge")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("recu", reponse.data["status"][0])

    def test_admin_suit_le_meme_ordre(self):
        Referencement.objects.filter(pk=self.ligne.pk).update(status="recu")
        self.comme(self.admin)
        self.assertEqual(self.changer("en_suivi").status_code, 400)
        self.assertEqual(self.changer("pris_en_charge").status_code, 200)

    def test_version_differente_renvoie_409(self):
        Referencement.objects.filter(pk=self.ligne.pk).update(version=4)
        self.comme(self.agent)
        reponse = self.changer("recu", version=1)
        self.assertEqual(reponse.status_code, 409)
        self.assertEqual(reponse.data["current"]["version"], 4)
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.status, "envoye")

    def test_agent_d_un_autre_csb_refuse(self):
        self.comme(self.autre_agent)
        self.assertEqual(self.changer("recu").status_code, 404)

    def test_asc_et_beneficiaire_refuses(self):
        for user in (self.asc, self.femme):
            with self.subTest(user=user.identifiant):
                self.comme(user)
                self.assertEqual(self.changer("recu").status_code, 403)

    def test_agent_ne_peut_changer_que_le_statut(self):
        self.comme(self.agent)
        reponse = self.client.patch(
            url(self.ligne),
            {"motif": "Autre", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)

    def test_le_statut_ne_passe_pas_par_la_modification(self):
        self.comme(self.admin)
        reponse = self.client.patch(
            url(self.ligne),
            {"status": "sortie", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["status"], "envoye")

    def test_changement_journalise(self):
        self.comme(self.agent)
        self.changer("recu")
        ligne = JournalAudit.objects.get(action="status_change")
        self.assertEqual(ligne.user, self.agent)
        self.assertEqual(ligne.table_nom, "referencement")
        self.assertEqual(ligne.ligne_id, self.ligne.pk)
        self.assertEqual(ligne.details["ancien"], "envoye")
        self.assertEqual(ligne.details["nouveau"], "recu")
