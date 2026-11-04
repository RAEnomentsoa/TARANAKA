"""Sync tests: idempotent outbox push, incremental pull, conflict queue (spec §9)."""

import gzip
import json
import uuid
from datetime import date, timedelta
from io import StringIO
from pathlib import Path

from django.conf import settings
from django.core.management import call_command
from django.test import SimpleTestCase
from django.utils import timezone

from comptes.models import CodeProfile
from nutrition.models import Enfant, Mesure
from referencement.models import Referencement
from sante_femme.models import Cycle
from synchro.models import (
    ConflitSync,
    HistoriqueVersion,
    JournalAudit,
    OperationSync,
)
from synchro.outils_tests import BaseApiTest

PUSH = "/api/sync/push/"
PULL = "/api/sync/pull/"
CONFLITS = "/api/conflicts/"


def operation(table, op, ligne_id=None, cle=None, **extra):
    return {
        "cle_idempotence": str(cle or uuid.uuid4()),
        "table": table,
        "operation": op,
        "id": str(ligne_id or uuid.uuid4()),
        **extra,
    }


class BaseSyncTest(BaseApiTest):
    def pousser(self, *operations, device="tel-asc-1", user=None):
        if user is not None:
            self.comme(user)
        return self.client.post(
            PUSH,
            {"operations": list(operations)},
            format="json",
            HTTP_X_DEVICE_ID=device,
        )

    def resultats(self, reponse):
        self.assertEqual(reponse.status_code, 200, reponse.data)
        return reponse.data["resultats"]

    def donnees_enfant(self, **extra):
        return {
            "nom": "Hery",
            "region_id": self.region.pk,
            "date_naissance": "2025-05-04",
            "sexe": "M",
            **extra,
        }

    def donnees_mesure(self, enfant_id, **extra):
        return {
            "enfant_id": str(enfant_id),
            "date_mesure": "2026-11-04",
            "poids_kg": "8.10",
            "taille_cm": "75.0",
            "position": "couche",
            "pb_mm": 112,
            "alerte": "orange",
            **extra,
        }


