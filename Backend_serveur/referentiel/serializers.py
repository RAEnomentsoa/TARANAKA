from decimal import Decimal

from rest_framework import serializers

from .models import CSB, Indicateur, Province, Region, Sexe, TypeDangerGrossesse


class ProvinceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Province
        fields = ("id", "nom")


class RegionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Region
        fields = ("id", "nom", "province_id")


class CSBSerializer(serializers.ModelSerializer):
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
