from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied

from referentiel.models import CSB, Region

from .models import (
    MESSAGE_CSB_OBLIGATOIRE,
    MESSAGE_IDENTIFIANT_UTILISE,
    PROFILS_DEMANDE_ACCES,
    CodeProfile,
    DemandeAcces,
    Profile,
    StatutDemande,
    User,
)
from .permissions import PROFILS_CONTACT_AGENT
from .validators import valider_pin


class ProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Profile
        fields = ("code", "libelle")


class UtilisateurSerializer(serializers.ModelSerializer):
    profile = ProfileSerializer(read_only=True)

    class Meta:
        model = User
        fields = ("id", "nom", "prenom", "profile", "region_id", "csb_id")
        read_only_fields = fields


class CompteSerializer(serializers.ModelSerializer):
    """A user account. The PIN can be sent on create and is never returned."""

    profile = ProfileSerializer(read_only=True)
    profile_code = serializers.SlugRelatedField(
        source="profile",
        slug_field="code",
        queryset=Profile.objects.filter(code__in=CodeProfile.values),
        write_only=True,
        required=False,
    )
    region_id = serializers.PrimaryKeyRelatedField(
        source="region",
        queryset=Region.objects.all(),
        required=False,
        allow_null=True,
    )
    csb_id = serializers.PrimaryKeyRelatedField(
        source="csb",
        queryset=CSB.objects.all(),
        required=False,
        allow_null=True,
    )
    pin = serializers.CharField(
        write_only=True,
        required=False,
        trim_whitespace=False,
        validators=[valider_pin],
    )

    class Meta:
        model = User
        fields = (
            "id",
            "identifiant",
            "nom",
            "prenom",
            "email",
            "phone",
            "consentement",
            "pin",
            "profile",
            "profile_code",
            "region_id",
            "csb_id",
            "is_active",
            "date_creation",
            "updated_at",
        )
        read_only_fields = ("id", "date_creation", "updated_at")

    @property
    def utilisateur(self):
        return self.context["request"].user

    def validate_identifiant(self, valeur):
        """Unique whatever the case, and not reserved by a pending access request."""
        valeur = valeur.strip()
        comptes = User.objects.filter(identifiant__iexact=valeur)
        if self.instance is not None:
            comptes = comptes.exclude(pk=self.instance.pk)
        demandes = DemandeAcces.objects.filter(
            identifiant__iexact=valeur, statut=StatutDemande.EN_ATTENTE
        )
        if comptes.exists() or demandes.exists():
            raise serializers.ValidationError(MESSAGE_IDENTIFIANT_UTILISE)
        return valeur

    def validate_profile_code(self, profil):
        code = self.utilisateur.profile.code
        if code == CodeProfile.ASC and profil.code != CodeProfile.BENEFICIAIRE:
            raise PermissionDenied(
                "Un agent de santé communautaire ne peut créer que des bénéficiaires."
            )
        if code == CodeProfile.SUPERVISEUR and profil.code != CodeProfile.ASC:
            raise PermissionDenied(
                "Un superviseur ne peut créer que des agents de santé communautaires."
            )
        return profil

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is None:
            self._completer_creation(attrs)
        else:
            attrs.pop("pin", None)
        self._verifier_profil(attrs)
        return attrs

    def _completer_creation(self, attrs):
        if "pin" not in attrs:
            raise serializers.ValidationError({"pin": ["Ce champ est obligatoire."]})
        if self.utilisateur.profile.code == CodeProfile.ASC:
            if self.utilisateur.region_id is None:
                raise serializers.ValidationError(
                    {"region_id": ["Votre compte n'a pas de région."]}
                )
            attrs["profile"] = Profile.objects.get(code=CodeProfile.BENEFICIAIRE)
            attrs["region"] = self.utilisateur.region
            attrs.pop("is_active", None)
        elif self.utilisateur.profile.code == CodeProfile.SUPERVISEUR:
            attrs["profile"] = Profile.objects.get(code=CodeProfile.ASC)
            if self.utilisateur.region_id is not None:
                attrs["region"] = self.utilisateur.region
            attrs.pop("is_active", None)
        elif "profile" not in attrs:
            raise serializers.ValidationError(
                {"profile_code": ["Ce champ est obligatoire."]}
            )

    def _verifier_profil(self, attrs):
        def valeur(champ):
            return attrs.get(champ, getattr(self.instance, champ, None))

        code = valeur("profile").code
        if code == CodeProfile.BENEFICIAIRE and valeur("region") is None:
            raise serializers.ValidationError(
                {"region_id": ["La région est obligatoire pour une bénéficiaire."]}
            )
        if code == CodeProfile.AGENT_CSB:
            if valeur("csb") is None:
                raise serializers.ValidationError(
                    {"csb_id": [MESSAGE_CSB_OBLIGATOIRE]}
                )
        else:
            attrs["csb"] = None


