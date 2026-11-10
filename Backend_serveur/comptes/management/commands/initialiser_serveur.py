"""First setup of a server, from environment variables (Railway, Docker…).

Safe to run on every deploy: each step does nothing when already done.

- ADMIN_IDENTIFIANT, ADMIN_PIN (4 to 6 digits), ADMIN_NOM, ADMIN_PRENOM:
  the first administrator, created if missing. Never updated afterwards
  (change the PIN from /admin/).
- CHARGER_DEMO=True: the fictitious demo data (docs/DEMO.md), once.
- Then, if no clinical config is published, the sample one is loaded and
  published (marked « À VALIDER »).
"""

import os

from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError

from comptes.models import User
from comptes.validators import valider_pin
from config_clinique.services import config_active


class Command(BaseCommand):
    help = "Prépare un serveur neuf (admin, config clinique, démo) ; sans effet si c'est déjà fait."

    def handle(self, **options):
        self.demo()
        self.config_clinique()
        self.administrateur()

    def demo(self):
        if os.getenv("CHARGER_DEMO", "False") != "True":
            return
        from demo import donnees

        if donnees.deja_charge():
            self.stdout.write("Démo : déjà chargée.")
            return
        call_command("charger_demo", stdout=self.stdout)

    def config_clinique(self):
        if config_active() is not None:
            self.stdout.write("Configuration clinique : une version est déjà publiée.")
            return
        call_command("charger_config_clinique", publier=True, stdout=self.stdout)

    def administrateur(self):
        identifiant = os.getenv("ADMIN_IDENTIFIANT", "").strip()
        pin = os.getenv("ADMIN_PIN", "").strip()
        if not identifiant or not pin:
            self.stdout.write("Administrateur : ADMIN_IDENTIFIANT ou ADMIN_PIN absent, rien à faire.")
            return
        if User.objects.filter(identifiant__iexact=identifiant).exists():
            self.stdout.write(f"Administrateur : « {identifiant} » existe déjà.")
            return
        try:
            valider_pin(pin)
        except ValidationError as erreur:
            raise CommandError(f"ADMIN_PIN : {erreur.messages[0]}") from erreur
        User.objects.create_superuser(
            identifiant,
            pin,
            nom=os.getenv("ADMIN_NOM", "Administrateur"),
            prenom=os.getenv("ADMIN_PRENOM", "TARANAKA"),
        )
        self.stdout.write(self.style.SUCCESS(f"Administrateur « {identifiant} » créé."))
