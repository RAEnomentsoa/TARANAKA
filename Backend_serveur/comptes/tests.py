from datetime import timedelta
from importlib import import_module

from django.apps import apps
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.test import SimpleTestCase, TestCase, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory, APITestCase
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from synchro.models import JournalAudit
from synchro.outils_tests import BaseApiTest

from . import services
from .models import CodeProfile, Profile, User
from .permissions import IsAdmin, IsASC, profil_requis
from .validators import valider_pin

LOGIN = "/api/auth/login/"
REFRESH = "/api/auth/refresh/"
LOGOUT = "/api/auth/logout/"
ME = "/api/auth/me/"
CHANGER_PIN = "/api/auth/changer-pin/"
PIN = "1234"
MESSAGE_INCORRECT = "Identifiant ou PIN incorrect"
SESSION_INVALIDE = {
    "detail": "Session invalide ou expirée. Veuillez vous reconnecter.",
    "code": "token_not_valid",
}


class VueAsc(APIView):
    permission_classes = [IsASC]

    def get(self, request):
        return Response({})


class VueAscOuAgent(APIView):
    permission_classes = [profil_requis(CodeProfile.ASC, CodeProfile.AGENT_CSB)]

    def get(self, request):
        return Response({})


@override_settings(
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class BaseAuthTest(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = self.creer_utilisateur("0341112233", CodeProfile.ASC)

    def creer_utilisateur(self, identifiant, code, **extra):
        return User.objects.create_user(
            identifiant,
            PIN,
            nom="Rabe",
            prenom="Soa",
            profile=Profile.objects.get(code=code),
            **extra,
        )

    def login(self, identifiant="0341112233", pin=PIN):
        return self.client.post(LOGIN, {"identifiant": identifiant, "pin": pin})

    def echouer(self, fois):
        for _ in range(fois):
            cache.clear()
            reponse = self.login(pin="9999")
        return reponse

    def fixer_tentatives(self, nombre):
        User.objects.filter(pk=self.user.pk).update(tentatives_echouees=nombre)

    def authentifier(self, user=None):
        token = RefreshToken.for_user(user or self.user).access_token
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")


class LoginTests(BaseAuthTest):
    def test_pin_correct(self):
        reponse = self.login()
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("access", reponse.data)
        self.assertIn("refresh", reponse.data)
        self.assertEqual(
            reponse.json()["utilisateur"],
            {
                "id": str(self.user.id),
                "identifiant": self.user.identifiant,
                "nom": "Rabe",
                "prenom": "Soa",
                "profile": {
                    "code": "asc",
                    "libelle": "Agent de santé communautaire",
                },
                "region_id": None,
                "csb_id": None,
                "code_beneficiaire": None,
                "partage_cycle": False,
            },
        )
        ligne = JournalAudit.objects.get(action="login_succes")
        self.assertEqual(ligne.user, self.user)
        self.assertEqual(ligne.ligne_id, self.user.id)

    def test_pin_incorrect(self):
        reponse = self.login(pin="9999")
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reponse.data["detail"], MESSAGE_INCORRECT)
        self.user.refresh_from_db()
        self.assertEqual(self.user.tentatives_echouees, 1)
        self.assertEqual(JournalAudit.objects.get().action, "login_echec")

    def test_identifiant_inconnu_meme_message(self):
        inconnu = self.login(identifiant="0000000000", pin="9999")
        mauvais_pin = self.login(pin="9999")
        self.assertEqual(inconnu.status_code, mauvais_pin.status_code)
        self.assertEqual(inconnu.json(), mauvais_pin.json())
        ligne = JournalAudit.objects.get(user__isnull=True)
        self.assertEqual(ligne.action, "login_echec")
        self.assertEqual(ligne.details["identifiant"], "0000000000")
        self.assertIsNone(ligne.ligne_id)

    def test_compte_inactif_meme_message(self):
        User.objects.filter(pk=self.user.pk).update(is_active=False)
        reponse = self.login()
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reponse.data["detail"], MESSAGE_INCORRECT)

    def test_succes_remet_le_compteur_a_zero(self):
        self.echouer(4)
        self.assertEqual(self.login().status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.tentatives_echouees, 0)
        self.assertIsNotNone(self.user.last_login)

    def test_limite_de_requetes(self):
        for _ in range(10):
            self.client.post(LOGIN, {})
        reponse = self.client.post(LOGIN, {})
        self.assertEqual(reponse.status_code, status.HTTP_429_TOO_MANY_REQUESTS)