class LoginSerializer(serializers.Serializer):
    identifiant = serializers.CharField(max_length=50)
    pin = serializers.CharField(max_length=128, trim_whitespace=False)
    # Only for accounts with two-factor login turned on.
    code_totp = serializers.CharField(max_length=10, required=False, allow_blank=True)


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class LoginReponseSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()
    utilisateur = UtilisateurSerializer()
    totp_a_configurer = serializers.BooleanField()


class MessageSerializer(serializers.Serializer):
    detail = serializers.CharField()


class ChangerPinReponseSerializer(MessageSerializer):
    access = serializers.CharField()
    refresh = serializers.CharField()


class ReinitialiserPinSerializer(serializers.Serializer):
    nouveau_pin = serializers.CharField(
        trim_whitespace=False,
        validators=[valider_pin],
    )


class ChangerPinSerializer(serializers.Serializer):
    ancien_pin = serializers.CharField(max_length=128, trim_whitespace=False)
    nouveau_pin = serializers.CharField(
        trim_whitespace=False,
        validators=[valider_pin],
    )


class TotpEtatSerializer(serializers.Serializer):
    active = serializers.BooleanField()
    requise_pour_ce_profil = serializers.BooleanField()
    obligatoire = serializers.BooleanField()
    a_configurer = serializers.BooleanField()


class TotpPreparationSerializer(serializers.Serializer):
    secret = serializers.CharField()
    uri = serializers.CharField()


class TotpCodeSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=10)


class TotpDesactivationSerializer(serializers.Serializer):
    pin = serializers.CharField(max_length=128, trim_whitespace=False)
    code = serializers.CharField(max_length=10)


class EffacementSerializer(serializers.Serializer):
    pin = serializers.CharField(max_length=128, trim_whitespace=False)
    inclure_enfants = serializers.BooleanField(default=False)


class EffacementAdminSerializer(serializers.Serializer):
    inclure_enfants = serializers.BooleanField(default=False)


class EffacementReponseSerializer(serializers.Serializer):
    detail = serializers.CharField()
    resume = serializers.DictField(child=serializers.IntegerField())


class DonneesPersonnellesSerializer(serializers.Serializer):
    genere_le = serializers.DateTimeField()
    compte = serializers.DictField()
    cycles = serializers.ListField(child=serializers.DictField(), required=False)
    grossesses = serializers.ListField(child=serializers.DictField(), required=False)
    signes_danger = serializers.ListField(child=serializers.DictField(), required=False)
    enfants = serializers.ListField(child=serializers.DictField(), required=False)
    mesures = serializers.ListField(child=serializers.DictField(), required=False)
    journaux_alimentaires = serializers.ListField(child=serializers.DictField(), required=False)
    referencements = serializers.ListField(child=serializers.DictField(), required=False)
    rendez_vous = serializers.ListField(child=serializers.DictField(), required=False)
    consultations = serializers.ListField(child=serializers.DictField(), required=False)
    journal = serializers.ListField(child=serializers.DictField())


class ContactAgentSerializer(serializers.ModelSerializer):
    """Name and phone of a health worker, for authorised staff only."""

    class Meta:
        model = User
        fields = ("nom", "prenom", "phone")
        read_only_fields = fields


