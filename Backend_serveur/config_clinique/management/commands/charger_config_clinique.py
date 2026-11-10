import json
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from rest_framework.exceptions import ValidationError

from config_clinique import services


class Command(BaseCommand):
    help = (
        "Charge un fichier JSON comme nouvelle version de la configuration clinique. "
        "Sans fichier, charge l'exemple marqué « À VALIDER »."
    )

    def add_arguments(self, parser):
        parser.add_argument("fichier", nargs="?", default=str(services.EXEMPLE))
        parser.add_argument("--libelle", default="")
        parser.add_argument("--publier", action="store_true")

    def handle(self, fichier, libelle, publier, **options):
        chemin = Path(fichier)
        try:
            contenu = json.loads(chemin.read_text(encoding="utf-8"))
        except (OSError, ValueError) as erreur:
            raise CommandError(f"Fichier illisible : {erreur}") from erreur
        try:
            config = services.creer_version(
                {
                    "libelle": libelle or chemin.stem,
                    "contenu": contenu,
                    "notes": f"Chargé depuis {chemin.name}",
                }
            )
            if publier:
                config = services.publier(config)
        except ValidationError as erreur:
            raise CommandError(json.dumps(erreur.detail, ensure_ascii=False)) from erreur
        self.stdout.write(
            self.style.SUCCESS(f"Version {config.version} créée ({config.get_statut_display()}).")
        )
        if config.statut_validation != "validee":
            self.stdout.write(self.style.WARNING("Statut de validation : À VALIDER."))
