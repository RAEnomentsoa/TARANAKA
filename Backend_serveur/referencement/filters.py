from django_filters import rest_framework as filters

from synchro.filters import SyncFilterSet

from .models import Origine, Priorite, Referencement, Status


class ReferencementFilter(SyncFilterSet):
    status = filters.ChoiceFilter(choices=Status.choices)
    priorite = filters.ChoiceFilter(choices=Priorite.choices)
    origine = filters.ChoiceFilter(choices=Origine.choices)
    csb = filters.NumberFilter(field_name="csb_id")

    class Meta:
        model = Referencement
        fields = []
