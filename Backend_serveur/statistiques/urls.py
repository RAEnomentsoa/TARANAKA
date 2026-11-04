from django.urls import path

from .views import ExportCsvView, StatistiquesView

urlpatterns = [
    path("stats/", StatistiquesView.as_view(), name="stats"),
    path("stats/export/", ExportCsvView.as_view(), name="stats-export"),
]
