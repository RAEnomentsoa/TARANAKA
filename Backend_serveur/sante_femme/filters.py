from django_filters import rest_framework as filters

from synchro.filters import SyncFilterSet

from .models import (
    AlimentationFemme,
    ContactSoin,
    Cycle,
    CycleJour,
    DangerGrossesse,
    Grossesse,
    MouvementBebe,
    MouvementEvenement,
    SuiviGrossesse,
)
from .services import filtrer_dangers_sans_referencement


class CycleFilter(SyncFilterSet):
    femme = filters.UUIDFilter(field_name="user_id")

    class Meta:
        model = Cycle
        fields = []


class CycleJourFilter(SyncFilterSet):
    femme = filters.UUIDFilter(field_name="user_id")
    date_min = filters.DateFilter(field_name="date_jour", lookup_expr="gte")
    date_max = filters.DateFilter(field_name="date_jour", lookup_expr="lte")

    class Meta:
        model = CycleJour
        fields = []


class AlimentationFemmeFilter(SyncFilterSet):
    femme = filters.UUIDFilter(field_name="user_id")
    date_min = filters.DateFilter(field_name="date_jour", lookup_expr="gte")
    date_max = filters.DateFilter(field_name="date_jour", lookup_expr="lte")

    class Meta:
        model = AlimentationFemme
        fields = []


class GrossesseFilter(SyncFilterSet):
    femme = filters.UUIDFilter(field_name="user_id")
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


class DeGrossesseFilter(SyncFilterSet):
    grossesse = filters.UUIDFilter(field_name="grossesse_id")


class ContactSoinFilter(DeGrossesseFilter):
    class Meta:
        model = ContactSoin
        fields = []


class SuiviGrossesseFilter(DeGrossesseFilter):
    class Meta:
        model = SuiviGrossesse
        fields = []


class MouvementBebeFilter(DeGrossesseFilter):
    class Meta:
        model = MouvementBebe
        fields = []


class MouvementEvenementFilter(DeGrossesseFilter):
    class Meta:
        model = MouvementEvenement
        fields = []
