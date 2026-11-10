from rest_framework.routers import SimpleRouter

from .views import (
    ConsultationViewSet,
    EnfantViewSet,
    JournalAlimentaireViewSet,
    MesureEnfantViewSet,
    MesureViewSet,
    TeteeViewSet,
    VaccinFaitViewSet,
)

router = SimpleRouter()
router.register("children", EnfantViewSet, basename="child")
router.register(
    r"children/(?P<enfant_pk>[0-9a-fA-F-]{36})/measurements",
    MesureEnfantViewSet,
    basename="child-measurement",
)
router.register("measurements", MesureViewSet, basename="measurement")
router.register("food-logs", JournalAlimentaireViewSet, basename="food-log")
router.register("consultations", ConsultationViewSet, basename="consultation")
router.register("vaccinations", VaccinFaitViewSet, basename="vaccination")
router.register("feeds", TeteeViewSet, basename="feed")

urlpatterns = router.urls
