from django_filters import rest_framework as filters

from .models import CSB


class CSBFilter(filters.FilterSet):
    region = filters.NumberFilter(field_name="region_id")

    class Meta:
        model = CSB
        fields = []