class PushTest(BaseSyncTest):
    def setUp(self):
        super().setUp()
        self.comme(self.asc)

    def test_lot_hors_ligne_applique_dans_l_ordre(self):
        """Scenario 5 then 7: child, measurement and referral made offline."""
        self.publier_config()
        enfant_id, mesure_id, ref_id = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
        reponse = self.pousser(
            operation("enfant", "create", enfant_id, donnees=self.donnees_enfant()),
            operation("mesure", "create", mesure_id, donnees=self.donnees_mesure(enfant_id)),
            operation(
                "referencement",
                "create",
                ref_id,
                donnees={
                    "code_unique": "TRK-7F3K-92",
                    "origine": "enfant",
                    "enfant_id": str(enfant_id),
                    "mesure_id": str(mesure_id),
                    "csb_id": self.csb.pk,
                    "priorite": "haute",
                    "motif": "MAS – PB 112 mm",
                    "date_referencement": "2026-11-04T07:30:00Z",
                },
            ),
        )
        resultats = self.resultats(reponse)
        self.assertEqual([r["statut"] for r in resultats], ["applique"] * 3, resultats)
        self.assertEqual(resultats[1]["ligne"]["classification"], "mas")
        self.assertEqual(resultats[2]["ligne"]["code_unique"], "TRK-7F3K-92")
        self.assertEqual(resultats[2]["ligne"]["status"], "envoye")
        self.assertEqual(Referencement.objects.get().device_id, "tel-asc-1")

    def test_renvoi_force_ne_cree_aucun_doublon(self):
        """Scenario 7: the same outbox sent twice."""
        enfant_id = uuid.uuid4()
        lot = [operation("enfant", "create", enfant_id, donnees=self.donnees_enfant())]
        premier = self.resultats(self.pousser(*lot))[0]
        second = self.resultats(self.pousser(*lot))[0]
        self.assertEqual(premier["statut"], "applique")
        self.assertFalse(premier["rejoue"])
        self.assertEqual(second["statut"], "applique")
        self.assertTrue(second["rejoue"])
        self.assertEqual(second["ligne"], premier["ligne"])
        self.assertEqual(Enfant.objects.count(), 1)
        self.assertEqual(OperationSync.objects.count(), 1)

    def test_meme_ligne_avec_une_nouvelle_cle(self):
        enfant_id = uuid.uuid4()
        self.pousser(operation("enfant", "create", enfant_id, donnees=self.donnees_enfant()))
        resultat = self.resultats(
            self.pousser(operation("enfant", "create", enfant_id, donnees=self.donnees_enfant()))
        )[0]
        self.assertEqual(resultat["statut"], "deja_applique")
        self.assertEqual(Enfant.objects.count(), 1)

    def test_une_erreur_ne_bloque_pas_la_suite(self):
        resultats = self.resultats(
            self.pousser(
                {"table": "enfant", "operation": "create"},
                operation("enfant", "create", donnees=self.donnees_enfant(sexe="X")),
                operation("enfant", "create", donnees=self.donnees_enfant()),
            )
        )
        self.assertEqual([r["statut"] for r in resultats], ["erreur", "erreur", "applique"])
        self.assertIn("cle_idempotence", resultats[0]["erreurs"])
        self.assertIn("sexe", resultats[1]["erreurs"])
        self.assertEqual(Enfant.objects.count(), 1)

    def test_une_erreur_n_est_pas_memorisee(self):
        """Once the cause is fixed, the same key can be retried."""
        cle = uuid.uuid4()
        enfant_id = uuid.uuid4()
        mesure = operation(
            "mesure",
            "create",
            cle=cle,
            donnees=self.donnees_mesure(enfant_id),
        )
        self.assertEqual(self.resultats(self.pousser(mesure))[0]["statut"], "erreur")
        self.pousser(operation("enfant", "create", enfant_id, donnees=self.donnees_enfant()))
        self.assertEqual(self.resultats(self.pousser(mesure))[0]["statut"], "applique")

    def test_cle_d_un_autre_utilisateur_refusee(self):
        cle = uuid.uuid4()
        self.pousser(operation("enfant", "create", cle=cle, donnees=self.donnees_enfant()))
        resultat = self.resultats(
            self.pousser(
                operation("enfant", "create", cle=cle, donnees=self.donnees_enfant()),
                user=self.asc_meme_region,
            )
        )[0]
        self.assertEqual(resultat["statut"], "erreur")
        self.assertIn("cle_idempotence", resultat["erreurs"])

    def test_modification_puis_suppression(self):
        petit = self.enfant()
        resultat = self.resultats(
            self.pousser(operation("enfant", "update", petit.pk, version=1, donnees={"nom": "Rivo"}))
        )[0]
        self.assertEqual(resultat["statut"], "applique")
        self.assertEqual(resultat["ligne"]["version"], 2)

        suppression = operation("enfant", "delete", petit.pk, version=2)
        self.assertEqual(self.resultats(self.pousser(suppression))[0]["statut"], "applique")
        autre_cle = {**suppression, "cle_idempotence": str(uuid.uuid4())}
        self.assertEqual(
            self.resultats(self.pousser(autre_cle))[0]["statut"],
            "deja_applique",
        )

    def test_version_obligatoire_pour_une_modification(self):
        petit = self.enfant()
        resultat = self.resultats(
            self.pousser(operation("enfant", "update", petit.pk, donnees={"nom": "Rivo"}))
        )[0]
        self.assertEqual(resultat["statut"], "erreur")
        self.assertIn("version", resultat["erreurs"])

    def test_ligne_inconnue_ou_hors_de_portee(self):
        autre = self.enfant(asc=self.autre_asc)
        for ligne_id in (uuid.uuid4(), autre.pk):
            with self.subTest(ligne_id=ligne_id):
                resultat = self.resultats(
                    self.pousser(operation("enfant", "update", ligne_id, version=1, donnees={}))
                )[0]
                self.assertEqual(resultat["statut"], "introuvable")

    def test_trop_d_operations(self):
        lot = [operation("enfant", "create", donnees=self.donnees_enfant()) for _ in range(101)]
        self.assertEqual(self.pousser(*lot).status_code, 400)

    def test_signe_de_danger_cree_le_referencement(self):
        grossesse = self.grossesse()
        resultat = self.resultats(
            self.pousser(
                operation(
                    "danger_grossesse",
                    "create",
                    donnees={
                        "grossesse_id": str(grossesse.pk),
                        "type_danger_grossesse_id": self.type_danger.pk,
                        "csb_id": self.csb.pk,
                    },
                )
            )
        )[0]
        self.assertEqual(resultat["statut"], "applique", resultat)
        self.assertIsNotNone(resultat["ligne"]["referencement_id"])

    def test_corps_compresse_gzip(self):
        corps = json.dumps(
            {"operations": [operation("enfant", "create", donnees=self.donnees_enfant())]}
        ).encode()
        reponse = self.client.post(
            PUSH,
            gzip.compress(corps),
            content_type="application/json",
            HTTP_CONTENT_ENCODING="gzip",
        )
        self.assertEqual(self.resultats(reponse)[0]["statut"], "applique")


