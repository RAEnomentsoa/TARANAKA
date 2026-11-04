from rest_framework import serializers

from .models import CSB, Province, Region, TypeDangerGrossesse


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
        fields = ("id", "name", "region_id", "tel")


class TypeDangerGrossesseSerializer(serializers.ModelSerializer):
    class Meta:
        model = TypeDangerGrossesse
        fields = ("id", "description")
