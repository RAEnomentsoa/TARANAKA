from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models import Q

from referentiel.models import Sexe
from synchro.models import SyncModel


class StatutPriseEnCharge(models.TextChoices):
    AUCUN = "aucun", "Aucun"
    SUIVI = "suivi", "Suivi"
    REFERE = "refere", "Référé"
    PRIS_EN_CHARGE = "pris_en_charge", "Pris en charge"
    GUERI = "gueri", "Guéri"
    ABANDON = "abandon", "Abandon"


class Enfant(SyncModel):
    nom = models.CharField(max_length=150)
    mere = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="enfants",
    )
    asc = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="enfants_suivis",
    )
    grossesse = models.ForeignKey(
        "sante_femme.Grossesse",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="enfants",
    )
    region = models.ForeignKey(
        "referentiel.Region",
        on_delete=models.PROTECT,
        related_name="enfants",
    )
    date_naissance = models.DateField()
    sexe = models.CharField(max_length=1, choices=Sexe.choices)
    statut_prise_en_charge = models.CharField(
        max_length=20,
        choices=StatutPriseEnCharge.choices,
        default=StatutPriseEnCharge.AUCUN,
    )

    class Meta:
        db_table = "enfant"
        verbose_name = "Enfant"
        verbose_name_plural = "Enfants"
        ordering = ["nom"]

    def __str__(self):
        return self.nom


class Position(models.TextChoices):
    COUCHE = "couche", "Couché"
    DEBOUT = "debout", "Debout"


class Oedemes(models.TextChoices):
    AUCUN = "aucun", "Aucun"
    UN_PLUS = "+", "+"
    DEUX_PLUS = "++", "++"
    TROIS_PLUS = "+++", "+++"


class Alerte(models.TextChoices):
    VERT = "vert", "Vert"
    ORANGE = "orange", "Orange"
    ROUGE = "rouge", "Rouge"


class Mesure(SyncModel):
    enfant = models.ForeignKey(
        Enfant,
        on_delete=models.PROTECT,
        related_name="mesures",
    )
    asc = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="mesures_realisees",
    )
    date_mesure = models.DateField()
    poids_kg = models.DecimalField(max_digits=5, decimal_places=2)
    taille_cm = models.DecimalField(max_digits=5, decimal_places=1)
    position = models.CharField(max_length=10, choices=Position.choices)
    pb_mm = models.PositiveSmallIntegerField(null=True, blank=True)
    oedemes_bilateraux = models.CharField(
        max_length=5,
        choices=Oedemes.choices,
        default=Oedemes.AUCUN,
    )
    age_jour = models.PositiveIntegerField()
    age_mois = models.PositiveSmallIntegerField()
    taille_corrigee_cm = models.DecimalField(max_digits=5, decimal_places=1)
    waz = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    haz = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    whz = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    flag_aberrant = models.BooleanField(default=False)
    alerte = models.CharField(max_length=10, choices=Alerte.choices)
    motif_alerte = models.TextField(blank=True)
    ref_oms = models.CharField(max_length=20, default="WHO2006")

    class Meta:
        db_table = "mesure"
        verbose_name = "Mesure"
        verbose_name_plural = "Mesures"
        ordering = ["-date_mesure"]
        indexes = [
            models.Index(
                fields=["enfant", "date_mesure"],
                name="mesure_enfant_date_idx",
            ),
        ]
        constraints = [
            models.CheckConstraint(
                condition=Q(pb_mm__isnull=True) | Q(age_mois__range=(6, 59)),
                name="mesure_pb_age_6_59_mois",
                violation_error_message=(
                    "Le périmètre brachial ne peut être saisi qu'entre 6 et 59 mois."
                ),
            ),
            models.CheckConstraint(
                condition=Q(poids_kg__range=(Decimal("0.3"), Decimal("40"))),
                name="mesure_poids_limites",
                violation_error_message="Le poids doit être compris entre 0,3 et 40 kg.",
            ),
            models.CheckConstraint(
                condition=Q(taille_cm__range=(Decimal("25"), Decimal("130"))),
                name="mesure_taille_limites",
                violation_error_message="La taille doit être comprise entre 25 et 130 cm.",
            ),
            models.CheckConstraint(
                condition=Q(pb_mm__isnull=True) | Q(pb_mm__range=(70, 250)),
                name="mesure_pb_limites",
                violation_error_message=(
                    "Le périmètre brachial doit être compris entre 70 et 250 mm."
                ),
            ),
        ]

    def __str__(self):
        return f"Mesure du {self.date_mesure} ({self.poids_kg} kg)"


