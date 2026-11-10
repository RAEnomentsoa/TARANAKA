import uuid
from datetime import date, timedelta
from decimal import Decimal

from comptes.models import Profile, User
from nutrition.models import Enfant, Mesure
from nutrition.services import calculer_champs_mesure
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

ENFANTS = "/api/children/"
MESURES = "/api/measurements/"


def enfant_url(enfant):
    return f"{ENFANTS}{enfant.pk}/"


def mesure_url(mesure):
    return f"{MESURES}{mesure.pk}/"


class AccesEnfantsTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.le_mien = self.enfant(mere=self.femme, nom="Hery")
        self.le_sien = self.enfant(asc=self.autre_asc, region=self.autre_region, nom="Koto")

    def test_asc_ne_voit_que_ses_enfants(self):
        self.comme(self.asc)
        self.assertEqual(self.ids(self.client.get(ENFANTS)), {str(self.le_mien.pk)})
        self.assertEqual(self.client.get(enfant_url(self.le_sien)).status_code, 404)

    def test_les_filtres_ne_montrent_jamais_les_enfants_des_autres(self):
        self.comme(self.asc)
        for filtre in (
            f"asc={self.autre_asc.pk}",
            f"region={self.autre_region.pk}",
            "search=Koto",
        ):
            with self.subTest(filtre=filtre):
                reponse = self.client.get(f"{ENFANTS}?{filtre}")
                self.assertEqual(reponse.status_code, 200)
                self.assertEqual(reponse.data["results"], [])

    def test_meme_region_ne_suffit_pas_pour_un_enfant(self):
        self.comme(self.asc_meme_region)
        self.assertEqual(self.client.get(enfant_url(self.le_mien)).status_code, 404)

    def test_beneficiaire_ecrit_ses_propres_enfants(self):
        """M1 (D16): the mother registers and corrects her children herself."""
        self.comme(self.femme)
        self.assertEqual(self.ids(self.client.get(ENFANTS)), {str(self.le_mien.pk)})
        self.assertEqual(self.client.get(enfant_url(self.le_sien)).status_code, 404)
        reponse = self.client.patch(
            enfant_url(self.le_mien),
            {"nom": "X", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        bebe = {
            "nom": "Bebe",
            "sexe": "F",
            "date_naissance": "2026-06-01",
            "poids_naissance_kg": "3.10",
        }
        # Never another woman's child.
        reponse = self.client.post(
            ENFANTS, {**bebe, "mere_id": str(self.autre_femme.pk)}, format="json"
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("mere_id", reponse.data)
        reponse = self.client.post(ENFANTS, bebe, format="json")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["mere_id"], self.femme.pk)
        self.assertIsNone(reponse.data["asc_id"])
        self.assertEqual(reponse.data["region_id"], self.region.pk)
        self.assertEqual(reponse.data["poids_naissance_kg"], "3.10")
        self.assertEqual(self.client.patch(
            enfant_url(self.le_sien), {"nom": "Y", "version": 1}, format="json"
        ).status_code, 404)

    def test_agent_ne_voit_que_les_enfants_references_a_son_csb(self):
        self.referencement(enfant=self.le_mien, csb=self.csb)
        self.referencement(code="R-2", enfant=self.le_sien, csb=self.autre_csb)
        self.comme(self.agent)
        self.assertEqual(self.ids(self.client.get(ENFANTS)), {str(self.le_mien.pk)})
        self.assertEqual(self.client.get(enfant_url(self.le_sien)).status_code, 404)
        reponse = self.client.patch(
            enfant_url(self.le_mien),
            {"nom": "X", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)

    def test_agent_sans_csb_ne_voit_rien(self):
        self.enfant()
        sans_csb = self.compte("agent3", "agent_csb")
        self.comme(sans_csb)
        self.assertEqual(self.client.get(ENFANTS).data["results"], [])

    def test_admin_voit_tout(self):
        self.comme(self.admin)
        self.assertEqual(
            self.ids(self.client.get(ENFANTS)),
            {str(self.le_mien.pk), str(self.le_sien.pk)},
        )

    def test_profil_inconnu_refuse(self):
        profil = Profile.objects.create(code="invite", libelle="Invité")
        self.comme(
            User.objects.create_user("x", "1234", nom="X", prenom="X", profile=profil)
        )
        self.assertEqual(self.client.get(ENFANTS).status_code, 403)

    def test_sans_token_refuse(self):
        self.assertEqual(self.client.get(ENFANTS).status_code, 401)


class CreationEnfantTest(BaseApiTest):
    def donnees(self, **extra):
        return {
            "nom": "Hery",
            "region_id": self.region.pk,
            "date_naissance": "2025-01-01",
            "sexe": "M",
            **extra,
        }

    def test_id_du_telephone_garde_et_asc_impose(self):
        self.comme(self.asc)
        identifiant = str(uuid.uuid4())
        reponse = self.client.post(
            ENFANTS,
            self.donnees(id=identifiant),
            format="json",
            headers={"X-Device-Id": "tel-1"},
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        enfant = Enfant.objects.get(pk=identifiant)
        self.assertEqual(enfant.asc, self.asc)
        self.assertEqual(enfant.device_id, "tel-1")
        self.assertEqual(enfant.version, 1)
        self.assertTrue(
            JournalAudit.objects.filter(
                action="create",
                table_nom="enfant",
                ligne_id=identifiant,
                user=self.asc,
            ).exists()
        )

    def test_id_cree_par_le_serveur_si_absent(self):
        self.comme(self.asc)
        reponse = self.client.post(ENFANTS, self.donnees(), format="json")
        self.assertEqual(reponse.status_code, 201)
        self.assertTrue(Enfant.objects.filter(pk=reponse.data["id"]).exists())

    def test_champs_du_serveur_ignores_a_la_creation(self):
        self.comme(self.asc)
        reponse = self.client.post(
            ENFANTS,
            self.donnees(version=99, device_id="faux", deleted_at="2020-01-01T00:00:00Z"),
            format="json",
        )
        self.assertEqual(reponse.data["version"], 1)
        self.assertEqual(reponse.data["device_id"], "")
        self.assertIsNone(reponse.data["deleted_at"])

    def test_renvoi_du_meme_id_ne_cree_rien(self):
        self.comme(self.asc)
        identifiant = str(uuid.uuid4())
        self.client.post(ENFANTS, self.donnees(id=identifiant), format="json")
        reponse = self.client.post(
            ENFANTS,
            self.donnees(id=identifiant, nom="Autre"),
            format="json",
        )
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.data["nom"], "Hery")
        self.assertEqual(Enfant.objects.count(), 1)

    def test_id_d_un_autre_utilisateur_refuse_sans_ecraser(self):
        sien = self.enfant(asc=self.autre_asc, nom="Koto")
        self.comme(self.asc)
        reponse = self.client.post(
            ENFANTS,
            self.donnees(id=str(sien.pk)),
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("id", reponse.data)
        sien.refresh_from_db()
        self.assertEqual(sien.nom, "Koto")
        self.assertEqual(sien.asc, self.autre_asc)

    def test_asc_ne_peut_pas_attribuer_l_enfant_a_un_autre_asc(self):
        self.comme(self.asc)
        reponse = self.client.post(
            ENFANTS,
            self.donnees(asc_id=str(self.autre_asc.pk)),
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("asc_id", reponse.data)

    def test_mere_hors_de_la_region_refusee(self):
        self.comme(self.asc)
        reponse = self.client.post(
            ENFANTS,
            self.donnees(mere_id=str(self.autre_femme.pk)),
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("mere_id", reponse.data)

    def test_grossesse_d_une_autre_mere_refusee(self):
        autre = self.compte("femme4", "beneficiaire", region=self.region)
        grossesse = self.grossesse(autre)
        self.comme(self.asc)
        reponse = self.client.post(
            ENFANTS,
            self.donnees(mere_id=str(self.femme.pk), grossesse_id=str(grossesse.pk)),
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("grossesse_id", reponse.data)

    def test_admin_doit_indiquer_l_asc(self):
        self.comme(self.admin)
        reponse = self.client.post(ENFANTS, self.donnees(), format="json")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("asc_id", reponse.data)


class VersionTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.ligne = self.enfant(nom="Hery")
        self.comme(self.asc)

    def test_mise_a_jour_augmente_la_version(self):
        reponse = self.client.patch(
            enfant_url(self.ligne),
            {"nom": "Rivo", "version": 1},
            format="json",
            headers={"X-Device-Id": "tel-2"},
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["version"], 2)
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.nom, "Rivo")
        self.assertEqual(self.ligne.device_id, "tel-2")
        self.assertTrue(
            JournalAudit.objects.filter(action="update", ligne_id=self.ligne.pk).exists()
        )

    def test_version_differente_renvoie_409_sans_rien_enregistrer(self):
        Enfant.objects.filter(pk=self.ligne.pk).update(version=5, nom="Serveur")
        reponse = self.client.patch(
            enfant_url(self.ligne),
            {"nom": "Téléphone", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 409)
        self.assertEqual(reponse.data["code"], "conflit_version")
        self.assertEqual(reponse.data["current"]["version"], 5)
        self.assertEqual(reponse.data["current"]["nom"], "Serveur")
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.nom, "Serveur")
        self.assertEqual(self.ligne.version, 5)
        self.assertFalse(
            JournalAudit.objects.filter(action="update", ligne_id=self.ligne.pk).exists()
        )

    def test_version_obligatoire(self):
        reponse = self.client.patch(
            enfant_url(self.ligne),
            {"nom": "Rivo"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(reponse.data["version"], ["Ce champ est obligatoire."])

    def test_409_aussi_pour_une_mesure(self):
        mesure = self.mesure(self.ligne, version=3)
        reponse = self.client.patch(
            mesure_url(mesure),
            {"poids_kg": "9.00", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 409)
        self.assertEqual(reponse.data["current"]["version"], 3)
        self.assertEqual(Decimal(reponse.data["current"]["poids_kg"]), Decimal("8.50"))


class SuppressionTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.ligne = self.enfant()
        self.comme(self.asc)

    def test_ligne_supprimee_invisible_partout(self):
        reponse = self.client.delete(
            enfant_url(self.ligne),
            headers={"X-Device-Id": "tel-3"},
        )
        self.assertEqual(reponse.status_code, 204)
        self.assertEqual(self.client.get(ENFANTS).data["results"], [])
        self.assertEqual(self.client.get(enfant_url(self.ligne)).status_code, 404)

        ligne = Enfant.all_objects.get(pk=self.ligne.pk)
        self.assertIsNotNone(ligne.deleted_at)
        self.assertEqual(ligne.version, 2)
        self.assertEqual(ligne.device_id, "tel-3")
        self.assertTrue(
            JournalAudit.objects.filter(action="delete", ligne_id=ligne.pk).exists()
        )

    def test_modifier_une_ligne_supprimee_renvoie_404(self):
        self.ligne.soft_delete()
        reponse = self.client.patch(
            enfant_url(self.ligne),
            {"nom": "X", "version": 2},
            format="json",
        )
        self.assertEqual(reponse.status_code, 404)

    def test_les_mesures_de_l_enfant_sont_supprimees_avec_lui(self):
        mesure = self.mesure(self.ligne)
        self.client.delete(enfant_url(self.ligne))
        self.assertEqual(self.client.get(MESURES).data["results"], [])
        self.assertIsNotNone(Mesure.all_objects.get(pk=mesure.pk).deleted_at)

    def test_enfant_avec_referencement_non_supprimable(self):
        self.referencement(enfant=self.ligne)
        reponse = self.client.delete(enfant_url(self.ligne))
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(reponse.data["code"], "referencement_existant")
        self.ligne.refresh_from_db()
        self.assertIsNone(self.ligne.deleted_at)

    def test_mesure_supprimee_invisible(self):
        mesure = self.mesure(self.ligne)
        self.assertEqual(self.client.delete(mesure_url(mesure)).status_code, 204)
        self.assertEqual(self.client.get(mesure_url(mesure)).status_code, 404)
        self.assertEqual(self.client.get(MESURES).data["results"], [])


class ListesTest(BaseApiTest):
    def test_pagination_50(self):
        for numero in range(51):
            self.enfant(nom=f"E{numero}")
        self.comme(self.asc)
        reponse = self.client.get(ENFANTS)
        self.assertEqual(reponse.data["count"], 51)
        self.assertEqual(len(reponse.data["results"]), 50)
        self.assertIsNotNone(reponse.data["next"])

    def test_plus_recent_d_abord(self):
        ancien = self.enfant(nom="Ancien")
        recent = self.enfant(nom="Récent")
        self.comme(self.asc)
        lignes = self.client.get(ENFANTS).data["results"]
        self.assertEqual(
            [ligne["id"] for ligne in lignes],
            [str(recent.pk), str(ancien.pk)],
        )

    def test_filtres_enfants(self):
        hery = self.enfant(nom="Hery", statut_prise_en_charge="suivi")
        koto = self.enfant(nom="Koto", region=self.autre_region)
        self.comme(self.asc)
        self.assertEqual(self.ids(self.client.get(f"{ENFANTS}?search=her")), {str(hery.pk)})
        self.assertEqual(
            self.ids(self.client.get(f"{ENFANTS}?region={self.autre_region.pk}")),
            {str(koto.pk)},
        )
        self.assertEqual(
            self.ids(self.client.get(f"{ENFANTS}?statut_prise_en_charge=suivi")),
            {str(hery.pk)},
        )

    def test_updated_since(self):
        ancien = self.enfant(nom="Ancien")
        recent = self.enfant(nom="Récent")
        limite = recent.updated_at
        Enfant.objects.filter(pk=ancien.pk).update(
            updated_at=limite - timedelta(days=1)
        )
        self.comme(self.asc)
        reponse = self.client.get(
            ENFANTS,
            {"updated_since": limite.isoformat()},
        )
        self.assertEqual(self.ids(reponse), {str(recent.pk)})

    def test_updated_since_invalide(self):
        self.comme(self.asc)
        self.assertEqual(
            self.client.get(f"{ENFANTS}?updated_since=hier").status_code,
            400,
        )


class CalculsMesureTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.ligne = self.enfant(date_naissance=date(2025, 1, 1))

    def donnees(self, **extra):
        return {
            "date_mesure": "2026-01-01",
            "poids_kg": "8.50",
            "taille_cm": "70.0",
            "position": "couche",
            "alerte": "vert",
            **extra,
        }

    def creer(self, **extra):
        self.comme(self.asc)
        return self.client.post(
            f"{ENFANTS}{self.ligne.pk}/measurements/",
            self.donnees(**extra),
            format="json",
        )

    def test_age_calcule_par_le_serveur(self):
        reponse = self.creer(age_jour=1, age_mois=1, taille_corrigee_cm="1.0")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["age_jour"], 365)
        self.assertEqual(reponse.data["age_mois"], 11)
        self.assertEqual(Decimal(reponse.data["taille_corrigee_cm"]), Decimal("70.0"))
        self.assertEqual(reponse.data["enfant_id"], self.ligne.pk)
        self.assertEqual(reponse.data["asc_id"], self.asc.pk)

    def test_correction_de_taille(self):
        naissance = date(2025, 1, 1)
        cas = [
            (730, "couche", "70.0"),
            (730, "debout", "70.7"),
            (731, "debout", "70.0"),
            (731, "couche", "69.3"),
        ]
        for jours, position, attendu in cas:
            with self.subTest(jours=jours, position=position):
                champs = calculer_champs_mesure(
                    self.enfant(date_naissance=naissance),
                    naissance + timedelta(days=jours),
                    Decimal("70.0"),
                    position,
                    None,
                )
                self.assertEqual(champs["taille_corrigee_cm"], Decimal(attendu))

    def test_pb_refuse_avant_6_mois(self):
        # 182 days = 5.98 months, 183 days = 6.01 months.
        reponse = self.creer(date_mesure="2025-07-02", pb_mm=120)
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(
            reponse.data["pb_mm"],
            ["Le périmètre brachial ne peut être saisi qu'entre 6 et 59 mois."],
        )
        self.assertEqual(Mesure.objects.count(), 0)

    def test_pb_accepte_a_6_mois(self):
        reponse = self.creer(date_mesure="2025-07-03", pb_mm=120)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["age_mois"], 6)

    def test_pb_accepte_a_59_mois(self):
        # 1826 days = 59.99 months.
        reponse = self.creer(date_mesure="2030-01-01", pb_mm=150)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["age_mois"], 59)

    def test_pb_refuse_a_60_mois(self):
        reponse = self.creer(date_mesure="2030-01-02", pb_mm=150)
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("pb_mm", reponse.data)

    def test_pb_refuse_si_une_mise_a_jour_sort_de_l_age(self):
        mesure = self.mesure(self.ligne, pb_mm=120, age_mois=11)
        self.comme(self.asc)
        reponse = self.client.patch(
            mesure_url(mesure),
            {"date_mesure": "2030-01-02", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("pb_mm", reponse.data)
        mesure.refresh_from_db()
        self.assertEqual(mesure.date_mesure, date(2026, 1, 1))

    def test_mise_a_jour_recalcule_l_age(self):
        mesure = self.mesure(self.ligne, age_jour=1, age_mois=0)
        self.comme(self.asc)
        reponse = self.client.patch(
            mesure_url(mesure),
            {"position": "debout", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["age_jour"], 365)
        self.assertEqual(Decimal(reponse.data["taille_corrigee_cm"]), Decimal("70.7"))

    def test_date_avant_la_naissance_refusee(self):
        reponse = self.creer(date_mesure="2024-12-31")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("date_mesure", reponse.data)

    def test_limites(self):
        cas = [
            ("poids_kg", "0.2", "Le poids doit être compris entre 0,3 et 40 kg."),
            ("taille_cm", "24.9", "La taille doit être comprise entre 25 et 130 cm."),
            ("pb_mm", 69, "Le périmètre brachial doit être compris entre 70 et 250 mm."),
        ]
        for champ, valeur, message in cas:
            with self.subTest(champ=champ):
                reponse = self.creer(**{champ: valeur})
                self.assertEqual(reponse.status_code, 400)
                self.assertEqual(reponse.data[champ], [message])

    def test_valeurs_oms_du_telephone_gardees_pour_l_instant(self):
        reponse = self.creer(
            waz="-2.10",
            haz="-1.50",
            whz="-2.40",
            alerte="orange",
            motif_alerte="WHZ bas",
            flag_aberrant=True,
        )
        self.assertEqual(Decimal(reponse.data["waz"]), Decimal("-2.10"))
        self.assertEqual(reponse.data["alerte"], "orange")
        self.assertEqual(reponse.data["motif_alerte"], "WHZ bas")
        self.assertTrue(reponse.data["flag_aberrant"])

    def test_l_enfant_d_une_mesure_ne_change_pas(self):
        autre = self.enfant(nom="Autre")
        mesure = self.mesure(self.ligne)
        self.comme(self.asc)
        reponse = self.client.patch(
            mesure_url(mesure),
            {"enfant_id": str(autre.pk), "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("enfant_id", reponse.data)

    def test_nouvelle_date_de_naissance_recalcule_les_mesures(self):
        mesure = self.mesure(self.ligne)
        self.comme(self.asc)
        reponse = self.client.patch(
            enfant_url(self.ligne),
            {"date_naissance": "2025-01-02", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        mesure.refresh_from_db()
        self.assertEqual(mesure.age_jour, 364)
        self.assertEqual(mesure.version, 2)

    def test_date_de_naissance_refusee_si_un_pb_sort_de_l_age(self):
        mesure = self.mesure(self.ligne, pb_mm=120)
        self.comme(self.asc)
        reponse = self.client.patch(
            enfant_url(self.ligne),
            {"date_naissance": "2025-11-01", "version": 1},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("date_naissance", reponse.data)
        self.ligne.refresh_from_db()
        mesure.refresh_from_db()
        self.assertEqual(self.ligne.date_naissance, date(2025, 1, 1))
        self.assertEqual(self.ligne.version, 1)
        self.assertEqual(mesure.version, 1)


class AccesMesuresTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.le_mien = self.enfant(mere=self.femme)
        self.le_sien = self.enfant(asc=self.autre_asc)
        self.ma_mesure = self.mesure(self.le_mien, alerte="rouge")
        self.sa_mesure = self.mesure(self.le_sien)

    def donnees(self, enfant):
        return {
            "enfant_id": str(enfant.pk),
            "date_mesure": "2026-01-01",
            "poids_kg": "8.50",
            "taille_cm": "70.0",
            "position": "couche",
            "alerte": "vert",
        }

    def test_asc_ne_voit_que_ses_mesures(self):
        self.comme(self.asc)
        self.assertEqual(self.ids(self.client.get(MESURES)), {str(self.ma_mesure.pk)})
        self.assertEqual(self.client.get(mesure_url(self.sa_mesure)).status_code, 404)

    def test_asc_ne_peut_pas_mesurer_l_enfant_d_un_autre(self):
        self.comme(self.asc)
        reponse = self.client.post(MESURES, self.donnees(self.le_sien), format="json")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("enfant_id", reponse.data)
        reponse = self.client.post(
            f"{ENFANTS}{self.le_sien.pk}/measurements/",
            self.donnees(self.le_sien),
            format="json",
        )
        self.assertEqual(reponse.status_code, 404)
        self.assertEqual(Mesure.objects.count(), 2)

    def test_liste_par_enfant(self):
        self.mesure(self.enfant(nom="Autre"))
        self.comme(self.asc)
        reponse = self.client.get(f"{ENFANTS}{self.le_mien.pk}/measurements/")
        self.assertEqual(self.ids(reponse), {str(self.ma_mesure.pk)})

    def test_beneficiaire_pese_son_enfant_sans_asc(self):
        """M1 (D16): a weighing at home has no ASC, so it is not a screening."""
        self.comme(self.femme)
        self.assertEqual(self.ids(self.client.get(MESURES)), {str(self.ma_mesure.pk)})
        reponse = self.client.post(MESURES, self.donnees(self.le_mien), format="json")
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertIsNone(reponse.data["asc_id"])
        self.assertEqual(
            self.client.post(MESURES, self.donnees(self.le_sien), format="json").status_code,
            400,
        )

    def test_agent_lit_les_mesures_liees_a_son_csb(self):
        self.referencement(enfant=self.le_mien, csb=self.csb)
        self.comme(self.agent)
        self.assertEqual(self.ids(self.client.get(MESURES)), {str(self.ma_mesure.pk)})
        self.assertEqual(self.client.get(mesure_url(self.sa_mesure)).status_code, 404)
        self.assertEqual(self.client.delete(mesure_url(self.ma_mesure)).status_code, 403)

    def test_filtres_mesures(self):
        autre = self.mesure(self.le_mien, date_mesure=date(2026, 6, 1), alerte="vert")
        self.comme(self.asc)
        self.assertEqual(
            self.ids(self.client.get(f"{MESURES}?alerte=rouge")),
            {str(self.ma_mesure.pk)},
        )
        self.assertEqual(
            self.ids(self.client.get(f"{MESURES}?date_min=2026-05-01&date_max=2026-07-01")),
            {str(autre.pk)},
        )
