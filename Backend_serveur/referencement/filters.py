from django_filters import rest_framework as filters

from synchro.filters import SyncFilterSet

from referentiel.models import TypeCentre

from .models import (
    Origine,
    Priorite,
    Referencement,
    RendezVous,
    StatutRendezVous,
    Status,
    TypeRendezVous,
)
from .services import non_arrives, rendez_vous_manques


class ReferencementFilter(SyncFilterSet):
    status = filters.ChoiceFilter(choices=Status.choices)
    priorite = filters.ChoiceFilter(choices=Priorite.choices)
    origine = filters.ChoiceFilter(choices=Origine.choices)
    csb = filters.NumberFilter(field_name="csb_id")
    type_centre = filters.ChoiceFilter(field_name="csb__type_centre", choices=TypeCentre.choices)
    code = filters.CharFilter(field_name="code_unique", lookup_expr="iexact")
    enfant = filters.UUIDFilter(field_name="enfant_id")
    en_retard = filters.BooleanFilter(method="filtrer_en_retard")

    class Meta:
        model = Referencement
        fields = []

    def filtrer_en_retard(self, queryset, name, valeur):
        retard = non_arrives(queryset)
        return retard if valeur else queryset.exclude(pk__in=retard.values("pk"))


class RendezVousFilter(SyncFilterSet):
    statut = filters.ChoiceFilter(choices=StatutRendezVous.choices)
    type_rendez_vous = filters.ChoiceFilter(choices=TypeRendezVous.choices)
    enfant = filters.UUIDFilter(field_name="enfant_id")
    csb = filters.NumberFilter(field_name="csb_id")
    date_min = filters.DateFilter(field_name="date_prevue", lookup_expr="gte")
    date_max = filters.DateFilter(field_name="date_prevue", lookup_expr="lte")
    manque = filters.BooleanFilter(method="filtrer_manques")

    class Meta:
        model = RendezVous
        fields = []

    def filtrer_manques(self, queryset, name, valeur):
        manques = rendez_vous_manques(queryset)
        return manques if valeur else queryset.exclude(pk__in=manques.values("pk"))
