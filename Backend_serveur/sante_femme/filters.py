from django_filters import rest_framework as filters

from synchro.filters import SyncFilterSet

from .models import Cycle, DangerGrossesse, Grossesse
from .services import filtrer_dangers_sans_referencement


class CycleFilter(SyncFilterSet):
    class Meta:
        model = Cycle
        fields = []


class GrossesseFilter(SyncFilterSet):
    danger_sans_referencement = filters.BooleanFilter(method="filtrer_dangers")

    class Meta:
        model = Grossesse
        fields = []

    def filtrer_dangers(self, queryset, name, valeur):
        return filtrer_dangers_sans_referencement(queryset, valeur)


class DangerGrossesseFilter(SyncFilterSet):
    class Meta:
        model = DangerGrossesse
        fields = []
