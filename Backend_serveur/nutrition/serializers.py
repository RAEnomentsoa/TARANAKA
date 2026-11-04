from decimal import Decimal

from rest_framework import serializers

from comptes.models import CodeProfile
from comptes.services import asc_visibles, beneficiaires_visibles
from referentiel.models import Region
from sante_femme.services import grossesses_visibles
from synchro.serializers import (
    CHAMPS_SYNC,
    CHAMPS_SYNC_LECTURE,
    MESSAGE_OBLIGATOIRE,
    LienVisible,
    SyncSerializer,
)

from .models import Enfant, Mesure
from .services import enfants_visibles


class EnfantSerializer(SyncSerializer):
    mere_id = LienVisible(
        beneficiaires_visibles,
        source="mere",
        required=False,
        allow_null=True,
    )
    asc_id = LienVisible(asc_visibles, source="asc", required=False)
    grossesse_id = LienVisible(
        grossesses_visibles,
        source="grossesse",
        required=False,
        allow_null=True,
    )
    region_id = serializers.PrimaryKeyRelatedField(
        source="region",
        queryset=Region.objects.all(),
    )

    class Meta:
        model = Enfant
        fields = (
            "id",
            "nom",
            "mere_id",
            "asc_id",
            "grossesse_id",
            "region_id",
            "date_naissance",
            "sexe",
            "statut_prise_en_charge",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE

    def validate(self, attrs):
        attrs = super().validate(attrs)

        def valeur(champ):
            return attrs.get(champ, getattr(self.instance, champ, None))

        grossesse, mere = valeur("grossesse"), valeur("mere")
        if grossesse is not None and (mere is None or grossesse.user_id != mere.pk):
            raise serializers.ValidationError(
                {"grossesse_id": ["Cette grossesse n'est pas celle de la mère indiquée."]}
            )
        if self.instance is None and "asc" not in attrs:
            if self.utilisateur.profile.code != CodeProfile.ASC:
                raise serializers.ValidationError({"asc_id": [MESSAGE_OBLIGATOIRE]})
            attrs["asc"] = self.utilisateur
        return attrs


CHAMPS_CLASSIFICATION = (
    "classification",
    "orientation_centre",
    "urgence",
    "date_prochain_controle",
    "config_version",
)
MAX_SIGNES_DANGER = 20


class MesureSerializer(SyncSerializer):
    enfant_id = LienVisible(enfants_visibles, source="enfant")
    asc_id = LienVisible(asc_visibles, source="asc", required=False)
    signes_danger = serializers.ListField(
        child=serializers.CharField(max_length=50),
        required=False,
        max_length=MAX_SIGNES_DANGER,
    )

    champs_fixes = ("enfant",)

    class Meta:
        model = Mesure
        fields = (
            "id",
            "enfant_id",
            "asc_id",
            "date_mesure",
            "poids_kg",
            "taille_cm",
            "position",
            "pb_mm",
            "oedemes_bilateraux",
            "age_jour",
            "age_mois",
            "taille_corrigee_cm",
            "waz",
            "haz",
            "whz",
            "flag_aberrant",
            "alerte",
            "motif_alerte",
            "ref_oms",
            "signes_danger",
            "complications_medicales",
            "appetit",
            "difficultes_allaitement",
            "classification",
            "orientation_centre",
            "urgence",
            "date_prochain_controle",
            "config_version",
            *CHAMPS_SYNC,
        )
        read_only_fields = (
            "age_jour",
            "age_mois",
            "taille_corrigee_cm",
            *CHAMPS_CLASSIFICATION,
            *CHAMPS_SYNC_LECTURE,
        )

    def validate_poids_kg(self, valeur):
        if not Decimal("0.3") <= valeur <= Decimal("40"):
            raise serializers.ValidationError(
                "Le poids doit être compris entre 0,3 et 40 kg."
            )
        return valeur

    def validate_taille_cm(self, valeur):
        if not Decimal("25") <= valeur <= Decimal("130"):
            raise serializers.ValidationError(
                "La taille doit être comprise entre 25 et 130 cm."
            )
        return valeur

    def validate_pb_mm(self, valeur):
        if valeur is not None and not 70 <= valeur <= 250:
            raise serializers.ValidationError(
                "Le périmètre brachial doit être compris entre 70 et 250 mm."
            )
        return valeur
