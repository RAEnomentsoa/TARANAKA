from django.conf import settings
from django.db import models


class StatutPublication(models.TextChoices):
    BROUILLON = "brouillon", "Brouillon"
    PUBLIEE = "publiee", "Publiée"
    RETIREE = "retiree", "Retirée"


class StatutValidation(models.TextChoices):
    A_VALIDER = "a_valider", "À VALIDER"
    VALIDEE = "validee", "Validée"


class ConfigurationClinique(models.Model):
    """One version of the clinical rules and content (spec §11).

    Thresholds, referral rules, calendars, danger signs and advice live in
    `contenu`, never in the code. A published version can't change: a change
    means a new version.
    """

    id = models.AutoField(primary_key=True)
    version = models.PositiveIntegerField(unique=True, editable=False)
    libelle = models.CharField(max_length=200)
    contenu = models.JSONField()
    statut = models.CharField(
        max_length=10,
        choices=StatutPublication.choices,
        default=StatutPublication.BROUILLON,
    )
    statut_validation = models.CharField(
        max_length=10,
        choices=StatutValidation.choices,
        default=StatutValidation.A_VALIDER,
    )
    valide_par = models.CharField(
        "Validé par (autorité et signataire)",
        max_length=200,
        blank=True,
    )
    reference_validation = models.CharField(
        "Référence du document de validation",
        max_length=200,
        blank=True,
    )
    date_validation = models.DateField(null=True, blank=True)
    notes = models.TextField(blank=True)
    cree_par = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="configurations_creees",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    publiee_le = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "configuration_clinique"
        verbose_name = "Configuration clinique"
        verbose_name_plural = "Configurations cliniques"
        ordering = ["-version"]

    def __str__(self):
        return f"v{self.version} – {self.libelle} ({self.get_statut_display()})"
