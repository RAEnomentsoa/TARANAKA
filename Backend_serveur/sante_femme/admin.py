from django.contrib import admin

from synchro.admin import SyncModelAdmin

from .models import Cycle, DangerGrossesse, Grossesse


@admin.register(Cycle)
class CycleAdmin(SyncModelAdmin):
    list_display = ("user", "date_debut", "date_fin", "intensite", "deleted_at")
    list_filter = ("intensite", "date_debut", ("deleted_at", admin.EmptyFieldListFilter))
    search_fields = ("user__identifiant", "user__nom", "user__prenom")
    autocomplete_fields = ("user",)
    list_select_related = ("user",)


@admin.register(Grossesse)
class GrossesseAdmin(SyncModelAdmin):
    list_display = ("user", "ddr", "dpa", "deleted_at")
    list_filter = ("dpa", ("deleted_at", admin.EmptyFieldListFilter))
    search_fields = ("user__identifiant", "user__nom", "user__prenom")
    autocomplete_fields = ("user",)
    list_select_related = ("user",)


@admin.register(DangerGrossesse)
class DangerGrossesseAdmin(SyncModelAdmin):
    list_display = ("grossesse", "type_danger_grossesse", "date_signalement", "deleted_at")
    list_filter = (
        "type_danger_grossesse",
        "date_signalement",
        ("deleted_at", admin.EmptyFieldListFilter),
    )
    search_fields = (
        "grossesse__user__identifiant",
        "grossesse__user__nom",
        "type_danger_grossesse__description",
    )
    autocomplete_fields = ("grossesse",)
    list_select_related = ("grossesse", "type_danger_grossesse")