def contact_agent(serializer, agent):
    """The agent's contact if the logged-in user may see it, else None."""
    requete = serializer.context.get("request")
    user = getattr(requete, "user", None)
    if agent is None or user is None or not user.is_authenticated:
        return None
    if user.profile.code not in PROFILS_CONTACT_AGENT:
        return None
    return ContactAgentSerializer(agent).data


# ---------- Access requests (D15) ----------

CHOIX_PROFIL_DEMANDE = [(code.value, code.label) for code in PROFILS_DEMANDE_ACCES]


class DemandeAccesSerializer(serializers.ModelSerializer):
    """Public form: what the person asks for. The PIN is never returned."""

    profil_demande = serializers.ChoiceField(choices=CHOIX_PROFIL_DEMANDE)
    region_id = serializers.PrimaryKeyRelatedField(
        source="region",
        queryset=Region.objects.all(),
        required=False,
        allow_null=True,
    )
    csb_id = serializers.PrimaryKeyRelatedField(
        source="csb",
        queryset=CSB.objects.all(),
        required=False,
        allow_null=True,
    )
    pin = serializers.CharField(
        write_only=True,
        trim_whitespace=False,
        validators=[valider_pin],
    )

    class Meta:
        model = DemandeAcces
        fields = (
            "id",
            "nom",
            "prenom",
            "email",
            "phone",
            "identifiant",
            "pin",
            "profil_demande",
            "region_id",
            "csb_id",
            "fonction",
            "message",
            "statut",
            "date_creation",
        )
        read_only_fields = ("id", "statut", "date_creation")
        # The unique identifiant is checked by comptes.demandes, against the
        # accounts too, with the same message as for an account.
        validators = []

    def validate_identifiant(self, valeur):
        return valeur.strip()

    def validate_phone(self, valeur):
        valeur = valeur.strip()
        if not valeur:
            raise serializers.ValidationError("Ce champ est obligatoire.")
        return valeur


class TraiteParSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ("id", "nom", "prenom")
        read_only_fields = fields


class DemandeAccesAdminSerializer(serializers.ModelSerializer):
    """What the admin sees to decide. Never the PIN, not even hashed."""

    region_id = serializers.IntegerField(read_only=True)
    region_nom = serializers.CharField(source="region.nom", read_only=True, default=None)
    csb_id = serializers.IntegerField(read_only=True)
    csb_nom = serializers.CharField(source="csb.name", read_only=True, default=None)
    csb_type = serializers.CharField(source="csb.type_centre", read_only=True, default=None)
    traitee_par = TraiteParSerializer(read_only=True)
    utilisateur_id = serializers.UUIDField(read_only=True)

    class Meta:
        model = DemandeAcces
        fields = (
            "id",
            "nom",
            "prenom",
            "email",
            "phone",
            "identifiant",
            "profil_demande",
            "region_id",
            "region_nom",
            "csb_id",
            "csb_nom",
            "csb_type",
            "fonction",
            "message",
            "statut",
            "motif_refus",
            "traitee_par",
            "date_traitement",
            "utilisateur_id",
            "date_creation",
        )
        read_only_fields = fields


class ApprobationSerializer(serializers.Serializer):
    """Optional corrections: by default the account gets what was asked."""

    profil_demande = serializers.ChoiceField(choices=CHOIX_PROFIL_DEMANDE, required=False)
    region_id = serializers.PrimaryKeyRelatedField(
        source="region",
        queryset=Region.objects.all(),
        required=False,
        allow_null=True,
    )
    csb_id = serializers.PrimaryKeyRelatedField(
        source="csb",
        queryset=CSB.objects.all(),
        required=False,
        allow_null=True,
    )


class RefusSerializer(serializers.Serializer):
    motif = serializers.CharField(max_length=1000, allow_blank=True, required=False, default="")


class OptionRegionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Region
        fields = ("id", "nom")
        read_only_fields = fields


class OptionCentreSerializer(serializers.ModelSerializer):
    region_id = serializers.IntegerField(read_only=True)

    class Meta:
        model = CSB
        fields = ("id", "name", "type_centre", "region_id")
        read_only_fields = fields


class OptionsDemandeSerializer(serializers.Serializer):
    regions = OptionRegionSerializer(many=True)
    centres = OptionCentreSerializer(many=True)
