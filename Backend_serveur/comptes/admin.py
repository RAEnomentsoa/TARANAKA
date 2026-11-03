from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import AdminUserCreationForm, UserChangeForm

from .models import Profile, User


class UtilisateurCreationForm(AdminUserCreationForm):
    class Meta:
        model = User
        fields = ("identifiant", "nom", "prenom", "role")


class UtilisateurChangeForm(UserChangeForm):
    class Meta:
        model = User
        fields = "__all__"


@admin.register(Profile)
class ProfileAdmin(admin.ModelAdmin):
    list_display = ("type",)
    list_filter = ("type",)
    search_fields = ("type",)


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
                    "role",
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
                    "role",
                    "usable_password",
                    "password1",
                    "password2",
                ),
            },
        ),
    )
    readonly_fields = ("last_login", "date_creation", "updated_at")
    list_display = ("identifiant", "nom", "prenom", "phone", "role", "region", "is_active")
    list_filter = ("role", "is_active", "is_staff", "consentement", "region")
    search_fields = ("identifiant", "nom", "prenom", "phone", "email")
    list_select_related = ("region",)
    ordering = ("nom", "prenom")
