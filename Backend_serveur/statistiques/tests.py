import csv
import io
from datetime import date, timedelta

from django.utils import timezone

from comptes.models import CodeProfile
from referencement.models import RendezVous
from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

STATS = "/api/stats/"
PERIODE = "date_debut=2026-10-01&date_fin=2026-11-30"


class StatistiquesTest(BaseApiTest):
    def setUp(self):
        super().setUp()
        self.superviseur = self.compte("sup", CodeProfile.SUPERVISEUR, region=self.region)
        self.national = self.compte("sup-nat", CodeProfile.SUPERVISEUR)
        maintenant = timezone.now()
        # 6 MAS children and 2 MAM children screened in the region.
        for numero in range(6):
            self.mesure(
                self.enfant(nom=f"MAS {numero}"),
                date_mesure=date(2026, 11, 2),
                classification="mas",
            )
        for numero in range(2):
            self.mesure(
                self.enfant(nom=f"MAM {numero}"),
                date_mesure=date(2026, 11, 2),
                classification="mam",
            )
        # 6 referrals to the region's CSB, 5 arrived after 24 hours.
        for numero in range(6):
            arrive = numero < 5
            self.referencement(
                code=f"R-{numero}",
                enfant=self.enfant(nom=f"Ref {numero}"),
                date_referencement=maintenant - timedelta(days=3),
                date_reception=maintenant - timedelta(days=2) if arrive else None,
                status="recu" if arrive else "envoye",
            )
        # One MAS child in the other region.
        self.mesure(
            self.enfant(nom="Ailleurs", asc=self.autre_asc, region=self.autre_region),
            date_mesure=date(2026, 11, 2),
            classification="mas",
        )

    def stats(self, parametres=PERIODE, user=None):
        self.comme(user or self.superviseur)
        return self.client.get(f"{STATS}?{parametres}")

    def test_compteurs_de_la_region(self):
        reponse = self.stats()
        self.assertEqual(reponse.status_code, 200, reponse.data)
        indicateurs = reponse.data["total"]["indicateurs"]
        self.assertEqual(indicateurs["depistages"], 8)
        self.assertEqual(indicateurs["cas_mas"], 6)
        self.assertEqual(indicateurs["referencements"], 6)
        self.assertEqual(indicateurs["referencements_arrives"], 5)
        self.assertEqual(indicateurs["taux_arrivee_pct"], 83.3)
        self.assertEqual(indicateurs["delai_moyen_arrivee_heures"], 24.0)

    def test_petits_effectifs_masques(self):
        total = self.stats().data["total"]
        self.assertIsNone(total["indicateurs"]["cas_mam"])
        self.assertIn("cas_mam", total["masques"])
        # 0 is not a small count: it reveals nobody.
        self.assertEqual(total["indicateurs"]["nourrissons_a_risque"], 0)
        self.assertNotIn("nourrissons_a_risque", total["masques"])

    def test_taux_masque_si_le_denominateur_est_petit(self):
        reponse = self.stats(PERIODE, self.national)
        self.assertIsNotNone(reponse.data["total"]["indicateurs"]["taux_arrivee_pct"])
        reponse = self.stats(f"{PERIODE}&region={self.autre_region.pk}", self.national)
        indicateurs = reponse.data["total"]["indicateurs"]
        self.assertIsNone(indicateurs["cas_mas"])
        self.assertIsNone(indicateurs["taux_arrivee_pct"])

    def test_aucune_donnee_nominative(self):
        contenu = str(self.stats(f"{PERIODE}&grouper_par=region").data)
        for interdit in ("MAS 0", "Hery", "R-0", str(self.asc.pk), "asc"):
            self.assertNotIn(interdit, contenu)

    def test_superviseur_regional_limite_a_sa_region(self):
        reponse = self.stats(f"{PERIODE}&grouper_par=region")
        self.assertEqual([g["libelle"] for g in reponse.data["groupes"]], ["Analamanga"])
        self.assertEqual(
            self.stats(f"{PERIODE}&region={self.autre_region.pk}").status_code,
            403,
        )

    def test_superviseur_national_par_region(self):
        reponse = self.stats(f"{PERIODE}&grouper_par=region", self.national)
        groupes = {g["libelle"]: g["indicateurs"] for g in reponse.data["groupes"]}
        self.assertEqual(groupes["Analamanga"]["cas_mas"], 6)
        self.assertIsNone(groupes["Itasy"]["cas_mas"])
        self.assertEqual(reponse.data["total"]["indicateurs"]["cas_mas"], 7)

    def test_par_mois(self):
        reponse = self.stats(f"{PERIODE}&grouper_par=mois")
        self.assertEqual([g["cle"] for g in reponse.data["groupes"]], ["2026-10", "2026-11"])
        self.assertEqual(reponse.data["groupes"][0]["indicateurs"]["depistages"], 0)
        self.assertEqual(reponse.data["groupes"][1]["indicateurs"]["depistages"], 8)

    def test_compteur_mas_augmente_de_un(self):
        """Scenario 8: one more MAS child, the supervisor's counter goes up by 1."""
        avant = self.stats().data["total"]["indicateurs"]["cas_mas"]
        self.mesure(self.enfant(nom="Nouveau"), date_mesure=date(2026, 11, 4), classification="mas")
        apres = self.stats().data["total"]["indicateurs"]["cas_mas"]
        self.assertEqual(apres, avant + 1)

    def test_sorties_et_rendez_vous_manques(self):
        petit = self.enfant(nom="Sorti")
        for numero in range(5):
            self.referencement(
                code=f"S-{numero}",
                enfant=petit,
                status="sortie",
                issue_sortie="gueri",
                date_reception=timezone.now() - timedelta(days=2),
                date_sortie=timezone.now(),
            )
        RendezVous.objects.create(enfant=petit, date_prevue=timezone.localdate() - timedelta(days=1))
        fin = timezone.localdate()
        reponse = self.stats(f"date_debut={fin - timedelta(days=10)}&date_fin={fin}")
        indicateurs = reponse.data["total"]["indicateurs"]
        self.assertEqual(indicateurs["sorties_gueri"], 5)
        self.assertIsNone(indicateurs["rendez_vous_manques"])
        self.assertIn("rendez_vous_manques", reponse.data["total"]["masques"])

    def test_acces_reserve(self):
        for user in (self.asc, self.agent, self.femme):
            with self.subTest(user=user.identifiant):
                self.assertEqual(self.stats(user=user).status_code, 403)
        self.assertEqual(self.stats(user=self.admin).status_code, 200)

    def test_periode_invalide(self):
        self.assertEqual(self.stats("date_debut=2026-12-01&date_fin=2026-11-01").status_code, 400)

    def test_export_csv(self):
        self.comme(self.superviseur)
        reponse = self.client.get(f"{STATS}export/?{PERIODE}")
        self.assertEqual(reponse.status_code, 200)
        self.assertTrue(reponse["Content-Type"].startswith("text/csv"))
        lignes = list(csv.reader(io.StringIO(reponse.content.decode())))
        self.assertEqual(lignes[0], ["groupe", "indicateur", "valeur"])
        valeurs = {ligne[1]: ligne[2] for ligne in lignes[1:] if ligne[0] == "total"}
        self.assertEqual(valeurs["cas_mas"], "6")
        self.assertEqual(valeurs["cas_mam"], "<5")
        audit = JournalAudit.objects.get(action="export_csv")
        self.assertEqual(audit.user, self.superviseur)