class PermissionsSyncTest(BaseSyncTest):
    """/sync applies exactly the same rights as the REST endpoints."""

    def test_agent_ne_cree_pas_d_enfant(self):
        resultat = self.resultats(
            self.pousser(
                operation("enfant", "create", donnees=self.donnees_enfant()),
                user=self.agent,
            )
        )[0]
        self.assertEqual(resultat["statut"], "refuse")

    def test_superviseur_n_ecrit_rien(self):
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        resultat = self.resultats(
            self.pousser(
                operation("enfant", "create", donnees=self.donnees_enfant()),
                user=superviseur,
            )
        )[0]
        self.assertEqual(resultat["statut"], "refuse")

    def test_asc_n_ecrit_pas_de_cycle(self):
        resultat = self.resultats(
            self.pousser(
                operation(
                    "cycle",
                    "create",
                    donnees={"date_debut": "2026-10-01", "intensite": "moyenne"},
                ),
                user=self.asc,
            )
        )[0]
        self.assertEqual(resultat["statut"], "refuse")

    def test_beneficiaire_synchronise_son_cycle(self):
        resultat = self.resultats(
            self.pousser(
                operation(
                    "cycle",
                    "create",
                    donnees={"date_debut": "2026-10-01", "intensite": "moyenne"},
                ),
                user=self.femme,
            )
        )[0]
        self.assertEqual(resultat["statut"], "applique")
        self.assertEqual(Cycle.objects.get().user, self.femme)

    def test_sans_token(self):
        self.client.force_authenticate(None)
        self.assertEqual(self.client.post(PUSH, {"operations": []}, format="json").status_code, 401)
        self.assertEqual(self.client.get(PULL).status_code, 401)


