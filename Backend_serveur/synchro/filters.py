from django_filters import rest_framework as filters

from .models import ConflitSync, JournalAudit, StatutConflit


class SyncFilterSet(filters.FilterSet):
    """updated_since keeps the rows changed at that moment or later."""

    updated_since = filters.IsoDateTimeFilter(
        field_name="updated_at",
        lookup_expr="gte",
    )


class JournalAuditFilter(filters.FilterSet):
    user = filters.UUIDFilter(field_name="user_id")
    action = filters.CharFilter()
    table = filters.CharFilter(field_name="table_nom")
    ligne_id = filters.UUIDFilter()
    depuis = filters.IsoDateTimeFilter(field_name="date_creation", lookup_expr="gte")
    jusqu_a = filters.IsoDateTimeFilter(field_name="date_creation", lookup_expr="lt")

    class Meta:
        model = JournalAudit
        fields = []


class ConflitFilter(filters.FilterSet):
    statut = filters.ChoiceFilter(choices=StatutConflit.choices)
    table = filters.CharFilter(field_name="table_nom")
    ligne_id = filters.UUIDFilter()

    class Meta:
        model = ConflitSync
        fields = []
