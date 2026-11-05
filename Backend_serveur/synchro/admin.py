from django.contrib import admin

from .models import HistoriqueVersion, JournalAudit


class SyncModelAdmin(admin.ModelAdmin):
    """Show soft-deleted rows, and delete softly instead of for real."""

    readonly_fields = (
        "id",
        "version",
        "created_at",
        "updated_at",
        "device_id",
        "deleted_at",
    )
    actions = ("supprimer",)

    def get_queryset(self, request):
        queryset = self.model.all_objects.get_queryset()
        ordering = self.get_ordering(request)
        if ordering:
            queryset = queryset.order_by(*ordering)
        return queryset

    def has_delete_permission(self, request, obj=None):
        return False

    def save_model(self, request, obj, form, change):
        if change:
            obj.version += 1
        super().save_model(request, obj, form, change)

    @admin.action(description="Supprimer (suppression logique)", permissions=["change"])
    def supprimer(self, request, queryset):
        for objet in queryset:
            objet.soft_delete()


class ReadOnlyAdmin(admin.ModelAdmin):
    """Logs can be read in the admin, never changed."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(JournalAudit)
class JournalAuditAdmin(ReadOnlyAdmin):
    list_display = ("date_creation", "user", "action", "table_nom", "ligne_id")
    list_filter = ("action", "table_nom", "date_creation")
    search_fields = ("ligne_id", "user__identifiant", "user__nom", "user__prenom")
    list_select_related = ("user",)


@admin.register(HistoriqueVersion)
class HistoriqueVersionAdmin(ReadOnlyAdmin):
    list_display = (
        "table_nom",
        "ligne_id",
        "version",
        "device_id",
        "conflit",
        "date_creation",
    )
    list_filter = ("conflit", "table_nom", "date_creation")
    search_fields = ("ligne_id", "device_id")
