from django.contrib import admin

from .models import ConfigurationClinique, StatutPublication


@admin.register(ConfigurationClinique)
class ConfigurationCliniqueAdmin(admin.ModelAdmin):
    """Publishing goes through the API, so that the checks and the audit run."""

    list_display = ("version", "libelle", "statut", "statut_validation", "publiee_le")
    list_filter = ("statut", "statut_validation")
    readonly_fields = ("version", "statut", "publiee_le", "created_at", "updated_at", "cree_par")

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return obj is None or obj.statut == StatutPublication.BROUILLON
