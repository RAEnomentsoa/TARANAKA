import uuid

from django.conf import settings
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
    donnees = models.JSONField()
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
