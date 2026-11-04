from rest_framework.routers import SimpleRouter

from .views import ConfigurationCliniqueViewSet

router = SimpleRouter()
router.register("clinical-config", ConfigurationCliniqueViewSet, basename="clinical-config")

urlpatterns = router.urls
