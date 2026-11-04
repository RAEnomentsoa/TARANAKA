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

from .models import Origine, Referencement, Status
from .services import MESSAGE_CODE_UTILISE

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

    champs_fixes = ("code_unique", "origine", "enfant", "grossesse")

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
            "femme",
            *CHAMPS_SYNC,
        )
        read_only_fields = ("status", *CHAMPS_SYNC_LECTURE)

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
