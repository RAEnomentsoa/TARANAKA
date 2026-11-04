from django_filters import rest_framework as filters

from .models import CSB, TypeCentre


class CSBFilter(filters.FilterSet):
    region = filters.NumberFilter(field_name="region_id")
    type_centre = filters.ChoiceFilter(choices=TypeCentre.choices)

    class Meta:
        model = CSB
        fields = []
