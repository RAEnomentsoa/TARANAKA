import uuid

from django.conf import settings
from django.core.serializers.json import DjangoJSONEncoder
from django.db import models
from django.utils import timezone


class ActiveManager(models.Manager):
    """Hide soft-deleted rows."""

    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)


class SyncModel(models.Model):
    """Base of the tables created or changed by the phones."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    version = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)
    device_id = models.CharField(max_length=100, blank=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    objects = ActiveManager()
    all_objects = models.Manager()

    class Meta:
        abstract = True

    def soft_delete(self, device_id=None):
        """Mark the row as deleted so the deletion can reach the other phones."""
        if self.deleted_at is not None:
            return
        self.deleted_at = timezone.now()
        self.version += 1
        if device_id is not None:
            self.device_id = device_id
        self.save(update_fields=["deleted_at", "version", "device_id", "updated_at"])


class JournalImmuable(Exception):
    pass


class JournalAudit(models.Model):
    """Append-only: a line can be added, never changed or deleted."""

    id = models.BigAutoField(primary_key=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="actions_audit",
    )
    action = models.CharField(max_length=50)
    table_nom = models.CharField(max_length=100, blank=True)
    ligne_id = models.UUIDField(null=True, blank=True)
    details = models.JSONField(default=dict, blank=True)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "journal_audit"
        verbose_name = "Journal d'audit"
        verbose_name_plural = "Journaux d'audit"
        ordering = ["-date_creation"]

    def __str__(self):
        return f"{self.action} - {self.date_creation:%Y-%m-%d %H:%M}"

    def save(self, *args, **kwargs):
        if self.pk is not None or kwargs.get("force_update"):
            raise JournalImmuable("Une ligne du journal d'audit ne peut pas être modifiée.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise JournalImmuable("Une ligne du journal d'audit ne peut pas être supprimée.")


class HistoriqueVersion(models.Model):
    id = models.BigAutoField(primary_key=True)
    table_nom = models.CharField(max_length=100)
    ligne_id = models.UUIDField()
    version = models.PositiveIntegerField()
    donnees = models.JSONField(encoder=DjangoJSONEncoder)
    device_id = models.CharField(max_length=100, blank=True)
    conflit = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "historique_version"
        verbose_name = "Historique de version"
        verbose_name_plural = "Historiques de version"
        ordering = ["-date_creation"]
        constraints = [
            models.UniqueConstraint(
                fields=["table_nom", "ligne_id", "version", "device_id"],
                name="historique_version_unique",
            ),
        ]

    def __str__(self):
        return f"{self.table_nom} {self.ligne_id} v{self.version}"


class StatutOperation(models.TextChoices):
    APPLIQUE = "applique", "Appliquée"
    DEJA_APPLIQUE = "deja_applique", "Déjà appliquée"
    CONFLIT = "conflit", "Conflit"
    ERREUR = "erreur", "Erreur"
    REFUSE = "refuse", "Refusée"
    INTROUVABLE = "introuvable", "Introuvable"


class TypeOperation(models.TextChoices):
    CREATE = "create", "Création"
    UPDATE = "update", "Modification"
    DELETE = "delete", "Suppression"


class OperationSync(models.Model):
    """Answer already given to an outbox operation, by idempotency key.

    A phone that resends the same operation gets the same answer, and nothing
    is applied twice (spec §9). Only final answers are kept: an error can be
    retried once the phone or the server has fixed the cause.
    """

    id = models.BigAutoField(primary_key=True)
    cle_idempotence = models.UUIDField(unique=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="operations_sync",
    )
    device_id = models.CharField(max_length=100, blank=True)
    table_nom = models.CharField(max_length=100)
    operation = models.CharField(max_length=10, choices=TypeOperation.choices)
    ligne_id = models.UUIDField()
    statut = models.CharField(max_length=20, choices=StatutOperation.choices)
    reponse = models.JSONField(encoder=DjangoJSONEncoder)
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "operation_sync"
        verbose_name = "Opération de synchronisation"
        verbose_name_plural = "Opérations de synchronisation"
        ordering = ["-date_creation"]

    def __str__(self):
        return f"{self.operation} {self.table_nom} {self.ligne_id} ({self.statut})"


class StatutConflit(models.TextChoices):
    A_VERIFIER = "a_verifier", "À vérifier"
    RESOLU = "resolu", "Résolu"


class Resolution(models.TextChoices):
    SERVEUR = "serveur", "Garder la version du serveur"
    TELEPHONE = "telephone", "Garder la version du téléphone"
    FUSION = "fusion", "Version fusionnée"


class ConflitSync(models.Model):
    """Two versions of the same clinical record, kept until a person decides.

    Spec §9: on clinical data the server never overwrites automatically.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    table_nom = models.CharField(max_length=100)
    ligne_id = models.UUIDField()
    operation = models.CharField(max_length=10, choices=TypeOperation.choices)
    version_base = models.PositiveIntegerField(null=True, blank=True)
    version_serveur = models.PositiveIntegerField()
    donnees_telephone = models.JSONField(encoder=DjangoJSONEncoder)
    donnees_serveur = models.JSONField(encoder=DjangoJSONEncoder)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="conflits_envoyes",
    )
    device_id = models.CharField(max_length=100, blank=True)
    statut = models.CharField(
        max_length=20,
        choices=StatutConflit.choices,
        default=StatutConflit.A_VERIFIER,
    )
    resolution = models.CharField(max_length=20, choices=Resolution.choices, blank=True)
    resolu_par = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="conflits_resolus",
    )
    resolu_le = models.DateTimeField(null=True, blank=True)
    version_finale = models.PositiveIntegerField(null=True, blank=True)
    commentaire = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True, db_index=True)

    class Meta:
        db_table = "conflit_sync"
        verbose_name = "Conflit de synchronisation"
        verbose_name_plural = "Conflits de synchronisation"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["table_nom", "ligne_id"], name="conflit_sync_ligne_idx"),
            models.Index(fields=["statut", "created_at"], name="conflit_sync_statut_idx"),
        ]

    def __str__(self):
        return f"Conflit {self.table_nom} {self.ligne_id} ({self.get_statut_display()})"
