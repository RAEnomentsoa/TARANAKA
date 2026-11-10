from datetime import timedelta

from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from django.db.models import UniqueConstraint
from rest_framework.exceptions import PermissionDenied
from rest_framework.validators import UniqueTogetherValidator

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

from .models import (
    AlimentationFemme,
    ContactSoin,
    Cycle,
    CycleJour,
    DangerGrossesse,
    Grossesse,
    MouvementBebe,
    MouvementEvenement,
    SuiviGrossesse,
)
from .services import grossesses_visibles

# Naegele: the due date is 280 days after the first day of the last period.
DUREE_GROSSESSE = timedelta(days=280)
MESSAGE_PARTAGE_CYCLE = (
    "Le partage du cycle n'est pas activé : il reste sur le téléphone "
    "(PATCH /api/auth/me/ avec partage_cycle)."
)
MAX_CODES = 30
# A pregnancy needs at least one of these to be placed in time.
CHAMPS_TERME = ("ddr", "dpa", "dpa_saisie", "terme_confirme_date", "date_accouchement")


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

    def get_validators(self):
        # DRF would turn "one row per woman and day" into a validator that
        # makes user_id mandatory; the phone of the woman never sends it.
        # The rule is checked in validate(), once the woman is known.
        return [
            validateur
            for validateur in super().get_validators()
            if not isinstance(validateur, UniqueTogetherValidator)
        ]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is None and "user" not in attrs:
            if self.utilisateur.profile.code != CodeProfile.BENEFICIAIRE:
                raise serializers.ValidationError({"user_id": [MESSAGE_OBLIGATOIRE]})
            attrs["user"] = self.utilisateur
        self._verifier_unicite(attrs)
        return attrs

    def _verifier_unicite(self, attrs):
        modele = self.Meta.model
        for contrainte in modele._meta.constraints:
            if not isinstance(contrainte, UniqueConstraint) or "user" not in contrainte.fields:
                continue
            valeurs = {
                champ: attrs.get(champ, getattr(self.instance, champ, None))
                for champ in contrainte.fields
            }
            existantes = modele.objects.filter(**valeurs)
            if self.instance is not None:
                existantes = existantes.exclude(pk=self.instance.pk)
            if existantes.exists():
                raise serializers.ValidationError(
                    {"non_field_errors": [contrainte.violation_error_message]}
                )


class PartageCycleRequis(AvecFemmeSerializer):
    """D16 option (a): nothing of the cycle reaches the server unless she shares it."""

    def validate(self, attrs):
        attrs = super().validate(attrs)
        femme = attrs.get("user", getattr(self.instance, "user", None))
        # Read from the database: she may have just changed it.
        if femme is not None and not User.objects.filter(
            pk=femme.pk, partage_cycle=True
        ).exists():
            raise PermissionDenied(MESSAGE_PARTAGE_CYCLE)
        return attrs