class BlocageTests(BaseAuthTest):
    def test_bloque_15_minutes_apres_5_echecs(self):
        self.assertEqual(self.echouer(4).status_code, status.HTTP_401_UNAUTHORIZED)
        reponse = self.echouer(1)
        self.assertEqual(reponse.status_code, status.HTTP_423_LOCKED)
        self.assertEqual(reponse.data["code"], "compte_bloque")
        self.assertIn("15 minute", reponse.data["detail"])
        self.assertAlmostEqual(reponse.data["secondes_restantes"], 900, delta=5)

        pin_correct = self.login()
        self.assertEqual(pin_correct.status_code, status.HTTP_423_LOCKED)
        self.assertTrue(JournalAudit.objects.filter(action="login_bloque").exists())

    def test_les_essais_pendant_le_blocage_ne_comptent_pas(self):
        self.echouer(7)
        self.user.refresh_from_db()
        self.assertEqual(self.user.tentatives_echouees, 5)

    def test_debloque_apres_15_minutes(self):
        self.echouer(5)
        User.objects.filter(pk=self.user.pk).update(
            bloque_jusqu_a=timezone.now() - timedelta(seconds=1),
        )
        self.assertEqual(self.login().status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.tentatives_echouees, 0)
        self.assertIsNone(self.user.bloque_jusqu_a)

    def test_bloque_1_heure_apres_10_echecs(self):
        self.fixer_tentatives(9)
        reponse = self.echouer(1)
        self.assertEqual(reponse.status_code, status.HTTP_423_LOCKED)
        self.assertAlmostEqual(reponse.data["secondes_restantes"], 3600, delta=5)

    def test_compteur_continue_apres_la_fin_du_blocage(self):
        self.fixer_tentatives(5)
        reponse = self.echouer(1)
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)
        self.user.refresh_from_db()
        self.assertEqual(self.user.tentatives_echouees, 6)

    def test_bloque_jusqu_a_deblocage_par_admin_apres_15_echecs(self):
        self.fixer_tentatives(14)
        reponse = self.echouer(1)
        self.assertEqual(reponse.status_code, status.HTTP_423_LOCKED)
        self.assertIsNone(reponse.data["secondes_restantes"])
        self.assertIn("administrateur", reponse.data["detail"])
        self.assertEqual(self.login().status_code, status.HTTP_423_LOCKED)

        admin = User.objects.create_superuser("admin", "Motdepasse!9", nom="A", prenom="B")
        self.user.refresh_from_db()
        services.debloquer(self.user, admin, "127.0.0.1")
        self.assertEqual(self.login().status_code, status.HTTP_200_OK)
        ligne = JournalAudit.objects.get(action="compte_debloque")
        self.assertEqual(ligne.user, admin)
        self.assertEqual(ligne.ligne_id, self.user.id)


class TokenTests(BaseAuthTest):
    def test_refresh_donne_de_nouveaux_tokens(self):
        ancien = self.login().data["refresh"]
        reponse = self.client.post(REFRESH, {"refresh": ancien})
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("access", reponse.data)
        self.assertNotEqual(reponse.data["refresh"], ancien)

    def test_ancien_refresh_refuse_apres_rotation(self):
        ancien = self.login().data["refresh"]
        self.client.post(REFRESH, {"refresh": ancien})
        reponse = self.client.post(REFRESH, {"refresh": ancien})
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reponse.json(), SESSION_INVALIDE)

    def test_logout_met_le_token_sur_liste_noire(self):
        refresh = self.login().data["refresh"]
        reponse = self.client.post(LOGOUT, {"refresh": refresh})
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        refuse = self.client.post(REFRESH, {"refresh": refresh})
        self.assertEqual(refuse.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_token_invalide(self):
        reponse = self.client.post(LOGOUT, {"refresh": "pas-un-token"})
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_refresh_refuse_si_compte_desactive(self):
        refresh = self.login().data["refresh"]
        User.objects.filter(pk=self.user.pk).update(is_active=False)
        reponse = self.client.post(REFRESH, {"refresh": refresh})
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reponse.data["code"], "no_active_account")
        self.assertEqual(reponse.data["detail"], SESSION_INVALIDE["detail"])

    def test_duree_des_tokens(self):
        refresh = RefreshToken.for_user(self.user)
        self.assertEqual(refresh.lifetime, timedelta(days=30))
        self.assertEqual(refresh.access_token.lifetime, timedelta(hours=1))


