from django.contrib import admin

from synchro.admin import SyncModelAdmin

from .models import ConsultationNutritionnelle, Enfant, JournalAlimentaire, Mesure


@admin.register(Enfant)
class EnfantAdmin(SyncModelAdmin):
    list_display = (
        "nom",
        "date_naissance",
        "sexe",
        "region",
        "asc",
        "statut_prise_en_charge",
        "deleted_at",
    )
    list_filter = (
        "sexe",
        "statut_prise_en_charge",
        "region",
        ("deleted_at", admin.EmptyFieldListFilter),
    )
    search_fields = ("nom", "mere__nom", "mere__prenom", "asc__nom", "asc__identifiant")
    autocomplete_fields = ("mere", "asc", "grossesse")
    list_select_related = ("region", "asc")


@admin.register(Mesure)
class MesureAdmin(SyncModelAdmin):
    list_display = (
        "enfant",
        "date_mesure",
        "poids_kg",
        "taille_cm",
        "pb_mm",
        "alerte",
        "flag_aberrant",
        "deleted_at",
    )
    list_filter = (
        "alerte",
        "flag_aberrant",
        "position",
        "oedemes_bilateraux",
        "date_mesure",
        ("deleted_at", admin.EmptyFieldListFilter),
    )
    search_fields = ("enfant__nom", "asc__nom", "asc__identifiant", "motif_alerte")
    autocomplete_fields = ("enfant", "asc")
    list_select_related = ("enfant",)


@admin.register(JournalAlimentaire)
class JournalAlimentaireAdmin(SyncModelAdmin):
    readonly_fields = (*SyncModelAdmin.readonly_fields, "score_diversite")
    list_display = (
        "enfant",
        "date_jour",
        "type_allaitement",
        "score_diversite",
        "deleted_at",
    )
    list_filter = (
        "type_allaitement",
        "date_jour",
        ("deleted_at", admin.EmptyFieldListFilter),
    )
    search_fields = ("enfant__nom", "notes")
    autocomplete_fields = ("enfant",)
    list_select_related = ("enfant",)


@admin.register(ConsultationNutritionnelle)
class ConsultationNutritionnelleAdmin(SyncModelAdmin):
    list_display = ("enfant", "date", "csb", "agent_medical", "decision", "deleted_at")
    list_filter = ("decision", "csb", "date", ("deleted_at", admin.EmptyFieldListFilter))
    search_fields = ("enfant__nom", "diagnostic", "observations", "agent_medical__nom")
    autocomplete_fields = ("enfant", "mesure", "referencement", "agent_medical")
    list_select_related = ("enfant", "csb", "agent_medical")
