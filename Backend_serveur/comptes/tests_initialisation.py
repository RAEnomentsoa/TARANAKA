"""initialiser_serveur: run on every deploy, so it must do each step once."""

import io
from unittest import mock

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from comptes.models import CodeProfile, User
from config_clinique.models import ConfigurationClinique

VARIABLES = {"ADMIN_IDENTIFIANT": "Admin.Railway", "ADMIN_PIN": "482915"}


def lancer(**variables):
    with mock.patch.dict("os.environ", variables, clear=False):
        call_command("initialiser_serveur", stdout=io.StringIO())


class InitialiserServeurTest(TestCase):
    def test_deux_deploiements_ne_creent_qu_une_fois(self):
        lancer(**VARIABLES)
        lancer(**VARIABLES)
        admin = User.objects.get(identifiant="Admin.Railway")
        self.assertTrue(admin.is_superuser)
        self.assertEqual(admin.profile.code, CodeProfile.ADMIN)
        self.assertTrue(admin.check_password("482915"))
        self.assertEqual(ConfigurationClinique.objects.count(), 1)

    def test_sans_variables_seule_la_config_est_publiee(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            call_command("initialiser_serveur", stdout=io.StringIO())
        self.assertFalse(User.objects.filter(is_superuser=True).exists())
        self.assertEqual(ConfigurationClinique.objects.count(), 1)

    def test_pin_invalide_refuse(self):
        with self.assertRaises(CommandError):
            lancer(ADMIN_IDENTIFIANT="admin", ADMIN_PIN="motdepasse")

    def test_demo_chargee_une_fois(self):
        lancer(CHARGER_DEMO="True")
        lancer(CHARGER_DEMO="True")
        self.assertTrue(User.objects.filter(identifiant="ac.rasoa").exists())
