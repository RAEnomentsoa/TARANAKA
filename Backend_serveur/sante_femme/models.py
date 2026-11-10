from django.conf import settings
from django.db import models
from django.db.models import Q

from synchro.models import SyncModel


class Intensite(models.TextChoices):
    FAIBLE = "faible", "Faible"
    MOYENNE = "moyenne", "Moyenne"
    FORTE = "forte", "Forte"


class Cycle(SyncModel):
    """A period ("Mon cycle"). On the server only if the woman shares her
    cycle (D16, option a): it is private by default."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="cycles",
    )
    date_debut = models.DateField()
    date_fin = models.DateField(null=True, blank=True)
    intensite = models.CharField(
        max_length=10, choices=Intensite.choices, default=Intensite.MOYENNE
    )
    symptome = models.TextField(blank=True)
    duree_cycle = models.PositiveSmallIntegerField(null=True, blank=True)
    duree_regle = models.PositiveSmallIntegerField(null=True, blank=True)
    estimation_prochain = models.DateField(null=True, blank=True)
    # As on the phone: pain 0-3, mood 1-5, notes, symptom codes, marked irregular.
    douleur = models.PositiveSmallIntegerField(default=0)
    humeur = models.PositiveSmallIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True)
    symptomes = models.JSONField(default=list, blank=True)
    irreguliere = models.BooleanField(default=False)

    class Meta:
        db_table = "cycle"
        verbose_name = "Cycle"
        verbose_name_plural = "Cycles"
        ordering = ["-date_debut"]
        constraints = [
            models.CheckConstraint(
                condition=Q(douleur__lte=3),
                name="cycle_douleur_0_3",
                violation_error_message="La douleur va de 0 à 3.",
            ),
            models.CheckConstraint(
                condition=Q(humeur__isnull=True) | Q(humeur__range=(1, 5)),
                name="cycle_humeur_1_5",
                violation_error_message="L'humeur va de 1 à 5.",
            ),
        ]

    def __str__(self):
        return f"Cycle du {self.date_debut}"


class CycleJour(SyncModel):
    """"Mon suivi du jour": one row per day. Shared like the cycle (D16)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="cycle_jours",
    )
    date_jour = models.DateField()
    flux = models.CharField(max_length=20, blank=True)
    douleur = models.PositiveSmallIntegerField(null=True, blank=True)
    humeur = models.PositiveSmallIntegerField(null=True, blank=True)
    symptomes = models.JSONField(default=list, blank=True)

    class Meta:
        db_table = "cycle_jour"
        verbose_name = "Suivi du jour (cycle)"
        verbose_name_plural = "Suivis du jour (cycle)"
        ordering = ["-date_jour"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "date_jour"],
                condition=Q(deleted_at__isnull=True),
                name="cycle_jour_un_par_jour",
                violation_error_message="Ce jour est déjà enregistré.",
            ),
            models.CheckConstraint(
                condition=Q(douleur__isnull=True) | Q(douleur__lte=3),
                name="cycle_jour_douleur_0_3",
                violation_error_message="La douleur va de 0 à 3.",
            ),
            models.CheckConstraint(
                condition=Q(humeur__isnull=True) | Q(humeur__range=(1, 5)),
                name="cycle_jour_humeur_1_5",
                violation_error_message="L'humeur va de 1 à 5.",
            ),
        ]

    def __str__(self):
        return f"Suivi du {self.date_jour}"


class Grossesse(SyncModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="grossesses",
    )
    # The phone may know the term from the last period (ddr), an ultrasound
    # (terme_confirme_*) or a due date typed directly (dpa_saisie).
    ddr = models.DateField(null=True, blank=True)
    dpa = models.DateField(null=True, blank=True)
    dpa_saisie = models.DateField(null=True, blank=True)
    terme_confirme_date = models.DateField(null=True, blank=True)
    terme_confirme_jours = models.PositiveSmallIntegerField(null=True, blank=True)
    date_accouchement = models.DateField(null=True, blank=True)
    mode_allaitement = models.CharField(max_length=20, blank=True)
    terminee = models.BooleanField(default=False)

    class Meta:
        db_table = "grossesse"
        verbose_name = "Grossesse"
        verbose_name_plural = "Grossesses"
        ordering = ["-created_at"]

    def __str__(self):
        return f"Grossesse (DPA {self.dpa or self.dpa_saisie or '?'})"


class DangerGrossesse(SyncModel):
    grossesse = models.ForeignKey(
        Grossesse,
        on_delete=models.PROTECT,
        related_name="dangers",
    )
    type_danger_grossesse = models.ForeignKey(
        "referentiel.TypeDangerGrossesse",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="signalements",
    )
    # The phone sends the code of the clinical config, and when it happened
    # (pregnancy or after the birth).
    code = models.CharField(max_length=50, blank=True)
    periode = models.CharField(max_length=20, blank=True)
    date_signalement = models.DateTimeField()

    class Meta:
        db_table = "danger_grossesse"
        verbose_name = "Signe de danger de grossesse"
        verbose_name_plural = "Signes de danger de grossesse"
        ordering = ["-date_signalement"]

    def __str__(self):
        return f"Signe de danger du {self.date_signalement:%Y-%m-%d}"

    @property
    def libelle(self):
        if self.type_danger_grossesse_id:
            return self.type_danger_grossesse.description
        return self.code