class CycleSerializer(PartageCycleRequis):
    symptomes = serializers.ListField(
        child=serializers.CharField(max_length=50),
        required=False,
        max_length=MAX_CODES,
    )

    class Meta:
        model = Cycle
        fields = (
            "id",
            "user_id",
            "date_debut",
            "date_fin",
            "intensite",
            "douleur",
            "humeur",
            "notes",
            "symptomes",
            "irreguliere",
            "symptome",
            "duree_cycle",
            "duree_regle",
            "estimation_prochain",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE


class CycleJourSerializer(PartageCycleRequis):
    symptomes = serializers.ListField(
        child=serializers.CharField(max_length=50),
        required=False,
        max_length=MAX_CODES,
    )

    class Meta:
        model = CycleJour
        fields = (
            "id",
            "user_id",
            "date_jour",
            "flux",
            "douleur",
            "humeur",
            "symptomes",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE


class AlimentationFemmeSerializer(AvecFemmeSerializer):
    groupes = serializers.ListField(
        child=serializers.CharField(max_length=50),
        required=False,
        max_length=MAX_CODES,
    )

    class Meta:
        model = AlimentationFemme
        fields = ("id", "user_id", "date_jour", "groupes", *CHAMPS_SYNC)
        read_only_fields = CHAMPS_SYNC_LECTURE


class GrossesseSerializer(AvecFemmeSerializer):
    femme = FemmeSerializer(source="user", read_only=True)

    class Meta:
        model = Grossesse
        fields = (
            "id",
            "user_id",
            "femme",
            "ddr",
            "dpa",
            "dpa_saisie",
            "terme_confirme_date",
            "terme_confirme_jours",
            "date_accouchement",
            "mode_allaitement",
            "terminee",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE

    def validate(self, attrs):
        attrs = super().validate(attrs)
        def valeur(champ):
            return attrs.get(champ, getattr(self.instance, champ, None))

        if all(valeur(champ) is None for champ in CHAMPS_TERME):
            raise serializers.ValidationError(
                {"ddr": [
                    "Indiquez au moins une date : dernières règles, date prévue, "
                    "échographie ou accouchement."
                ]}
            )
        ddr, dpa = valeur("ddr"), valeur("dpa")
        if ddr is not None and dpa is None:
            attrs["dpa"] = ddr + DUREE_GROSSESSE
        return attrs


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
    """The phone sends the config code; the type is found from it (D16)."""

    grossesse_id = serializers.UUIDField(read_only=True)
    type_danger_grossesse_id = serializers.PrimaryKeyRelatedField(
        source="type_danger_grossesse",
        queryset=TypeDangerGrossesse.objects.all(),
        required=False,
        allow_null=True,
    )
    code = serializers.CharField(max_length=50, required=False, allow_blank=True)
    date_signalement = serializers.DateTimeField(required=False)
    csb_id = CsbSouple(write_only=True, required=False)

    class Meta:
        model = DangerGrossesse
        fields = (
            "id",
            "grossesse_id",
            "type_danger_grossesse_id",
            "code",
            "periode",
            "date_signalement",
            "csb_id",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is not None:
            attrs.pop("csb_id", None)
        type_danger = attrs.get(
            "type_danger_grossesse", getattr(self.instance, "type_danger_grossesse", None)
        )
        code = attrs.get("code", getattr(self.instance, "code", ""))
        if type_danger is None and code:
            type_danger = TypeDangerGrossesse.objects.filter(code=code).first()
            if type_danger is not None:
                attrs["type_danger_grossesse"] = type_danger
        if type_danger is None and not code:
            raise serializers.ValidationError(
                {"code": ["Indiquez le code du signe de danger."]}
            )
        if type_danger is not None and not code and type_danger.code:
            attrs["code"] = type_danger.code
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


class DeGrossesseSerializer(SyncSerializer):
    """A row of a pregnancy's follow-up, linked by grossesse_id."""

    grossesse_id = LienVisible(grossesses_visibles, source="grossesse")

    champs_fixes = ("grossesse",)


class ContactSoinSerializer(DeGrossesseSerializer):
    class Meta:
        model = ContactSoin
        fields = ("id", "grossesse_id", "type", "numero", "date_faite", *CHAMPS_SYNC)
        read_only_fields = CHAMPS_SYNC_LECTURE


class SuiviGrossesseSerializer(DeGrossesseSerializer):
    class Meta:
        model = SuiviGrossesse
        fields = (
            "id",
            "grossesse_id",
            "date_jour",
            "poids_kg",
            "tension_sys",
            "tension_dia",
            "hauteur_uterine_cm",
            "hemoglobine_g_dl",
            "glycemie_g_l",
            "glycemie_a_jeun",
            "temperature_c",
            "source",
            "notes",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE


class MouvementBebeSerializer(DeGrossesseSerializer):
    class Meta:
        model = MouvementBebe
        fields = ("id", "grossesse_id", "date_jour", "mouvements", *CHAMPS_SYNC)
        read_only_fields = CHAMPS_SYNC_LECTURE


class MouvementEvenementSerializer(DeGrossesseSerializer):
    class Meta:
        model = MouvementEvenement
        fields = ("id", "grossesse_id", "horodatage", "type", *CHAMPS_SYNC)
        read_only_fields = CHAMPS_SYNC_LECTURE
