from django.conf import settings
from django.db import models
from django.db.models import Q

from synchro.models import SyncModel


class Origine(models.TextChoices):
    ENFANT = "enfant", "Enfant"
    GROSSESSE = "grossesse", "Grossesse"


class Priorite(models.TextChoices):
    URGENTE = "urgente", "Urgente"
    HAUTE = "haute", "Haute"
    NORMALE = "normale", "Normale"


class Status(models.TextChoices):
    ENVOYE = "envoye", "Envoyé"
    RECU = "recu", "Reçu"
    VU = "vu", "Vu"
    PRIS_EN_CHARGE = "pris_en_charge", "Pris en charge"
    CLOS = "clos", "Clos"


class Referencement(SyncModel):
    code_unique = models.CharField(
        max_length=30,
        unique=True,
        error_messages={"unique": "Ce code de référencement existe déjà."},
    )
    origine = models.CharField(max_length=10, choices=Origine.choices)
    enfant = models.ForeignKey(
        "nutrition.Enfant",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="referencements",
    )
    grossesse = models.ForeignKey(
        "sante_femme.Grossesse",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="referencements",
    )
    mesure = models.ForeignKey(
        "nutrition.Mesure",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="referencements",
    )
    asc = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="referencements_emis",
    )
    csb = models.ForeignKey(
        "referentiel.CSB",
        on_delete=models.PROTECT,
        related_name="referencements",
    )
    priorite = models.CharField(max_length=10, choices=Priorite.choices)
    motif = models.TextField()
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ENVOYE,
    )

    class Meta:
        db_table = "referencement"
        verbose_name = "Référencement"
        verbose_name_plural = "Référencements"
        ordering = ["-created_at"]
        indexes = [
            models.Index(
                fields=["csb", "status"],
                name="referencement_csb_status_idx",
            ),
        ]
        constraints = [
            models.CheckConstraint(
                condition=(
                    Q(origine=Origine.ENFANT, enfant__isnull=False)
                    | Q(origine=Origine.GROSSESSE, grossesse__isnull=False)
                ),
                name="referencement_origine_lien_requis",
                violation_error_message=(
                    "Un référencement enfant doit indiquer l'enfant, "
                    "et un référencement grossesse doit indiquer la grossesse."
                ),
            ),
        ]

    def __str__(self):
        return self.code_unique