class ContactSoin(SyncModel):
    """A pregnancy contact attended (CPN, or postnatal), by number."""

    grossesse = models.ForeignKey(
        Grossesse,
        on_delete=models.PROTECT,
        related_name="contacts",
    )
    type = models.CharField(max_length=20)
    numero = models.PositiveSmallIntegerField()
    date_faite = models.DateField()

    class Meta:
        db_table = "contact_soin"
        verbose_name = "Contact de soin"
        verbose_name_plural = "Contacts de soin"
        ordering = ["type", "numero"]
        constraints = [
            models.UniqueConstraint(
                fields=["grossesse", "type", "numero"],
                condition=Q(deleted_at__isnull=True),
                name="contact_soin_unique",
                violation_error_message="Ce contact est déjà enregistré.",
            ),
        ]

    def __str__(self):
        return f"{self.type} {self.numero}"


class SuiviGrossesse(SyncModel):
    """"Mon suivi de grossesse": dated health measurements."""

    grossesse = models.ForeignKey(
        Grossesse,
        on_delete=models.PROTECT,
        related_name="suivis",
    )
    date_jour = models.DateField()
    poids_kg = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    notes = models.TextField(blank=True)
    tension_sys = models.PositiveSmallIntegerField(null=True, blank=True)
    tension_dia = models.PositiveSmallIntegerField(null=True, blank=True)
    hauteur_uterine_cm = models.DecimalField(
        max_digits=4, decimal_places=1, null=True, blank=True
    )
    hemoglobine_g_dl = models.DecimalField(
        max_digits=4, decimal_places=1, null=True, blank=True
    )
    glycemie_g_l = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    glycemie_a_jeun = models.BooleanField(null=True, blank=True)
    temperature_c = models.DecimalField(max_digits=3, decimal_places=1, null=True, blank=True)
    # "domicile" or measured by a health professional.
    source = models.CharField(max_length=20, default="domicile")

    class Meta:
        db_table = "suivi_grossesse"
        verbose_name = "Suivi de grossesse"
        verbose_name_plural = "Suivis de grossesse"
        ordering = ["-date_jour"]

    def __str__(self):
        return f"Suivi du {self.date_jour}"


class MouvementBebe(SyncModel):
    """Number of baby movements counted on a day."""

    grossesse = models.ForeignKey(
        Grossesse,
        on_delete=models.PROTECT,
        related_name="mouvements",
    )
    date_jour = models.DateField()
    mouvements = models.PositiveSmallIntegerField()

    class Meta:
        db_table = "mouvement_bebe"
        verbose_name = "Mouvements du bébé (jour)"
        verbose_name_plural = "Mouvements du bébé (jours)"
        ordering = ["-date_jour"]
        constraints = [
            models.UniqueConstraint(
                fields=["grossesse", "date_jour"],
                condition=Q(deleted_at__isnull=True),
                name="mouvement_bebe_un_par_jour",
                violation_error_message="Ce jour est déjà enregistré.",
            ),
        ]

    def __str__(self):
        return f"{self.mouvements} mouvements le {self.date_jour}"


class MouvementEvenement(SyncModel):
    """One movement felt, with its type (kick, roll, hiccup...) and time."""

    grossesse = models.ForeignKey(
        Grossesse,
        on_delete=models.PROTECT,
        related_name="mouvements_evenements",
    )
    horodatage = models.DateTimeField()
    type = models.CharField(max_length=20)

    class Meta:
        db_table = "mouvement_evenement"
        verbose_name = "Mouvement du bébé"
        verbose_name_plural = "Mouvements du bébé"
        ordering = ["-horodatage"]

    def __str__(self):
        return f"{self.type} le {self.horodatage:%Y-%m-%d %H:%M}"


class AlimentationFemme(SyncModel):
    """The woman's dietary diversity of a day (food group codes)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="alimentations",
    )
    date_jour = models.DateField()
    groupes = models.JSONField(default=list, blank=True)

    class Meta:
        db_table = "alimentation_femme"
        verbose_name = "Alimentation de la femme"
        verbose_name_plural = "Alimentations de la femme"
        ordering = ["-date_jour"]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "date_jour"],
                condition=Q(deleted_at__isnull=True),
                name="alimentation_femme_un_par_jour",
                violation_error_message="Ce jour est déjà enregistré.",
            ),
        ]

    def __str__(self):
        return f"Alimentation du {self.date_jour}"
