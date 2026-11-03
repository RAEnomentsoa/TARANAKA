import uuid

from django.contrib.auth.models import (
    AbstractBaseUser,
    BaseUserManager,
    PermissionsMixin,
)
from django.db import models


class TypeProfile(models.TextChoices):
    FEMME = "femme", "Femme"
    MERE = "mere", "Mère"
    ASC = "asc", "Agent de santé communautaire"
    AGENT_CSB = "agent_csb", "Agent de CSB"
    ADMIN = "admin", "Administrateur"


class Profile(models.Model):
    id = models.AutoField(primary_key=True)
    type = models.CharField(max_length=20, choices=TypeProfile.choices)

    class Meta:
        db_table = "profile"
        verbose_name = "Profil"
        verbose_name_plural = "Profils"
        ordering = ["type"]

    def __str__(self):
        return self.get_type_display()


class Role(models.TextChoices):
    FEMME = "femme", "Femme"
    ASC = "asc", "Agent de santé communautaire"
    AGENT_CSB = "agent_csb", "Agent de CSB"
    ADMIN = "admin", "Administrateur"


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, identifiant, password=None, **extra_fields):
        if not identifiant:
            raise ValueError("L'identifiant est obligatoire.")
        user = self.model(identifiant=identifiant, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, identifiant, password=None, **extra_fields):
        extra_fields["is_staff"] = True
        extra_fields["is_superuser"] = True
        extra_fields.setdefault("role", Role.ADMIN)
        return self.create_user(identifiant, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """The PIN goes through Django's password hashing and is stored in pin_hash."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    identifiant = models.CharField(
        max_length=50,
        unique=True,
        error_messages={"unique": "Cet identifiant est déjà utilisé."},
    )
    nom = models.CharField(max_length=100)
    prenom = models.CharField(max_length=100)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=20, blank=True)
    role = models.CharField(max_length=20, choices=Role.choices)
    password = models.CharField("PIN (haché)", max_length=128, db_column="pin_hash")
    consentement = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    profile = models.ForeignKey(
        Profile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="utilisateurs",
    )
    region = models.ForeignKey(
        "referentiel.Region",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="utilisateurs",
    )
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    objects = UserManager()

    USERNAME_FIELD = "identifiant"
    REQUIRED_FIELDS = ["nom", "prenom"]

    class Meta:
        db_table = "utilisateur"
        verbose_name = "Utilisateur"
        verbose_name_plural = "Utilisateurs"
        ordering = ["nom", "prenom"]

    def __str__(self):
        return f"{self.prenom} {self.nom} ({self.identifiant})"
