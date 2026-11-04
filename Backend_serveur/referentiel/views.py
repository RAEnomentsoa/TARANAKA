from rest_framework import viewsets

from .filters import CSBFilter
from .models import CSB, Province, Region, TypeDangerGrossesse
from .serializers import (
    CSBSerializer,
    ProvinceSerializer,
    RegionSerializer,
    TypeDangerGrossesseSerializer,
)


class ProvinceViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Province.objects.all()
    serializer_class = ProvinceSerializer


class RegionViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Region.objects.all()
    serializer_class = RegionSerializer


class CSBViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = CSB.objects.all()
    serializer_class = CSBSerializer
    filterset_class = CSBFilter


class TypeDangerGrossesseViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = TypeDangerGrossesse.objects.all()
    serializer_class = TypeDangerGrossesseSerializer
