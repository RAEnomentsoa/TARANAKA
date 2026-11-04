from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from comptes.models import CodeProfile, User
from comptes.services import beneficiaires_visibles
from referentiel.models import TypeDangerGrossesse
from synchro.serializers import (
    CHAMPS_SYNC,
    CHAMPS_SYNC_LECTURE,
    MESSAGE_OBLIGATOIRE,
    LienVisible,
    SyncSerializer,
)

from .models import Cycle, DangerGrossesse, Grossesse


class FemmeSerializer(serializers.ModelSerializer):
    """Only the name: this is what an agent of CSB may see of the woman."""

    class Meta:
        model = User
        fields = ("nom", "prenom")
        read_only_fields = fields


class AvecFemmeSerializer(SyncSerializer):
    """A row that belongs to a woman: she is the logged-in beneficiaire by default."""

    user_id = LienVisible(beneficiaires_visibles, source="user", required=False)

    champs_fixes = ("user",)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is None and "user" not in attrs:
            if self.utilisateur.profile.code != CodeProfile.BENEFICIAIRE:
                raise serializers.ValidationError({"user_id": [MESSAGE_OBLIGATOIRE]})
            attrs["user"] = self.utilisateur
        return attrs


class CycleSerializer(AvecFemmeSerializer):
    class Meta:
        model = Cycle
        fields = (
            "id",
            "user_id",
            "date_debut",
            "date_fin",
            "intensite",
            "symptome",
            "duree_cycle",
            "duree_regle",
            "estimation_prochain",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE


class GrossesseSerializer(AvecFemmeSerializer):
    femme = FemmeSerializer(source="user", read_only=True)

    class Meta:
        model = Grossesse
        fields = ("id", "user_id", "femme", "ddr", "dpa", *CHAMPS_SYNC)
        read_only_fields = CHAMPS_SYNC_LECTURE


@extend_schema_field(serializers.IntegerField(allow_null=True))
class CsbSouple(serializers.Field):
    """A wrong csb_id must not lose the danger sign: it counts as missing."""

    def run_validation(self, data=serializers.empty):
        try:
            return int(data)
        except (TypeError, ValueError, OverflowError):
            return None

    def to_representation(self, value):
        return value


class DangerGrossesseSerializer(SyncSerializer):
    grossesse_id = serializers.UUIDField(read_only=True)
    type_danger_grossesse_id = serializers.PrimaryKeyRelatedField(
        source="type_danger_grossesse",
        queryset=TypeDangerGrossesse.objects.all(),
    )
    date_signalement = serializers.DateTimeField(required=False)
    csb_id = CsbSouple(write_only=True, required=False)

    class Meta:
        model = DangerGrossesse
        fields = (
            "id",
            "grossesse_id",
            "type_danger_grossesse_id",
            "date_signalement",
            "csb_id",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is not None:
            attrs.pop("csb_id", None)
        return attrs


class DangerCreeSerializer(DangerGrossesseSerializer):
    """Answer to a new danger sign, with what happened to its referral."""

    referencement_id = serializers.SerializerMethodField()
    code_unique = serializers.SerializerMethodField()
    avertissement = serializers.SerializerMethodField()

    class Meta(DangerGrossesseSerializer.Meta):
        fields = (
            *DangerGrossesseSerializer.Meta.fields,
            "referencement_id",
            "code_unique",
            "avertissement",
        )

    @extend_schema_field(serializers.UUIDField(allow_null=True))
    def get_referencement_id(self, danger):
        referencement = getattr(danger, "referencement", None)
        return referencement.pk if referencement else None

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_code_unique(self, danger):
        referencement = getattr(danger, "referencement", None)
        return referencement.code_unique if referencement else None

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_avertissement(self, danger):
        return getattr(danger, "avertissement", None)
