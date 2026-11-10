from django.db import migrations

CODE = "superviseur"
LIBELLE = "Superviseur"


def creer_profil(apps, schema_editor):
    Profile = apps.get_model("comptes", "Profile")
    Profile.objects.get_or_create(code=CODE, defaults={"libelle": LIBELLE})


def supprimer_profil(apps, schema_editor):
    Profile = apps.get_model("comptes", "Profile")
    Profile.objects.filter(code=CODE).delete()


class Migration(migrations.Migration):

    dependencies = [
        ("comptes", "0004_utilisateur_csb"),
    ]

    operations = [
        migrations.RunPython(creer_profil, supprimer_profil),
    ]
