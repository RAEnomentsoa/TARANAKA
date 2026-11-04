from rest_framework.routers import SimpleRouter

from .views import CycleViewSet, DangerGrossesseViewSet, GrossesseViewSet

router = SimpleRouter()
router.register("cycles", CycleViewSet, basename="cycle")
router.register("pregnancies", GrossesseViewSet, basename="pregnancy")
router.register(
    r"pregnancies/(?P<grossesse_pk>[0-9a-fA-F-]{36})/dangers",
    DangerGrossesseViewSet,
    basename="pregnancy-danger",
)

urlpatterns = router.urls
