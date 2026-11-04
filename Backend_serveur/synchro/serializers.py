from rest_framework import serializers

from .exceptions import MESSAGE_ID_UTILISE

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
