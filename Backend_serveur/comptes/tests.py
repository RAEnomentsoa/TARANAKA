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
                "nom": "Rabe",
                "prenom": "Soa",
                "profile": {
                    "code": "asc",
                    "libelle": "Agent de santé communautaire",
                },
                "region_id": None,
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

    def test_quatre_profils_crees_par_la_migration(self):
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
        self.assertFalse(Profile.objects.filter(code__in=CodeProfile.values).exists())


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
