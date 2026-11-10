import csv
from decimal import Decimal
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from referentiel.models import Indicateur, ReferenceOms

# WHO's expanded LMS tables, as published in the WHO "anthro" package
# (https://github.com/WorldHealthOrganization/anthro, data-raw/growthstandards).
FICHIERS = {
    "weianthro.txt": (Indicateur.WFA, "age", None),
    "lenanthro.txt": (Indicateur.LHFA, "age", "loh"),
    "wflanthro.txt": (Indicateur.WFL, "length", "lorh"),
    "wfhanthro.txt": (Indicateur.WFH, "height", "lorh"),
}
SEXES = {"1": "M", "2": "F"}


class Command(BaseCommand):
    help = (
        "Importe les tables LMS OMS 2006 (weianthro, lenanthro, wflanthro, "
        "wfhanthro .txt) dans reference_oms. Les lignes existantes sont mises à jour."
    )

    def add_arguments(self, parser):
        parser.add_argument("dossier")

    def handle(self, dossier, **options):
        dossier = Path(dossier)
        trouves = [nom for nom in FICHIERS if (dossier / nom).exists()]
        if not trouves:
            raise CommandError(f"Aucun fichier OMS dans {dossier} ({', '.join(FICHIERS)}).")
        with transaction.atomic():
            for nom in trouves:
                lignes = self._lire(dossier / nom, *FICHIERS[nom])
                ReferenceOms.objects.bulk_create(
                    lignes,
                    batch_size=1000,
                    update_conflicts=True,
                    unique_fields=["indicateur", "sexe", "cle"],
                    update_fields=["valeur_l", "valeur_m", "valeur_s", "mesure_type"],
                )
                self.stdout.write(f"{nom} : {len(lignes)} lignes")
        self.stdout.write(self.style.SUCCESS("Tables OMS importées."))

    def _lire(self, chemin, indicateur, colonne_cle, colonne_type):
        with chemin.open(encoding="utf-8") as fichier:
            return [
                ReferenceOms(
                    indicateur=indicateur,
                    sexe=SEXES[ligne["sex"]],
                    cle=Decimal(ligne[colonne_cle]),
                    valeur_l=Decimal(ligne["l"]),
                    valeur_m=Decimal(ligne["m"]),
                    valeur_s=Decimal(ligne["s"]),
                    mesure_type=(ligne.get(colonne_type) or "") if colonne_type else "",
                )
                for ligne in csv.DictReader(fichier, delimiter="\t")
            ]
