from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework.validators import UniqueValidator

from comptes.models import CodeProfile
from comptes.services import asc_visibles
from nutrition.services import enfants_visibles, mesures_visibles
from referentiel.models import CSB
from sante_femme.serializers import FemmeSerializer
from sante_femme.services import grossesses_visibles
from synchro.serializers import (
    CHAMPS_SYNC,
    CHAMPS_SYNC_LECTURE,
    MESSAGE_OBLIGATOIRE,
    LienVisible,
    SyncSerializer,
)

from .models import IssueSortie, Origine, Referencement, RendezVous, Status, StatutRendezVous
from .services import MESSAGE_CODE_UTILISE, en_retard, referencements_visibles, urgence

MESSAGE_LIEN_REQUIS = (
    "Un référencement enfant doit indiquer l'enfant, "
    "et un référencement grossesse doit indiquer la grossesse."
)


class ReferencementSerializer(SyncSerializer):
    code_unique = serializers.CharField(
        max_length=30,
        required=False,
        allow_blank=True,
        # Soft-deleted rows are included: their codes stay taken.
        validators=[
            UniqueValidator(
                queryset=Referencement.all_objects.all(),
                message=MESSAGE_CODE_UTILISE,
            )
        ],
    )
    enfant_id = LienVisible(
        enfants_visibles,
        source="enfant",
        required=False,
        allow_null=True,
    )
    grossesse_id = LienVisible(
        grossesses_visibles,
        source="grossesse",
        required=False,
        allow_null=True,
    )
    mesure_id = LienVisible(
        mesures_visibles,
        source="mesure",
        required=False,
        allow_null=True,
    )
    asc_id = LienVisible(asc_visibles, source="asc", required=False)
    csb_id = serializers.PrimaryKeyRelatedField(
        source="csb",
        queryset=CSB.objects.all(),
    )
    femme = FemmeSerializer(source="grossesse.user", read_only=True, allow_null=True)
    date_referencement = serializers.DateTimeField(required=False)
    urgence = serializers.SerializerMethodField()
    en_retard = serializers.SerializerMethodField()

    champs_fixes = ("code_unique", "origine", "enfant", "grossesse", "date_referencement")

    class Meta:
        model = Referencement
        fields = (
            "id",
            "code_unique",
            "origine",
            "enfant_id",
            "grossesse_id",
            "mesure_id",
            "asc_id",
            "csb_id",
            "priorite",
            "motif",
            "status",
            "urgence",
            "date_referencement",
            "date_reception",
            "date_prise_en_charge",
            "date_sortie",
            "issue_sortie",
            "en_retard",
            "femme",
            *CHAMPS_SYNC,
        )
        read_only_fields = (
            "status",
            "date_reception",
            "date_prise_en_charge",
            "date_sortie",
            "issue_sortie",
            *CHAMPS_SYNC_LECTURE,
        )

    @extend_schema_field(serializers.ChoiceField(choices=["rouge", "orange", "jaune"]))
    def get_urgence(self, referencement):
        return urgence(referencement)

    @extend_schema_field(serializers.BooleanField())
    def get_en_retard(self, referencement):
        """Not arrived after the config's delay (spec §7: 48 h, configurable)."""
        return en_retard(referencement, self.context.setdefault("_delais", {}))

    def validate(self, attrs):
        def valeur(champ):
            return attrs.get(champ, getattr(self.instance, champ, None))

        self._verifier_liens(
            valeur("origine"),
            valeur("enfant"),
            valeur("grossesse"),
            valeur("mesure"),
        )
        if self.instance is None and "asc" not in attrs:
            attrs["asc"] = self._asc_par_defaut(attrs.get("enfant"))
        return super().validate(attrs)

    def _verifier_liens(self, origine, enfant, grossesse, mesure):
        if origine == Origine.ENFANT:
            if enfant is None:
                raise serializers.ValidationError(MESSAGE_LIEN_REQUIS)
            if grossesse is not None:
                raise serializers.ValidationError(
                    {
                        "grossesse_id": [
                            "Un référencement enfant ne peut pas indiquer de grossesse."
                        ]
                    }
                )
        if origine == Origine.GROSSESSE:
            if grossesse is None:
                raise serializers.ValidationError(MESSAGE_LIEN_REQUIS)
            if enfant is not None:
                raise serializers.ValidationError(
                    {
                        "enfant_id": [
                            "Un référencement grossesse ne peut pas indiquer d'enfant."
                        ]
                    }
                )
        if mesure is not None and (enfant is None or mesure.enfant_id != enfant.pk):
            raise serializers.ValidationError(
                {"mesure_id": ["Cette mesure ne correspond pas à cet enfant."]}
            )

    def _asc_par_defaut(self, enfant):
        if self.utilisateur.profile.code == CodeProfile.ASC:
            return self.utilisateur
        if enfant is not None:
            return enfant.asc
        raise serializers.ValidationError({"asc_id": [MESSAGE_OBLIGATOIRE]})


class StatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=Status.choices)
    version = serializers.IntegerField(min_value=1)
    issue_sortie = serializers.ChoiceField(
        choices=IssueSortie.choices,
        required=False,
        allow_blank=True,
    )


class RendezVousSerializer(SyncSerializer):
    enfant_id = LienVisible(enfants_visibles, source="enfant")
    referencement_id = LienVisible(
        referencements_visibles,
        source="referencement",
        required=False,
        allow_null=True,
    )
    csb_id = serializers.PrimaryKeyRelatedField(
        source="csb",
        queryset=CSB.objects.all(),
        required=False,
        allow_null=True,
    )
    manque = serializers.SerializerMethodField()

    champs_fixes = ("enfant",)

    class Meta:
        model = RendezVous
        fields = (
            "id",
            "enfant_id",
            "referencement_id",
            "csb_id",
            "date_prevue",
            "type_rendez_vous",
            "statut",
            "motif",
            "manque",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE

    @extend_schema_field(serializers.BooleanField())
    def get_manque(self, rendez_vous):
        return (
            rendez_vous.statut == StatutRendezVous.PREVU
            and rendez_vous.date_prevue < timezone.localdate()
        )

    def validate(self, attrs):
        attrs = super().validate(attrs)

        def valeur(champ):
            return attrs.get(champ, getattr(self.instance, champ, None))

        referencement, enfant = valeur("referencement"), valeur("enfant")
        if referencement is not None and referencement.enfant_id != enfant.pk:
            raise serializers.ValidationError(
                {"referencement_id": ["Ce référencement ne concerne pas cet enfant."]}
            )
        # A centre agent always books in their own centre.
        if self.utilisateur.profile.code == CodeProfile.AGENT_CSB:
            attrs["csb"] = self.utilisateur.csb
        return attrs
