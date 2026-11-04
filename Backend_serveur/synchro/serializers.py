from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from comptes.serializers import ContactAgentSerializer, contact_agent

from .exceptions import MESSAGE_ID_UTILISE
from .models import (
    ConflitSync,
    JournalAudit,
    Resolution,
    StatutOperation,
    TypeOperation,
)
from .registre import NOMS_TABLES

CHAMPS_SYNC = ("version", "created_at", "updated_at", "device_id", "deleted_at")
CHAMPS_SYNC_LECTURE = ("created_at", "updated_at", "device_id", "deleted_at")
MESSAGE_OBLIGATOIRE = "Ce champ est obligatoire."


class LienVisible(serializers.PrimaryKeyRelatedField):
    """Link limited to the rows the user may see.

    A row outside that scope gets the same error as a row that doesn't exist.
    """

    def __init__(self, visibles, **kwargs):
        self.visibles = visibles
        super().__init__(**kwargs)

    def get_queryset(self):
        return self.visibles(self.context["request"].user)

    def to_internal_value(self, data):
        # The current value stays valid, even if it has left the user's scope
        # since then (for example a mother who moved to another region).
        instance = self.parent.instance
        if instance is not None:
            actuel = getattr(instance, self.source, None)
            if actuel is not None and str(actuel.pk) == str(data):
                return actuel
        return super().to_internal_value(data)


class SyncSerializer(serializers.ModelSerializer):
    """Rules shared by the synced tables, also meant for the future /sync."""

    id = serializers.UUIDField(required=False)
    version = serializers.IntegerField(required=False, min_value=1)

    # Fields (by model name) that can't change after the row is created.
    champs_fixes = ()

    @property
    def utilisateur(self):
        return self.context["request"].user

    def validate_id(self, valeur):
        modele = self.Meta.model
        if self.instance is None and modele.all_objects.filter(pk=valeur).exists():
            raise serializers.ValidationError(MESSAGE_ID_UTILISE)
        return valeur

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is None:
            attrs.pop("version", None)
            return attrs
        if "version" not in attrs:
            raise serializers.ValidationError({"version": [MESSAGE_OBLIGATOIRE]})
        attrs.pop("id", None)
        for champ in self.champs_fixes:
            if champ in attrs and attrs[champ] != getattr(self.instance, champ):
                nom = next(n for n, f in self.fields.items() if f.source == champ)
                raise serializers.ValidationError(
                    {nom: ["Ce champ ne peut pas être modifié."]}
                )
            attrs.pop(champ, None)
        return attrs


class JournalAuditSerializer(serializers.ModelSerializer):
    user_id = serializers.UUIDField(read_only=True, allow_null=True)

    class Meta:
        model = JournalAudit
        fields = ("id", "user_id", "action", "table_nom", "ligne_id", "details", "date_creation")
        read_only_fields = fields


MAX_OPERATIONS = 100


class OperationSerializer(serializers.Serializer):
    """One entry of the phone's outbox."""

    cle_idempotence = serializers.UUIDField()
    table = serializers.ChoiceField(choices=NOMS_TABLES)
    operation = serializers.ChoiceField(choices=TypeOperation.choices)
    id = serializers.UUIDField()
    version = serializers.IntegerField(min_value=1, required=False)
    donnees = serializers.DictField(required=False, default=dict)

    def validate(self, attrs):
        if attrs["operation"] == TypeOperation.UPDATE and "version" not in attrs:
            raise serializers.ValidationError({"version": [MESSAGE_OBLIGATOIRE]})
        return attrs


class PushSerializer(serializers.Serializer):
    operations = serializers.ListField(
        child=serializers.JSONField(),
        min_length=1,
        max_length=MAX_OPERATIONS,
    )


class ResultatOperationSerializer(serializers.Serializer):
    cle_idempotence = serializers.UUIDField(allow_null=True)
    table = serializers.CharField(allow_null=True)
    operation = serializers.CharField(allow_null=True)
    id = serializers.UUIDField(allow_null=True)
    statut = serializers.ChoiceField(choices=StatutOperation.choices)
    ligne = serializers.DictField(allow_null=True)
    conflit_id = serializers.UUIDField(allow_null=True)
    erreurs = serializers.JSONField(allow_null=True)
    rejoue = serializers.BooleanField()


class PushReponseSerializer(serializers.Serializer):
    horodatage_serveur = serializers.DateTimeField()
    resultats = ResultatOperationSerializer(many=True)


class PullParametresSerializer(serializers.Serializer):
    depuis = serializers.DateTimeField(required=False)
    tables = serializers.CharField(required=False)
    limite = serializers.IntegerField(required=False, min_value=1, max_value=1000, default=500)
    config_version = serializers.IntegerField(required=False, min_value=0)
    apres_id = serializers.UUIDField(required=False)

    def validate(self, attrs):
        if "apres_id" in attrs and "depuis" not in attrs:
            raise serializers.ValidationError({"apres_id": ["À utiliser avec depuis."]})
        return attrs

    def validate_tables(self, valeur):
        noms = {nom.strip() for nom in valeur.split(",") if nom.strip()}
        inconnues = noms - set(NOMS_TABLES)
        if inconnues:
            raise serializers.ValidationError(f"Tables inconnues : {', '.join(sorted(inconnues))}")
        return noms


class TablePullSerializer(serializers.Serializer):
    lignes = serializers.ListField(child=serializers.DictField())
    suite = serializers.BooleanField()
    prochain_depuis = serializers.DateTimeField()
    apres_id = serializers.UUIDField(allow_null=True)


class ConflitResumeSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    table_nom = serializers.CharField()
    ligne_id = serializers.UUIDField()
    statut = serializers.CharField()
    resolution = serializers.CharField()
    version_finale = serializers.IntegerField(allow_null=True)
    resolu_le = serializers.DateTimeField(allow_null=True)


class PullReponseSerializer(serializers.Serializer):
    horodatage_serveur = serializers.DateTimeField()
    tables = serializers.DictField(child=TablePullSerializer())
    conflits = ConflitResumeSerializer(many=True)
    config_clinique = serializers.DictField()


class ConflitSerializer(serializers.ModelSerializer):
    user_id = serializers.UUIDField(read_only=True)
    expediteur = serializers.SerializerMethodField()
    resolu_par_id = serializers.UUIDField(read_only=True, allow_null=True)
    # Objects: the row's fields. For a deletion, donnees_telephone is {}.
    donnees_telephone = serializers.DictField(read_only=True)
    donnees_serveur = serializers.DictField(read_only=True)

    @extend_schema_field(ContactAgentSerializer(allow_null=True))
    def get_expediteur(self, conflit):
        """Who sent the phone's version. Staff only (ASC, centre, admin)."""
        return contact_agent(self, conflit.user)

    class Meta:
        model = ConflitSync
        fields = (
            "id",
            "table_nom",
            "ligne_id",
            "operation",
            "version_base",
            "version_serveur",
            "donnees_telephone",
            "donnees_serveur",
            "user_id",
            "expediteur",
            "device_id",
            "statut",
            "resolution",
            "resolu_par_id",
            "resolu_le",
            "version_finale",
            "commentaire",
            "created_at",
            "updated_at",
        )
        read_only_fields = fields


class ResolutionSerializer(serializers.Serializer):
    choix = serializers.ChoiceField(choices=Resolution.choices)
    donnees = serializers.DictField(required=False)
    commentaire = serializers.CharField(required=False, allow_blank=True, default="")
