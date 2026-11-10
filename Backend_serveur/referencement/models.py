from django.conf import settings
from django.db import models
from django.db.models import Q
from django.utils import timezone

from synchro.models import SyncModel


class Origine(models.TextChoices):
    ENFANT = "enfant", "Enfant"
    GROSSESSE = "grossesse", "Grossesse"


class Priorite(models.TextChoices):
    URGENTE = "urgente", "Urgente"
    HAUTE = "haute", "Haute"
    NORMALE = "normale", "Normale"


class Status(models.TextChoices):
    """Case lifecycle of spec §7: Référé → Reçu → Pris en charge → En suivi → Sortie."""

    ENVOYE = "envoye", "Référé"
    RECU = "recu", "Reçu"
    PRIS_EN_CHARGE = "pris_en_charge", "Pris en charge"
    EN_SUIVI = "en_suivi", "En suivi"
    SORTIE = "sortie", "Sortie"


class IssueSortie(models.TextChoices):
    GUERI = "gueri", "Guéri"
    TRANSFERE = "transfere", "Transféré"
    NON_REPONDANT = "non_repondant", "Non-répondant"
    ABANDON = "abandon", "Abandon / perdu de vue"
    DECEDE = "decede", "Décédé"


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
    # When the ASC referred the child, on the phone (it may sync days later).
    date_referencement = models.DateTimeField(default=timezone.now)
    date_reception = models.DateTimeField(null=True, blank=True)
    date_prise_en_charge = models.DateTimeField(null=True, blank=True)
    date_suivi = models.DateTimeField(null=True, blank=True)
    date_sortie = models.DateTimeField(null=True, blank=True)
    issue_sortie = models.CharField(
        max_length=20,
        choices=IssueSortie.choices,
        blank=True,
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
            models.CheckConstraint(
                condition=Q(status="sortie", date_sortie__isnull=False)
                | (~Q(status="sortie") & Q(issue_sortie="")),
                name="referencement_sortie_coherente",
                violation_error_message="Une sortie doit avoir une date et une issue.",
            ),
        ]

    def __str__(self):
        return self.code_unique


class TypeRendezVous(models.TextChoices):
    CONTROLE = "controle", "Contrôle"
    DEPISTAGE = "depistage", "Dépistage"


class StatutRendezVous(models.TextChoices):
    PREVU = "prevu", "Prévu"
    HONORE = "honore", "Honoré"
    ANNULE = "annule", "Annulé"


class RendezVous(SyncModel):
    """A follow-up visit (spec §7, §10). It is « manqué » when still prévu
    after its date: that is computed, not stored."""

    enfant = models.ForeignKey(
        "nutrition.Enfant",
        on_delete=models.PROTECT,
        related_name="rendez_vous",
    )
    referencement = models.ForeignKey(
        Referencement,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="rendez_vous",
    )
    csb = models.ForeignKey(
        "referentiel.CSB",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="rendez_vous",
    )
    date_prevue = models.DateField()
    type_rendez_vous = models.CharField(
        max_length=10,
        choices=TypeRendezVous.choices,
        default=TypeRendezVous.CONTROLE,
    )
    statut = models.CharField(
        max_length=10,
        choices=StatutRendezVous.choices,
        default=StatutRendezVous.PREVU,
    )
    motif = models.TextField(blank=True)

    class Meta:
        db_table = "rendez_vous"
        verbose_name = "Rendez-vous"
        verbose_name_plural = "Rendez-vous"
        ordering = ["date_prevue"]
        indexes = [
            models.Index(fields=["statut", "date_prevue"], name="rendez_vous_statut_date_idx"),
        ]

    def __str__(self):
        return f"Rendez-vous du {self.date_prevue}"
