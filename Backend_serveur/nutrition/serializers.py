from decimal import Decimal

from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from comptes.models import CodeProfile, User
from comptes.services import asc_visibles, beneficiaires_visibles
from config_clinique.services import config_active
from referencement.services import referencements_visibles
from referentiel.models import CSB, Region
from sante_femme.services import grossesses_visibles
from synchro.serializers import (
    CHAMPS_SYNC,
    CHAMPS_SYNC_LECTURE,
    MESSAGE_OBLIGATOIRE,
    LienVisible,
    SyncSerializer,
)

from .models import (
    GROUPES_ALIMENTAIRES,
    ConsultationNutritionnelle,
    Enfant,
    JournalAlimentaire,
    Mesure,
)
from .services import enfants_visibles, mesures_visibles


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


class JournalAlimentaireSerializer(SyncSerializer):
    enfant_id = LienVisible(enfants_visibles, source="enfant")
    diversite_minimale_atteinte = serializers.SerializerMethodField()

    champs_fixes = ("enfant",)

    class Meta:
        model = JournalAlimentaire
        fields = (
            "id",
            "enfant_id",
            "date_jour",
            "type_allaitement",
            *GROUPES_ALIMENTAIRES,
            "score_diversite",
            "diversite_minimale_atteinte",
            "notes",
            *CHAMPS_SYNC,
        )
        read_only_fields = ("score_diversite", *CHAMPS_SYNC_LECTURE)

    @extend_schema_field(serializers.BooleanField(allow_null=True))
    def get_diversite_minimale_atteinte(self, journal):
        """Spec §6: at least N of the 8 groups, N from the clinical config."""
        cache = self.context.setdefault("_config", {})
        if "config" not in cache:
            cache["config"] = config_active()
        config = cache["config"]
        seuil = (
            config.contenu.get("alimentation_enfant", {}).get("diversite_minimale_groupes")
            if config
            else None
        )
        if seuil is None:
            return None
        return journal.calculer_score_diversite() >= seuil


class ConsultationSerializer(SyncSerializer):
    """A visit at the centre, written by its health worker (spec §10)."""

    enfant_id = LienVisible(enfants_visibles, source="enfant")
    mesure_id = LienVisible(
        mesures_visibles,
        source="mesure",
        required=False,
        allow_null=True,
    )
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
    )
    agent_medical_id = LienVisible(
        lambda user: User.objects.filter(profile__code=CodeProfile.AGENT_CSB),
        source="agent_medical",
        required=False,
    )

    champs_fixes = ("enfant",)

    class Meta:
        model = ConsultationNutritionnelle
        fields = (
            "id",
            "enfant_id",
            "mesure_id",
            "referencement_id",
            "csb_id",
            "agent_medical_id",
            "date",
            "diagnostic",
            "decision",
            "observations",
            *CHAMPS_SYNC,
        )
        read_only_fields = CHAMPS_SYNC_LECTURE

    def validate(self, attrs):
        attrs = super().validate(attrs)

        def valeur(champ):
            return attrs.get(champ, getattr(self.instance, champ, None))

        enfant = valeur("enfant")
        for champ, lien in (("mesure_id", valeur("mesure")), ("referencement_id", valeur("referencement"))):
            if lien is not None and lien.enfant_id != enfant.pk:
                raise serializers.ValidationError(
                    {champ: ["Cette ligne ne concerne pas cet enfant."]}
                )
        if self.utilisateur.profile.code == CodeProfile.AGENT_CSB:
            attrs["csb"] = self.utilisateur.csb
            attrs["agent_medical"] = self.utilisateur
        elif self.instance is None:
            for champ, nom in (("csb", "csb_id"), ("agent_medical", "agent_medical_id")):
                if champ not in attrs:
                    raise serializers.ValidationError({nom: [MESSAGE_OBLIGATOIRE]})
        return attrs
