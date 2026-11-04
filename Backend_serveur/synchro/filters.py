from django_filters import rest_framework as filters


class SyncFilterSet(filters.FilterSet):
    """updated_since keeps the rows changed at that moment or later."""

    updated_since = filters.IsoDateTimeFilter(
        field_name="updated_at",
        lookup_expr="gte",
    )
