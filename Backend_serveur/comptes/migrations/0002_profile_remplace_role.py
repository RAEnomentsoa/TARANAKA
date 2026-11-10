import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("comptes", "0001_initial"),
    ]

    operations = [
        migrations.AlterModelOptions(
            name="profile",
            options={
                "ordering": ["libelle"],
                "verbose_name": "Profil",
                "verbose_name_plural": "Profils",
            },
        ),
        migrations.RemoveField(
            model_name="user",
            name="role",
        ),
        migrations.RemoveField(
            model_name="profile",
            name="type",
        ),
        migrations.AddField(
            model_name="profile",
            name="code",
            field=models.CharField(default="", max_length=30, unique=True),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name="profile",
            name="libelle",
            field=models.CharField(default="", max_length=100),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name="user",
            name="tentatives_echouees",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="user",
            name="bloque_jusqu_a",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="user",
            name="profile",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name="utilisateurs",
                to="comptes.profile",
            ),
        ),
    ]
