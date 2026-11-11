from decimal import Decimal

from rest_framework import serializers

from .models import CSB, Indicateur, Province, Region, Sexe, TypeDangerGrossesse


class NomUniqueMixin:
    """The same name twice in one place is a typo: refused, case ignored."""

    champ_nom = "nom"
    champ_parent = None
    message_doublon = "Ce nom existe déjà."

    def validate(self, attrs):
        attrs = super().validate(attrs)
        nom = attrs.get(self.champ_nom, getattr(self.instance, self.champ_nom, ""))
        attrs[self.champ_nom] = " ".join(nom.split())
        if not attrs[self.champ_nom]:
            raise serializers.ValidationError({self.champ_nom: ["Ce champ est obligatoire."]})
        lignes = self.Meta.model.objects.filter(
            **{f"{self.champ_nom}__iexact": attrs[self.champ_nom]}
        )
        if self.champ_parent:
            parent = attrs.get(self.champ_parent, getattr(self.instance, self.champ_parent, None))
            lignes = lignes.filter(**{self.champ_parent: parent})
        if self.instance is not None:
            lignes = lignes.exclude(pk=self.instance.pk)
        if lignes.exists():
            raise serializers.ValidationError({self.champ_nom: [self.message_doublon]})
        return attrs


class ProvinceSerializer(NomUniqueMixin, serializers.ModelSerializer):
    message_doublon = "Cette province existe déjà."

    class Meta:
        model = Province
        fields = ("id", "nom")


class RegionSerializer(NomUniqueMixin, serializers.ModelSerializer):
    province_id = serializers.PrimaryKeyRelatedField(
        source="province", queryset=Province.objects.all()
    )
    champ_parent = "province"
    message_doublon = "Cette région existe déjà dans cette province."

    class Meta:
        model = Region
        fields = ("id", "nom", "province_id")


class CSBSerializer(NomUniqueMixin, serializers.ModelSerializer):
    region_id = serializers.PrimaryKeyRelatedField(source="region", queryset=Region.objects.all())
    champ_nom = "name"
    champ_parent = "region"
    message_doublon = "Ce centre existe déjà dans cette région."

    class Meta:
        model = CSB
        fields = ("id", "name", "type_centre", "region_id", "tel")


class TypeDangerGrossesseSerializer(serializers.ModelSerializer):
    class Meta:
        model = TypeDangerGrossesse
        fields = ("id", "description")


class ReferenceOmsParametresSerializer(serializers.Serializer):
    indicateur = serializers.ChoiceField(choices=Indicateur.choices)
    sexe = serializers.ChoiceField(choices=Sexe.choices)
    cle_min = serializers.DecimalField(max_digits=6, decimal_places=1, required=False)
    cle_max = serializers.DecimalField(max_digits=6, decimal_places=1, required=False)
    pas = serializers.DecimalField(
        max_digits=6,
        decimal_places=1,
        required=False,
        min_value=Decimal("0.1"),
        help_text="Garder une clé sur `pas` (par exemple 30 jours, ou 1 cm).",
    )


class PointOmsSerializer(serializers.Serializer):
    cle = serializers.DecimalField(max_digits=6, decimal_places=1)
    l = serializers.DecimalField(max_digits=8, decimal_places=4)  # noqa: E741
    m = serializers.DecimalField(max_digits=8, decimal_places=4)
    s = serializers.DecimalField(max_digits=8, decimal_places=5)
    mesure_type = serializers.CharField()
    courbes = serializers.DictField(child=serializers.FloatField())


class ReferenceOmsSerializer(serializers.Serializer):
    source = serializers.CharField()
    indicateur = serializers.CharField()
    sexe = serializers.CharField()
    unite_cle = serializers.CharField()
    unite_valeur = serializers.CharField()
    points = PointOmsSerializer(many=True)
