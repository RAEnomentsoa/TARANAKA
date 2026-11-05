from django_filters import rest_framework as filters

from synchro.filters import SyncFilterSet

from .models import (
    Alerte,
    Classification,
    ConsultationNutritionnelle,
    Decision,
    Enfant,
    JournalAlimentaire,
    Mesure,
    StatutPriseEnCharge,
)


class EnfantFilter(SyncFilterSet):
    region = filters.NumberFilter(field_name="region_id")
    asc = filters.UUIDFilter(field_name="asc_id")
    statut_prise_en_charge = filters.ChoiceFilter(choices=StatutPriseEnCharge.choices)
    search = filters.CharFilter(field_name="nom", lookup_expr="icontains")

    class Meta:
        model = Enfant
        fields = []


class MesureFilter(SyncFilterSet):
    date_min = filters.DateFilter(field_name="date_mesure", lookup_expr="gte")
    date_max = filters.DateFilter(field_name="date_mesure", lookup_expr="lte")
    alerte = filters.ChoiceFilter(choices=Alerte.choices)
    classification = filters.ChoiceFilter(choices=Classification.choices)

    class Meta:
        model = Mesure
        fields = []


class JournalAlimentaireFilter(SyncFilterSet):
    enfant = filters.UUIDFilter(field_name="enfant_id")
    date_min = filters.DateFilter(field_name="date_jour", lookup_expr="gte")
    date_max = filters.DateFilter(field_name="date_jour", lookup_expr="lte")

    class Meta:
        model = JournalAlimentaire
        fields = []


class ConsultationFilter(SyncFilterSet):
    enfant = filters.UUIDFilter(field_name="enfant_id")
    decision = filters.ChoiceFilter(choices=Decision.choices)

    class Meta:
        model = ConsultationNutritionnelle
        fields = []
