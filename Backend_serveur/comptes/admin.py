from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import AdminUserCreationForm, UserChangeForm

from . import services
from .models import Profile, User


class UtilisateurCreationForm(AdminUserCreationForm):
    class Meta:
        model = User
        fields = ("identifiant", "nom", "prenom", "profile")


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
