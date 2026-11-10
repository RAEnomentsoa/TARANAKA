from rest_framework.routers import SimpleRouter

from .views import (
    AlimentationFemmeViewSet,
    ContactSoinViewSet,
    CycleJourViewSet,
    CycleViewSet,
    DangerGrossesseViewSet,
    GrossesseViewSet,
    MouvementBebeViewSet,
    MouvementEvenementViewSet,
    SuiviGrossesseViewSet,
)

router = SimpleRouter()
router.register("cycles", CycleViewSet, basename="cycle")
router.register("cycle-days", CycleJourViewSet, basename="cycle-day")
router.register("women-food-logs", AlimentationFemmeViewSet, basename="women-food-log")
router.register("pregnancies", GrossesseViewSet, basename="pregnancy")
router.register(
    r"pregnancies/(?P<grossesse_pk>[0-9a-fA-F-]{36})/dangers",
    DangerGrossesseViewSet,
    basename="pregnancy-danger",
)
router.register("care-contacts", ContactSoinViewSet, basename="care-contact")
router.register("pregnancy-checks", SuiviGrossesseViewSet, basename="pregnancy-check")
router.register("baby-movements", MouvementBebeViewSet, basename="baby-movement")
router.register(
    "baby-movement-events", MouvementEvenementViewSet, basename="baby-movement-event"
)

urlpatterns = router.urls