class MeTests(BaseAuthTest):
    def test_me(self):
        self.authentifier()
        reponse = self.client.get(ME)
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["profile"]["code"], "asc")

    def test_me_sans_token(self):
        self.assertEqual(self.client.get(ME).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_token_invalide(self):
        self.client.credentials(HTTP_AUTHORIZATION="Bearer pas-un-token")
        reponse = self.client.get(ME)
        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reponse.json(), SESSION_INVALIDE)

    def test_me_sans_requete_supplementaire_pour_le_profil(self):
        self.authentifier()
        with self.assertNumQueries(1):
            self.client.get(ME)


class ProfilTests(BaseAuthTest):
    def appeler(self, vue, user):
        token = RefreshToken.for_user(user).access_token
        requete = APIRequestFactory().get("/", HTTP_AUTHORIZATION=f"Bearer {token}")
        return vue.as_view()(requete).status_code

    def test_mauvais_profil_refuse(self):
        beneficiaire = self.creer_utilisateur("b", CodeProfile.BENEFICIAIRE)
        self.assertEqual(self.appeler(VueAsc, beneficiaire), status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.appeler(VueAsc, self.user), status.HTTP_200_OK)

    def test_plusieurs_profils_autorises(self):
        agent = self.creer_utilisateur("c", CodeProfile.AGENT_CSB)
        admin = self.creer_utilisateur("d", CodeProfile.ADMIN)
        self.assertEqual(self.appeler(VueAscOuAgent, agent), status.HTTP_200_OK)
        self.assertEqual(self.appeler(VueAscOuAgent, admin), status.HTTP_403_FORBIDDEN)

    def test_superuser_recoit_le_profil_admin(self):
        admin = User.objects.create_superuser("admin", "Motdepasse!9", nom="A", prenom="B")
        self.assertEqual(admin.profile.code, CodeProfile.ADMIN)
        self.assertIn(CodeProfile.ADMIN, IsAdmin.codes)

    def test_profil_inconnu_sans_acces(self):
        Profile.objects.create(code="sage_femme", libelle="Sage-femme")
        inconnu = self.creer_utilisateur("e", "sage_femme")

        reponse = self.login(identifiant="e")
        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(reponse.data["code"], "profil_inconnu")
        self.assertNotIn("access", reponse.data)

        self.authentifier(inconnu)
        me = self.client.get(ME)
        self.assertEqual(me.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(
            me.json(),
            {"detail": "Votre profil ne permet pas d'accéder à cette ressource."},
        )

    def test_profils_crees_par_les_migrations(self):
        codes = set(Profile.objects.values_list("code", flat=True))
        self.assertEqual(codes, set(CodeProfile.values))


class ChangerPinTests(BaseAuthTest):
    def changer(self, ancien=PIN, nouveau="567890"):
        return self.client.post(
            CHANGER_PIN,
            {"ancien_pin": ancien, "nouveau_pin": nouveau},
        )

    def test_changer_pin(self):
        ancien_refresh = self.login().data["refresh"]
        self.authentifier()
        reponse = self.changer()
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("access", reponse.data)

        self.assertEqual(self.login().status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(self.login(pin="567890").status_code, status.HTTP_200_OK)
        revoque = self.client.post(REFRESH, {"refresh": ancien_refresh})
        self.assertEqual(revoque.status_code, status.HTTP_401_UNAUTHORIZED)
        nouveau = self.client.post(REFRESH, {"refresh": reponse.data["refresh"]})
        self.assertEqual(nouveau.status_code, status.HTTP_200_OK)

    def test_ancien_pin_incorrect_compte_comme_un_echec(self):
        self.authentifier()
        reponse = self.changer(ancien="9999")
        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(reponse.data["code"], "ancien_pin_incorrect")
        self.user.refresh_from_db()
        self.assertEqual(self.user.tentatives_echouees, 1)

    def test_bloque_apres_5_mauvais_anciens_pins(self):
        self.fixer_tentatives(4)
        self.authentifier()
        self.assertEqual(self.changer(ancien="9999").status_code, status.HTTP_423_LOCKED)
        self.assertEqual(self.changer().status_code, status.HTTP_423_LOCKED)

    def test_format_du_nouveau_pin(self):
        self.authentifier()
        reponse = self.changer(nouveau="12a4")
        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("nouveau_pin", reponse.data)

    def test_refuse_pour_les_comptes_staff(self):
        staff = self.creer_utilisateur("f", CodeProfile.ADMIN, is_staff=True)
        self.authentifier(staff)
        reponse = self.changer()
        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(reponse.data["code"], "pin_non_modifiable")


class MigrationProfilsTests(TestCase):
    def test_retour_arriere_supprime_les_4_profils(self):
        migration = import_module("comptes.migrations.0003_profils_initiaux")
        migration.supprimer_profils(apps, None)
        codes = [code for code, _ in migration.PROFILS]
        self.assertFalse(Profile.objects.filter(code__in=codes).exists())

    def test_retour_arriere_supprime_le_superviseur(self):
        migration = import_module("comptes.migrations.0005_profil_superviseur")
        migration.supprimer_profil(apps, None)
        self.assertFalse(Profile.objects.filter(code="superviseur").exists())


class ValidateurPinTests(SimpleTestCase):
    def test_pins_valides(self):
        for pin in ("1234", "12345", "123456"):
            with self.subTest(pin=pin):
                valider_pin(pin)

    def test_pins_invalides(self):
        for pin in ("123", "1234567", "12a4", "", "12 34", "١٢٣٤", "1234\n"):
            with self.subTest(pin=pin):
                with self.assertRaises(ValidationError):
                    valider_pin(pin)


class ComptesApiTest(BaseApiTest):
    URL = "/api/profiles/"

    def donnees(self, **extra):
        return {
            "identifiant": "0340000000",
            "nom": "Rasoa",
            "prenom": "Vola",
            "pin": "4321",
            **extra,
        }

    def creer(self, **extra):
        return self.client.post(self.URL, self.donnees(**extra), format="json")

    def test_asc_cree_une_beneficiaire_dans_sa_region(self):
        self.comme(self.asc)
        reponse = self.creer()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["profile"]["code"], "beneficiaire")
        self.assertEqual(reponse.data["region_id"], self.region.pk)
        self.assertNotIn("pin", reponse.data)
        self.assertNotIn("password", reponse.data)
        compte = User.objects.get(identifiant="0340000000")
        self.assertTrue(compte.check_password("4321"))
        self.assertNotEqual(compte.password, "4321")
        ligne = JournalAudit.objects.get(action="create", table_nom="utilisateur")
        self.assertEqual(ligne.user, self.asc)
        self.assertNotIn("4321", str(ligne.details))

    def test_asc_ne_choisit_pas_une_autre_region(self):
        self.comme(self.asc)
        reponse = self.creer(region_id=self.autre_region.pk)
        self.assertEqual(reponse.data["region_id"], self.region.pk)

    def test_asc_ne_cree_ni_asc_ni_admin_ni_agent(self):
        self.comme(self.asc)
        for code in ("asc", "admin", "agent_csb"):
            with self.subTest(code=code):
                reponse = self.creer(profile_code=code, csb_id=self.csb.pk)
                self.assertEqual(reponse.status_code, 403)
        self.assertFalse(User.objects.filter(identifiant="0340000000").exists())

    def test_asc_sans_region_ne_cree_pas(self):
        self.comme(self.asc_sans_region)
        reponse = self.creer()
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("region_id", reponse.data)

    def test_admin_cree_chaque_profil(self):
        self.comme(self.admin)
        cas = {
            "beneficiaire": {"region_id": self.region.pk},
            "asc": {},
            "agent_csb": {"csb_id": self.csb.pk},
            "admin": {},
        }
        for numero, (code, extra) in enumerate(cas.items()):
            with self.subTest(code=code):
                reponse = self.creer(
                    identifiant=f"id{numero}",
                    profile_code=code,
                    **extra,
                )
                self.assertEqual(reponse.status_code, 201, reponse.data)
                self.assertEqual(reponse.data["profile"]["code"], code)

    def test_compte_admin_de_l_api_sans_acces_a_l_administration(self):
        self.comme(self.admin)
        reponse = self.creer(
            profile_code="admin",
            is_staff=True,
            is_superuser=True,
        )
        self.assertEqual(reponse.status_code, 201, reponse.data)
        compte = User.objects.get(pk=reponse.data["id"])
        self.assertFalse(compte.is_staff)
        self.assertFalse(compte.is_superuser)

    def test_agent_sans_csb_refuse(self):
        self.comme(self.admin)
        reponse = self.creer(profile_code="agent_csb")
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(
            reponse.data["csb_id"],
            ["Le CSB est obligatoire pour un agent de CSB."],
        )

    def test_beneficiaire_sans_region_refusee(self):
        self.comme(self.admin)
        reponse = self.creer(profile_code="beneficiaire")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("region_id", reponse.data)

    def test_le_csb_est_reserve_aux_agents(self):
        self.comme(self.admin)
        reponse = self.creer(profile_code="asc", csb_id=self.csb.pk)
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertIsNone(reponse.data["csb_id"])

    def test_identifiant_en_double(self):
        self.comme(self.asc)
        reponse = self.creer(identifiant="femme")
        self.assertEqual(reponse.status_code, 400)
        self.assertEqual(
            reponse.data["identifiant"],
            ["Cet identifiant est déjà utilisé."],
        )

    def test_pin_invalide_ou_absent(self):
        self.comme(self.asc)
        self.assertEqual(
            self.creer(pin="12")
            .data["pin"],
            ["Le PIN doit contenir de 4 à 6 chiffres."],
        )
        donnees = self.donnees()
        del donnees["pin"]
        reponse = self.client.post(self.URL, donnees, format="json")
        self.assertEqual(reponse.data["pin"], ["Ce champ est obligatoire."])

    def test_beneficiaire_ne_lit_qu_elle_meme(self):
        self.comme(self.femme)
        self.assertEqual(self.ids(self.client.get(self.URL)), {str(self.femme.pk)})
        self.assertEqual(
            self.client.get(f"{self.URL}{self.autre_femme.pk}/").status_code,
            404,
        )
        self.assertEqual(self.creer().status_code, 403)
        self.assertEqual(
            self.client.patch(
                f"{self.URL}{self.femme.pk}/",
                {"nom": "X"},
                format="json",
            ).status_code,
            403,
        )

    def test_asc_lit_les_beneficiaires_de_sa_region_seulement(self):
        self.comme(self.asc)
        self.assertEqual(self.ids(self.client.get(self.URL)), {str(self.femme.pk)})
        self.assertEqual(
            self.client.get(f"{self.URL}{self.autre_femme.pk}/").status_code,
            404,
        )
        self.assertEqual(
            self.client.get(f"{self.URL}{self.asc_meme_region.pk}/").status_code,
            404,
        )
        self.assertEqual(
            self.client.patch(
                f"{self.URL}{self.femme.pk}/",
                {"nom": "X"},
                format="json",
            ).status_code,
            403,
        )

    def test_asc_sans_region_ne_voit_pas_les_femmes_sans_region(self):
        self.comme(self.asc_sans_region)
        self.assertEqual(self.client.get(self.URL).data["results"], [])

    def test_agent_refuse(self):
        self.comme(self.agent)
        self.assertEqual(self.client.get(self.URL).status_code, 403)
        self.assertEqual(self.creer().status_code, 403)

    def test_admin_modifie_et_desactive(self):
        self.comme(self.admin)
        reponse = self.client.patch(
            f"{self.URL}{self.femme.pk}/",
            {"nom": "Nouveau", "is_active": False, "pin": "9999"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.femme.refresh_from_db()
        self.assertEqual(self.femme.nom, "Nouveau")
        self.assertFalse(self.femme.is_active)
        self.assertTrue(self.femme.check_password("1234"))

    def test_admin_ne_retire_pas_le_csb_d_un_agent(self):
        self.comme(self.admin)
        reponse = self.client.patch(
            f"{self.URL}{self.agent.pk}/",
            {"csb_id": None},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("csb_id", reponse.data)

    def test_pas_de_suppression(self):
        self.comme(self.admin)
        self.assertEqual(self.client.delete(f"{self.URL}{self.femme.pk}/").status_code, 405)

    def test_me_renvoie_le_csb(self):
        self.comme(self.agent)
        self.assertEqual(self.client.get(ME).data["csb_id"], self.csb.pk)


class ValidationCsbModeleTest(BaseApiTest):
    def test_clean_exige_le_csb(self):
        agent = User(
            identifiant="x",
            nom="X",
            prenom="X",
            profile=Profile.objects.get(code=CodeProfile.AGENT_CSB),
        )
        with self.assertRaises(ValidationError) as contexte:
            agent.clean()
        self.assertEqual(
            contexte.exception.message_dict["csb"],
            ["Le CSB est obligatoire pour un agent de CSB."],
        )
        agent.csb = self.csb
        agent.clean()