class TypeAllaitement(models.TextChoices):
    EXCLUSIF = "exclusif", "Exclusif"
    MIXTE = "mixte", "Mixte"
    AUCUN = "aucun", "Aucun"


GROUPES_ALIMENTAIRES = (
    "g1_lait_maternel",
    "g2_cereales_tubercules",
    "g3_legumineuses_noix",
    "g4_produits_laitiers",
    "g5_viande_poisson",
    "g6_oeufs",
    "g7_fruits_legumes_vit_a",
    "g8_autres_fruits_legumes",
)


class JournalAlimentaire(SyncModel):
    enfant = models.ForeignKey(
        Enfant,
        on_delete=models.PROTECT,
        related_name="journaux_alimentaires",
    )
    date_jour = models.DateField()
    type_allaitement = models.CharField(
        max_length=10,
        choices=TypeAllaitement.choices,
    )
    g1_lait_maternel = models.BooleanField(default=False)
    g2_cereales_tubercules = models.BooleanField(default=False)
    g3_legumineuses_noix = models.BooleanField(default=False)
    g4_produits_laitiers = models.BooleanField(default=False)
    g5_viande_poisson = models.BooleanField(default=False)
    g6_oeufs = models.BooleanField(default=False)
    g7_fruits_legumes_vit_a = models.BooleanField(default=False)
    g8_autres_fruits_legumes = models.BooleanField(default=False)
    score_diversite = models.PositiveSmallIntegerField(default=0, editable=False)
    notes = models.TextField(blank=True)

    class Meta:
        db_table = "journal_alimentaire"
        verbose_name = "Journal alimentaire"
        verbose_name_plural = "Journaux alimentaires"
        ordering = ["-date_jour"]
        constraints = [
            models.UniqueConstraint(
                fields=["enfant", "date_jour"],
                condition=Q(deleted_at__isnull=True),
                name="journal_un_par_enfant_par_jour",
                violation_error_message="Un journal existe déjà pour cet enfant à cette date.",
            ),
            models.CheckConstraint(
                condition=Q(score_diversite__range=(0, 8)),
                name="journal_score_diversite_0_8",
                violation_error_message="Le score de diversité doit être compris entre 0 et 8.",
            ),
        ]

    def __str__(self):
        return f"Journal du {self.date_jour} (score {self.score_diversite})"

    def calculer_score_diversite(self):
        return sum(getattr(self, groupe) for groupe in GROUPES_ALIMENTAIRES)

    def save(self, *args, **kwargs):
        self.score_diversite = self.calculer_score_diversite()
        super().save(*args, **kwargs)


class Decision(models.TextChoices):
    CONSEIL = "conseil", "Conseil"
    REFERENCE = "reference", "Référence"
    PRISE_EN_CHARGE = "prise_en_charge", "Prise en charge"


class ConsultationNutritionnelle(SyncModel):
    enfant = models.ForeignKey(
        Enfant,
        on_delete=models.PROTECT,
        related_name="consultations",
    )
    mesure = models.ForeignKey(
        Mesure,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="consultations",
    )
    referencement = models.ForeignKey(
        "referencement.Referencement",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="consultations",
    )
    csb = models.ForeignKey(
        "referentiel.CSB",
        on_delete=models.PROTECT,
        related_name="consultations",
    )
    agent_medical = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="consultations_realisees",
    )
    date = models.DateField()
    diagnostic = models.TextField()
    decision = models.CharField(max_length=20, choices=Decision.choices)
    observations = models.TextField(blank=True)

    class Meta:
        db_table = "consultation_nutritionnelle"
        verbose_name = "Consultation nutritionnelle"
        verbose_name_plural = "Consultations nutritionnelles"
        ordering = ["-date"]

    def __str__(self):
        return f"Consultation du {self.date}"
