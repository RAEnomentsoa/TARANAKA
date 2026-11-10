import uuid

from django.contrib.auth.models import (
    AbstractBaseUser,
    BaseUserManager,
    PermissionsMixin,
)
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models.functions import Lower


MESSAGE_CSB_OBLIGATOIRE = "Le CSB est obligatoire pour un agent de CSB."
MESSAGE_IDENTIFIANT_UTILISE = "Cet identifiant est déjà utilisé."


class CodeProfile(models.TextChoices):
    """Profiles known to the API. Any other code in the table gets no access."""

    BENEFICIAIRE = "beneficiaire", "Bénéficiaire"
    ASC = "asc", "Agent de santé communautaire"
    AGENT_CSB = "agent_csb", "Agent de CSB"
    SUPERVISEUR = "superviseur", "Superviseur"
    ADMIN = "admin", "Administrateur"


# Web accounts that must use two-factor login (spec §2: "double authentification").
PROFILS_TOTP = (CodeProfile.AGENT_CSB, CodeProfile.SUPERVISEUR, CodeProfile.ADMIN)


class Profile(models.Model):
    id = models.AutoField(primary_key=True)
    code = models.CharField(max_length=30, unique=True)
    libelle = models.CharField(max_length=100)

    class Meta:
        db_table = "profile"
        verbose_name = "Profil"
        verbose_name_plural = "Profils"
        ordering = ["libelle"]

    def __str__(self):
        return self.libelle


