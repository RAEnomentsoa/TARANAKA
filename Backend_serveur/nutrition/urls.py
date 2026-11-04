from rest_framework.routers import SimpleRouter

from .views import EnfantViewSet, MesureEnfantViewSet, MesureViewSet

router = SimpleRouter()
router.register("children", EnfantViewSet, basename="child")
router.register(
    r"children/(?P<enfant_pk>[0-9a-fA-F-]{36})/measurements",
    MesureEnfantViewSet,
    basename="child-measurement",
)
router.register("measurements", MesureViewSet, basename="measurement")

urlpatterns = router.urls
