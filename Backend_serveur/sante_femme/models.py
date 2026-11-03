from django.conf import settings
from django.db import models

from synchro.models import SyncModel


class Intensite(models.TextChoices):
    FAIBLE = "faible", "Faible"
    MOYENNE = "moyenne", "Moyenne"
    FORTE = "forte", "Forte"


class Cycle(SyncModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="cycles",
    )
    date_debut = models.DateField()
    date_fin = models.DateField(null=True, blank=True)
    intensite = models.CharField(max_length=10, choices=Intensite.choices)
    symptome = models.TextField(blank=True)
    duree_cycle = models.PositiveSmallIntegerField(null=True, blank=True)
    duree_regle = models.PositiveSmallIntegerField(null=True, blank=True)
    estimation_prochain = models.DateField(null=True, blank=True)

    class Meta:
        db_table = "cycle"
        verbose_name = "Cycle"
        verbose_name_plural = "Cycles"
        ordering = ["-date_debut"]

    def __str__(self):
        return f"Cycle du {self.date_debut}"


class Grossesse(SyncModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="grossesses",
    )
    ddr = models.DateField()
    dpa = models.DateField()

    class Meta:
        db_table = "grossesse"
        verbose_name = "Grossesse"
        verbose_name_plural = "Grossesses"
        ordering = ["-ddr"]

    def __str__(self):
        return f"Grossesse (DDR {self.ddr})"


class DangerGrossesse(SyncModel):
    grossesse = models.ForeignKey(
        Grossesse,
        on_delete=models.PROTECT,
        related_name="dangers",
    )
    type_danger_grossesse = models.ForeignKey(
        "referentiel.TypeDangerGrossesse",
        on_delete=models.PROTECT,
        related_name="signalements",
    )
    date_signalement = models.DateTimeField()

    class Meta:
        db_table = "danger_grossesse"
        verbose_name = "Signe de danger de grossesse"
        verbose_name_plural = "Signes de danger de grossesse"
        ordering = ["-date_signalement"]

    def __str__(self):
        return f"Signe de danger du {self.date_signalement:%Y-%m-%d}"