class UserManager(BaseUserManager):
    use_in_migrations = True

    def get_queryset(self):
        return super().get_queryset().select_related("profile")

    def get_by_natural_key(self, identifiant):
        # "Rasoa" and "rasoa" are the same account (Django admin login,
        # createsuperuser), as for the API login.
        return self.get(identifiant__iexact=identifiant)

    def create_user(self, identifiant, password=None, **extra_fields):
        if not identifiant:
            raise ValueError("L'identifiant est obligatoire.")
        if "profile" not in extra_fields and "profile_id" not in extra_fields:
            raise ValueError("Le profil est obligatoire.")
        user = self.model(identifiant=identifiant, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, identifiant, password=None, **extra_fields):
        extra_fields["is_staff"] = True
        extra_fields["is_superuser"] = True
        extra_fields.setdefault(
            "profile",
            Profile.objects.get(code=CodeProfile.ADMIN),
        )
        return self.create_user(identifiant, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """The PIN goes through Django's password hashing and is stored in pin_hash."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    identifiant = models.CharField(
        max_length=50,
        unique=True,
        error_messages={"unique": MESSAGE_IDENTIFIANT_UTILISE},
    )
    # A beneficiary may give only a first name or a nickname (spec §3).
    nom = models.CharField(max_length=100, blank=True)
    prenom = models.CharField(max_length=100)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=20, blank=True)
    password = models.CharField("PIN (haché)", max_length=128, db_column="pin_hash")
    consentement = models.BooleanField(default=False)
    # Beneficiary only (D16). Short code she shows to a health worker (typed or
    # as a QR) so they can open her file.
    code_beneficiaire = models.CharField(
        max_length=8, unique=True, null=True, blank=True
    )
    # Option (a) of D16: the cycle stays on her phone unless she shares it.
    partage_cycle = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    profile = models.ForeignKey(
        Profile,
        on_delete=models.PROTECT,
        related_name="utilisateurs",
    )
    region = models.ForeignKey(
        "referentiel.Region",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="utilisateurs",
    )
    csb = models.ForeignKey(
        "referentiel.CSB",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="agents",
    )
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)
    tentatives_echouees = models.PositiveSmallIntegerField(default=0)
    bloque_jusqu_a = models.DateTimeField(null=True, blank=True)
    # Two-factor login (TOTP, RFC 6238) for web accounts, spec §2.
    totp_secret = models.CharField(max_length=64, blank=True)
    totp_active = models.BooleanField(default=False)
    totp_dernier_pas = models.BigIntegerField(null=True, blank=True)
    # Loi 2014-038: set when the person's data was erased (account anonymised).
    efface_le = models.DateTimeField(null=True, blank=True)

    objects = UserManager()

    USERNAME_FIELD = "identifiant"
    REQUIRED_FIELDS = ["nom", "prenom"]

    class Meta:
        db_table = "utilisateur"
        verbose_name = "Utilisateur"
        verbose_name_plural = "Utilisateurs"
        ordering = ["nom", "prenom"]
        constraints = [
            # Usernames ignore case: a phone keyboard often capitalises the
            # first letter, and "Rasoa" must not become a second account.
            models.UniqueConstraint(
                Lower("identifiant"),
                name="utilisateur_identifiant_insensible_casse",
                violation_error_message=MESSAGE_IDENTIFIANT_UTILISE,
            ),
        ]

    def __str__(self):
        return f"{self.prenom} {self.nom} ({self.identifiant})"

    def clean(self):
        super().clean()
        if (
            self.profile_id
            and self.profile.code == CodeProfile.AGENT_CSB
            and not self.csb_id
        ):
            raise ValidationError({"csb": MESSAGE_CSB_OBLIGATOIRE})


# Profiles a person may ask for with the public access request (D15). ASCs
# are created by their supervisor (spec §2), beneficiaries register from the
# phone (D16), and an admin is never self-declared.
PROFILS_DEMANDE_ACCES = (CodeProfile.AGENT_CSB, CodeProfile.SUPERVISEUR)


class StatutDemande(models.TextChoices):
    EN_ATTENTE = "en_attente", "En attente"
    APPROUVEE = "approuvee", "Approuvée"
    REFUSEE = "refusee", "Refusée"


class DemandeAcces(models.Model):
    """A request for a web account, made from the login page (D15).

    No account exists until an admin approves: the person can't log in and
    sees nothing. The admin checks who they are, corrects the profile, centre
    or region if needed, then approves (the account is created with the PIN
    chosen in the request) or refuses. The PIN is kept hashed, and only until
    the request is handled.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # A beneficiary may give only a first name or a nickname (spec §3).
    nom = models.CharField(max_length=100, blank=True)
    prenom = models.CharField(max_length=100)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=20)
    identifiant = models.CharField(max_length=50)
    pin_hash = models.CharField(max_length=128, blank=True)
    profil_demande = models.CharField(
        max_length=30,
        choices=[(code.value, code.label) for code in PROFILS_DEMANDE_ACCES],
    )
    region = models.ForeignKey(
        "referentiel.Region",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="demandes_acces",
    )
    csb = models.ForeignKey(
        "referentiel.CSB",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="demandes_acces",
    )
    fonction = models.CharField(max_length=150, blank=True)
    message = models.TextField(blank=True, max_length=1000)
    statut = models.CharField(
        max_length=12,
        choices=StatutDemande.choices,
        default=StatutDemande.EN_ATTENTE,
    )
    motif_refus = models.TextField(blank=True, max_length=1000)
    traitee_par = models.ForeignKey(
        User,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="demandes_traitees",
    )
    date_traitement = models.DateTimeField(null=True, blank=True)
    utilisateur = models.OneToOneField(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="demande_acces",
    )
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "demande_acces"
        verbose_name = "Demande d'accès"
        verbose_name_plural = "Demandes d'accès"
        ordering = ["-date_creation"]
        constraints = [
            # Two pending requests can't reserve the same identifiant.
            models.UniqueConstraint(
                Lower("identifiant"),
                condition=models.Q(statut="en_attente"),
                name="demande_acces_identifiant_en_attente_unique",
                violation_error_message=MESSAGE_IDENTIFIANT_UTILISE,
            ),
        ]

    def __str__(self):
        return f"{self.prenom} {self.nom} ({self.identifiant}) – {self.get_statut_display()}"


class SuiviBeneficiaire(models.Model):
    """A health worker follows a beneficiary (D16): from then on, their pulls
    carry her whole file. Created when the worker opens her file, registers
    her, or records something for her."""

    id = models.BigAutoField(primary_key=True)
    agent = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="beneficiaires_suivies",
    )
    beneficiaire = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="suivie_par",
    )
    date_creation = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "suivi_beneficiaire"
        verbose_name = "Bénéficiaire suivie"
        verbose_name_plural = "Bénéficiaires suivies"
        ordering = ["-date_creation"]
        constraints = [
            models.UniqueConstraint(
                fields=["agent", "beneficiaire"],
                name="suivi_beneficiaire_unique",
            ),
        ]

    def __str__(self):
        return f"{self.agent} suit {self.beneficiaire}"