class ConflitTest(BaseSyncTest):
    """Scenario 7: a concurrent change of the same record creates a visible conflict."""

    def setUp(self):
        super().setUp()
        self.petit = self.enfant()
        self.ligne = self.referencement(enfant=self.petit, motif="PB 112 mm")
        # Another phone changed the referral first: the server is at version 2.
        Referencement.objects.filter(pk=self.ligne.pk).update(
            version=2,
            motif="PB 112 mm, œdèmes à vérifier",
            device_id="tel-admin",
        )

    def envoyer_conflit(self, cle=None):
        return self.resultats(
            self.pousser(
                operation(
                    "referencement",
                    "update",
                    self.ligne.pk,
                    cle=cle,
                    version=1,
                    donnees={"motif": "PB 110 mm"},
                ),
                user=self.admin,
            )
        )[0]

    def test_conflit_garde_les_deux_versions(self):
        resultat = self.envoyer_conflit()
        self.assertEqual(resultat["statut"], "conflit")
        self.assertEqual(resultat["ligne"]["motif"], "PB 112 mm, œdèmes à vérifier")
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.motif, "PB 112 mm, œdèmes à vérifier")
        self.assertEqual(self.ligne.version, 2)

        conflit = ConflitSync.objects.get(pk=resultat["conflit_id"])
        self.assertEqual(conflit.statut, "a_verifier")
        self.assertEqual(conflit.donnees_telephone, {"motif": "PB 110 mm"})
        self.assertEqual(conflit.version_base, 1)
        self.assertEqual(conflit.version_serveur, 2)
        versions = HistoriqueVersion.objects.filter(ligne_id=self.ligne.pk, conflit=True)
        self.assertEqual(versions.count(), 2)
        self.assertTrue(JournalAudit.objects.filter(action="conflit_sync").exists())

    def test_renvoi_du_meme_conflit_ne_le_duplique_pas(self):
        cle = uuid.uuid4()
        premier = self.envoyer_conflit(cle)
        second = self.envoyer_conflit(cle)
        self.assertTrue(second["rejoue"])
        self.assertEqual(second["conflit_id"], premier["conflit_id"])
        self.assertEqual(ConflitSync.objects.count(), 1)

    def test_conflit_visible_sur_le_web_par_le_centre(self):
        conflit_id = self.envoyer_conflit()["conflit_id"]
        self.comme(self.agent)
        reponse = self.client.get(f"{CONFLITS}?statut=a_verifier")
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(self.ids(reponse), {conflit_id})
        self.comme(self.autre_agent)
        self.assertEqual(self.client.get(CONFLITS).data["count"], 0)
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        self.comme(superviseur)
        self.assertEqual(self.client.get(CONFLITS).status_code, 403)

    def test_resolution_garder_le_serveur(self):
        conflit_id = self.envoyer_conflit()["conflit_id"]
        self.comme(self.agent)
        reponse = self.client.post(
            f"{CONFLITS}{conflit_id}/resolve/",
            {"choix": "serveur", "commentaire": "Mesure du centre plus fiable"},
            format="json",
            HTTP_X_DEVICE_ID="poste-csb",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["statut"], "resolu")
        self.assertEqual(reponse.data["version_finale"], 3)
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.motif, "PB 112 mm, œdèmes à vérifier")
        self.assertEqual(self.ligne.version, 3)
        audit = JournalAudit.objects.get(action="conflit_resolu")
        self.assertEqual(audit.user, self.agent)
        self.assertEqual(audit.details["device_id"], "poste-csb")

    def test_resolution_garder_le_telephone(self):
        conflit_id = self.envoyer_conflit()["conflit_id"]
        self.comme(self.agent)
        reponse = self.client.post(
            f"{CONFLITS}{conflit_id}/resolve/",
            {"choix": "telephone"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.motif, "PB 110 mm")

    def test_resolution_fusion(self):
        conflit_id = self.envoyer_conflit()["conflit_id"]
        self.comme(self.agent)
        url = f"{CONFLITS}{conflit_id}/resolve/"
        self.assertEqual(
            self.client.post(url, {"choix": "fusion"}, format="json").status_code,
            400,
        )
        reponse = self.client.post(
            url,
            {"choix": "fusion", "donnees": {"motif": "PB 110 mm, œdèmes à vérifier"}},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.ligne.refresh_from_db()
        self.assertEqual(self.ligne.motif, "PB 110 mm, œdèmes à vérifier")
        self.assertEqual(
            self.client.post(url, {"choix": "serveur"}, format="json").status_code,
            400,
        )

    def test_asc_ne_resout_pas(self):
        mesure = self.mesure(self.petit)
        Mesure.objects.filter(pk=mesure.pk).update(version=2)
        resultat = self.resultats(
            self.pousser(
                operation("mesure", "update", mesure.pk, version=1, donnees={"pb_mm": 110}),
                user=self.asc,
            )
        )[0]
        self.assertEqual(resultat["statut"], "conflit")
        reponse = self.client.get(CONFLITS)
        self.assertEqual(self.ids(reponse), {resultat["conflit_id"]})
        reponse = self.client.post(
            f"{CONFLITS}{resultat['conflit_id']}/resolve/",
            {"choix": "telephone"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 403)

    def test_donnees_personnelles_sans_file_web(self):
        cycle = Cycle.objects.create(
            user=self.femme,
            date_debut=date(2026, 10, 1),
            intensite="moyenne",
            version=3,
        )
        resultat = self.resultats(
            self.pousser(
                operation("cycle", "update", cycle.pk, version=1, donnees={"intensite": "forte"}),
                user=self.femme,
            )
        )[0]
        self.assertEqual(resultat["statut"], "conflit")
        self.assertIsNone(resultat["conflit_id"])
        self.assertEqual(resultat["ligne"]["intensite"], "moyenne")
        self.assertFalse(ConflitSync.objects.exists())


class PullTest(BaseSyncTest):
    def tirer(self, **parametres):
        reponse = self.client.get(PULL, parametres)
        self.assertEqual(reponse.status_code, 200, reponse.data)
        return reponse.data

    def test_premiere_synchronisation_et_suppressions(self):
        garde = self.enfant(nom="Garde")
        supprime = self.enfant(nom="Supprime")
        supprime.soft_delete(device_id="tel-2")
        self.enfant(nom="Autre", asc=self.autre_asc)
        self.comme(self.asc)
        donnees = self.tirer()
        lignes = {ligne["id"]: ligne for ligne in donnees["tables"]["enfant"]["lignes"]}
        self.assertEqual(set(lignes), {str(garde.pk), str(supprime.pk)})
        self.assertIsNotNone(lignes[str(supprime.pk)]["deleted_at"])
        self.assertIsNone(lignes[str(garde.pk)]["deleted_at"])
        self.assertNotIn("cycle", donnees["tables"])

    def test_seulement_ce_qui_a_change(self):
        ancien = self.enfant(nom="Ancien")
        Enfant.all_objects.filter(pk=ancien.pk).update(
            updated_at=timezone.now() - timedelta(days=2)
        )
        recent = self.enfant(nom="Recent")
        self.comme(self.asc)
        depuis = (timezone.now() - timedelta(days=1)).isoformat()
        donnees = self.tirer(depuis=depuis, tables="enfant,mesure")
        self.assertEqual(
            [ligne["id"] for ligne in donnees["tables"]["enfant"]["lignes"]],
            [str(recent.pk)],
        )
        self.assertEqual(set(donnees["tables"]), {"enfant", "mesure"})

    def test_pagination_par_table(self):
        for numero in range(5):
            self.enfant(nom=f"Enfant {numero}")
        # Same timestamp for every row: the cursor must still move forward.
        meme_instant = timezone.now() - timedelta(minutes=1)
        Enfant.all_objects.update(updated_at=meme_instant)
        self.comme(self.asc)
        vus, parametres = [], {"tables": "enfant", "limite": 2}
        for _ in range(5):
            page = self.tirer(**parametres)["tables"]["enfant"]
            vus += [ligne["id"] for ligne in page["lignes"]]
            if not page["suite"]:
                break
            parametres.update(depuis=page["prochain_depuis"], apres_id=page["apres_id"])
        self.assertFalse(page["suite"])
        self.assertEqual(len(vus), 5)
        self.assertEqual(len(set(vus)), 5)

    def test_apres_id_sans_depuis(self):
        self.comme(self.asc)
        reponse = self.client.get(PULL, {"apres_id": str(uuid.uuid4())})
        self.assertEqual(reponse.status_code, 400)

    def test_table_inconnue(self):
        self.comme(self.asc)
        self.assertEqual(self.client.get(PULL, {"tables": "utilisateur"}).status_code, 400)

    def test_configuration_telechargee_si_plus_recente(self):
        config = self.publier_config()
        self.comme(self.asc)
        donnees = self.tirer()
        self.assertEqual(donnees["config_clinique"]["version"], config.version)
        self.assertEqual(donnees["config_clinique"]["mise_a_jour"]["version"], config.version)
        a_jour = self.tirer(config_version=config.version)
        self.assertIsNone(a_jour["config_clinique"]["mise_a_jour"])

    def test_superviseur_ne_recoit_aucune_ligne(self):
        self.enfant()
        superviseur = self.compte("sup", CodeProfile.SUPERVISEUR)
        self.comme(superviseur)
        self.assertEqual(self.tirer()["tables"], {})

    def test_l_asc_voit_recu_par_le_centre(self):
        """Scenario 8: the ASC sees « Reçu par le centre » at the next sync."""
        ligne = self.referencement(enfant=self.enfant())
        self.comme(self.asc)
        depuis = self.tirer()["horodatage_serveur"]
        self.comme(self.agent)
        self.client.post(
            f"/api/referrals/{ligne.pk}/status/",
            {"status": "recu", "version": 1},
            format="json",
        )
        self.comme(self.asc)
        lignes = self.tirer(depuis=depuis, tables="referencement")["tables"]["referencement"]["lignes"]
        self.assertEqual([(l["id"], l["status"]) for l in lignes], [(str(ligne.pk), "recu")])

    def test_etat_des_conflits_de_l_utilisateur(self):
        petit = self.enfant()
        mesure = self.mesure(petit)
        Mesure.objects.filter(pk=mesure.pk).update(version=2)
        self.comme(self.asc)
        conflit_id = self.resultats(
            self.pousser(operation("mesure", "update", mesure.pk, version=1, donnees={"pb_mm": 110}))
        )[0]["conflit_id"]
        self.referencement(enfant=petit)
        self.comme(self.agent)
        self.client.post(f"{CONFLITS}{conflit_id}/resolve/", {"choix": "telephone"}, format="json")
        self.comme(self.asc)
        donnees = self.tirer(tables="mesure")
        self.assertEqual(
            [(c["id"], c["statut"], c["resolution"]) for c in donnees["conflits"]],
            [(conflit_id, "resolu", "telephone")],
        )
        self.assertEqual(donnees["tables"]["mesure"]["lignes"][0]["pb_mm"], 110)


class SchemaOpenApiTest(SimpleTestCase):
    """docs/openapi.yaml must match the code. To update it, from Backend_serveur/:
    python manage.py spectacular --file ../docs/openapi.yaml --validate"""

    def test_fichier_a_jour(self):
        sortie = StringIO()
        call_command("spectacular", "--validate", "--fail-on-warn", stdout=sortie)
        fichier = Path(settings.BASE_DIR).parent / "docs" / "openapi.yaml"
        self.assertEqual(sortie.getvalue(), fichier.read_text(encoding="utf-8"))
