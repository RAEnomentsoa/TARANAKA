from django.contrib import admin

from synchro.admin import SyncModelAdmin

from .models import Referencement


@admin.register(Referencement)
class ReferencementAdmin(SyncModelAdmin):
    list_display = (
        "code_unique",
        "origine",
        "enfant",
        "csb",
        "priorite",
        "status",
        "created_at",
        "deleted_at",
    )
    list_filter = (
        "status",
        "priorite",
        "origine",
        "csb",
        ("deleted_at", admin.EmptyFieldListFilter),
    )
    search_fields = ("code_unique", "motif", "enfant__nom", "asc__nom", "asc__identifiant")
    autocomplete_fields = ("enfant", "grossesse", "mesure", "asc")
    list_select_related = ("enfant", "csb")
