from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import AdminUserCreationForm, UserChangeForm

from django.contrib import messages
from rest_framework.exceptions import ValidationError

from synchro.services import Contexte

from . import demandes, services
from .models import DemandeAcces, Profile, StatutDemande, User


class UtilisateurCreationForm(AdminUserCreationForm):
    class Meta:
        model = User
        fields = ("identifiant", "nom", "prenom", "profile", "csb")


class UtilisateurChangeForm(UserChangeForm):
    class Meta:
        model = User
        fields = "__all__"


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("code", "libelle")
    search_fields = ("code", "libelle")


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    form = UtilisateurChangeForm
    add_form = UtilisateurCreationForm
    fieldsets = (
        (None, {"fields": ("identifiant", "password")}),
        (
            "Informations",
            {
                "fields": (
                    "nom",
                    "prenom",
                    "email",
                    "phone",
                    "profile",
                    "region",
                    "csb",
                    "consentement",
                ),
            },
        ),
        (
            "Permissions",
            {
                "fields": (
                    "is_active",
                    "is_staff",
                    "is_superuser",
                    "groups",
                    "user_permissions",
                ),
            },
        ),
        ("Sécurité", {"fields": ("tentatives_echouees", "bloque_jusqu_a")}),
        ("Dates", {"fields": ("last_login", "date_creation", "updated_at")}),
    )
    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": (
                    "identifiant",
                    "nom",
                    "prenom",
                    "profile",
                    "csb",
                    "usable_password",
                    "password1",
                    "password2",
                ),
            },
        ),
    )
    readonly_fields = (
        "tentatives_echouees",
        "bloque_jusqu_a",
        "last_login",
        "date_creation",
        "updated_at",
    )
    list_display = (
        "identifiant",
        "nom",
        "prenom",
        "phone",
        "profile",
        "region",
        "is_active",
        "bloque",
    )
    list_filter = ("profile", "is_active", "is_staff", "consentement", "region")
    search_fields = ("identifiant", "nom", "prenom", "phone", "email")
    list_select_related = ("profile", "region")
    ordering = ("nom", "prenom")
    actions = ("debloquer",)

    @admin.display(boolean=True, description="Bloqué")
    def bloque(self, obj):
        return services.est_bloque(obj)

    @admin.action(description="Débloquer les comptes sélectionnés", permissions=["change"])
    def debloquer(self, request, queryset):
        for user in queryset:
            services.debloquer(user, request.user, request.META.get("REMOTE_ADDR"))
        self.message_user(request, f"{len(queryset)} compte(s) débloqué(s).")


@admin.register(DemandeAcces)
class DemandeAccesAdmin(admin.ModelAdmin):
    """Access requests (D15). Read-only: approve or refuse with the actions,
    so the account is created and the audit log written by the same code as
    the dashboard."""

    list_display = (
        "date_creation",
        "nom",
        "prenom",
        "identifiant",
        "phone",
        "profil_demande",
        "csb",
        "region",
        "statut",
    )
    list_filter = ("statut", "profil_demande", "region")
    search_fields = ("nom", "prenom", "identifiant", "phone", "email")
    list_select_related = ("csb", "region")
    exclude = ("pin_hash",)
    actions = ("approuver", "refuser")

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def get_readonly_fields(self, request, obj=None):
        return [f.name for f in self.model._meta.fields if f.name != "pin_hash"]

    def _contexte(self, request):
        return Contexte(user=request.user, ip=request.META.get("REMOTE_ADDR"))

    def _traiter(self, request, queryset, traitement, verbe):
        faites = 0
        for demande in queryset.filter(statut=StatutDemande.EN_ATTENTE):
            try:
                traitement(demande)
                faites += 1
            except ValidationError as erreur:
                self.message_user(
                    request, f"{demande} : {erreur.detail}", level=messages.ERROR
                )
        self.message_user(request, f"{faites} demande(s) {verbe}.")

    @admin.action(description="Approuver (créer les comptes demandés)", permissions=["view"])
    def approuver(self, request, queryset):
        contexte = self._contexte(request)
        self._traiter(
            request, queryset, lambda d: demandes.approuver(d, {}, contexte), "approuvée(s)"
        )

    @admin.action(description="Refuser", permissions=["view"])
    def refuser(self, request, queryset):
        contexte = self._contexte(request)
        self._traiter(
            request, queryset, lambda d: demandes.refuser(d, "", contexte), "refusée(s)"
        )
