from rest_framework import serializers

from .models import Profile, User
from .validators import valider_pin


class ProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = Profile
        fields = ("code", "libelle")


class UtilisateurSerializer(serializers.ModelSerializer):
    profile = ProfileSerializer(read_only=True)

    class Meta:
        model = User
        fields = ("id", "nom", "prenom", "profile", "region_id")
        read_only_fields = fields


class LoginSerializer(serializers.Serializer):
    identifiant = serializers.CharField(max_length=50)
    pin = serializers.CharField(max_length=128, trim_whitespace=False)


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class ChangerPinSerializer(serializers.Serializer):
    ancien_pin = serializers.CharField(max_length=128, trim_whitespace=False)
    nouveau_pin = serializers.CharField(
        trim_whitespace=False,
        validators=[valider_pin],
    )
