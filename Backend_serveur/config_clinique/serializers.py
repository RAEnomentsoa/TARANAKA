from rest_framework import serializers

from .models import ConfigurationClinique

CHAMPS_RESUME = (
    "version",
    "libelle",
    "statut",
    "statut_validation",
    "valide_par",
    "reference_validation",
    "date_validation",
    "publiee_le",
    "created_at",
    "updated_at",
)


class ConfigResumeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ConfigurationClinique
        fields = CHAMPS_RESUME
        read_only_fields = fields


class ConfigSerializer(serializers.ModelSerializer):
    """Create and edit a draft; publication goes through /publish/."""

    class Meta:
        model = ConfigurationClinique
        fields = (*CHAMPS_RESUME, "notes", "contenu")
        read_only_fields = ("version", "statut", "publiee_le", "created_at", "updated_at")
