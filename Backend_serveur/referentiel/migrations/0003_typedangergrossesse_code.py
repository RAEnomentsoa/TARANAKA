import json
from pathlib import Path

from django.db import migrations, models

EXEMPLE = (
    Path(__file__).resolve().parents[2]
    / "config_clinique"
    / "exemples"
    / "config_clinique_exemple.json"
)


def remplir_codes(apps, schema_editor):
    """Existing types were created from the example config by their French
    label: give them the config code the phone sends."""
    TypeDangerGrossesse = apps.get_model("referentiel", "TypeDangerGrossesse")
    try:
        config = json.loads(EXEMPLE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return
    for signe in config.get("signes_danger", {}).get("grossesse", []):
        TypeDangerGrossesse.objects.filter(
            description=signe.get("fr"), code__isnull=True
        ).update(code=signe.get("code"))


class Migration(migrations.Migration):

    dependencies = [
        ('referentiel', '0002_type_centre'),
    ]

    operations = [
        migrations.AddField(
            model_name='typedangergrossesse',
            name='code',
            field=models.CharField(blank=True, max_length=50, null=True, unique=True),
        ),
        migrations.RunPython(remplir_codes, migrations.RunPython.noop),
    ]
