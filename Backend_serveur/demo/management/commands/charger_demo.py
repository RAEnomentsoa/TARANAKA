from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError

from demo import donnees


class Command(BaseCommand):
    help = (
        "Charge le jeu de données fictif des 8 scénarios de démonstration "
        "(spec §13) dans une base vide. Voir docs/DEMO.md."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--tables-oms",
            metavar="DOSSIER",
            help="Importe aussi les tables OMS 2006 depuis ce dossier.",
        )

    def handle(self, tables_oms=None, **options):
        if donnees.deja_charge():
            raise CommandError("Les données de démonstration sont déjà chargées.")
        if tables_oms:
            call_command("importer_tables_oms", tables_oms, stdout=self.stdout)
        donnees.charger(sortie=self.stdout.write)
        self.stdout.write(self.style.SUCCESS("Comptes de démonstration :"))
        for identifiant, code, pin, nom, prenom in donnees.COMPTES:
            self.stdout.write(f"  {identifiant:<16} {code:<13} PIN {pin}  ({prenom} {nom})")
        self.stdout.write(
            self.style.WARNING(
                "Données fictives. Configuration clinique « À VALIDER » : ne pas utiliser en production."
            )
        )
