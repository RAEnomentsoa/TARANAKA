from rest_framework.routers import SimpleRouter

from .views import CompteViewSet, ProfileTypeViewSet

router = SimpleRouter()
router.register("profiles", CompteViewSet, basename="profile")
router.register("profile-types", ProfileTypeViewSet, basename="profile-type")

urlpatterns = router.urls
