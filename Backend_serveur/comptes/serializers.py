from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied

from referentiel.models import CSB, Region

from .models import MESSAGE_CSB_OBLIGATOIRE, CodeProfile, Profile, User
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


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class LoginReponseSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()
    utilisateur = UtilisateurSerializer()


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
