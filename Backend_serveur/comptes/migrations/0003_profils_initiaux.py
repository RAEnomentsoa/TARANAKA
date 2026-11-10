from django.db import migrations

PROFILS = (
    ("beneficiaire", "Bénéficiaire"),
    ("asc", "Agent de santé communautaire"),
    ("agent_csb", "Agent de CSB"),
    ("admin", "Administrateur"),
)


def creer_profils(apps, schema_editor):
    Profile = apps.get_model("comptes", "Profile")
    for code, libelle in PROFILS:
        Profile.objects.get_or_create(code=code, defaults={"libelle": libelle})


def supprimer_profils(apps, schema_editor):
    Profile = apps.get_model("comptes", "Profile")
    Profile.objects.filter(code__in=[code for code, _ in PROFILS]).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("comptes", "0002_profile_remplace_role"),
    ]

    operations = [
        migrations.RunPython(creer_profils, supprimer_profils),
    ]
