from rest_framework.routers import SimpleRouter

from .views import (
    CSBViewSet,
    ProvinceViewSet,
    RegionViewSet,
    TypeDangerGrossesseViewSet,
)

router = SimpleRouter()
router.register("provinces", ProvinceViewSet, basename="province")
router.register("regions", RegionViewSet, basename="region")
router.register("facilities", CSBViewSet, basename="facility")
router.register("danger-types", TypeDangerGrossesseViewSet, basename="danger-type")

urlpatterns = router.urls
