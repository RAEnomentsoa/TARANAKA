from django.db import models


class Sexe(models.TextChoices):
    MASCULIN = "M", "Masculin"
    FEMININ = "F", "Féminin"


class Province(models.Model):
    id = models.AutoField(primary_key=True)
    nom = models.CharField(max_length=100)

    class Meta:
        db_table = "province"
        verbose_name = "Province"
        verbose_name_plural = "Provinces"
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class Region(models.Model):
    id = models.AutoField(primary_key=True)
    nom = models.CharField(max_length=100)
    province = models.ForeignKey(
        Province,
        on_delete=models.PROTECT,
        related_name="regions",
    )

    class Meta:
        db_table = "region"
        verbose_name = "Région"
        verbose_name_plural = "Régions"
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class CSB(models.Model):
    id = models.AutoField(primary_key=True)
    name = models.CharField(max_length=150)
    region = models.ForeignKey(
        Region,
        on_delete=models.PROTECT,
        related_name="csbs",
    )
    tel = models.CharField(max_length=20)

    class Meta:
        db_table = "csb"
        verbose_name = "CSB"
        verbose_name_plural = "CSB"
        ordering = ["name"]

    def __str__(self):
        return self.name


class TypeDangerGrossesse(models.Model):
    id = models.AutoField(primary_key=True)
    description = models.TextField()

    class Meta:
        db_table = "type_danger_grossesse"
        verbose_name = "Type de danger de grossesse"
        verbose_name_plural = "Types de danger de grossesse"
        ordering = ["description"]

    def __str__(self):
        return self.description


class Indicateur(models.TextChoices):
    WFA = "wfa", "Poids pour âge"
    LHFA = "lhfa", "Taille pour âge"
    WFL = "wfl", "Poids pour longueur"
    WFH = "wfh", "Poids pour hauteur"


class MesureType(models.TextChoices):
    LONGUEUR = "L", "Couché (longueur)"
    HAUTEUR = "H", "Debout (hauteur)"


class ReferenceOms(models.Model):
    id = models.AutoField(primary_key=True)
    indicateur = models.CharField(max_length=4, choices=Indicateur.choices)
    sexe = models.CharField(max_length=1, choices=Sexe.choices)
    cle = models.DecimalField(max_digits=6, decimal_places=1)
    valeur_l = models.DecimalField(max_digits=8, decimal_places=4, db_column="l")
    valeur_m = models.DecimalField(max_digits=8, decimal_places=4, db_column="m")
    valeur_s = models.DecimalField(max_digits=8, decimal_places=5, db_column="s")
    mesure_type = models.CharField(
        max_length=1,
        choices=MesureType.choices,
        blank=True,
    )

    class Meta:
        db_table = "reference_oms"
        verbose_name = "Référence OMS"
        verbose_name_plural = "Références OMS"
        ordering = ["indicateur", "sexe", "cle"]
        constraints = [
            models.UniqueConstraint(
                fields=["indicateur", "sexe", "cle"],
                name="reference_oms_unique",
            ),
        ]

    def __str__(self):
        return f"{self.indicateur} {self.sexe} {self.cle}"
