from rest_framework.routers import SimpleRouter

from .views import CompteViewSet, DemandeAccesViewSet, ProfileTypeViewSet

router = SimpleRouter()
router.register("profiles", CompteViewSet, basename="profile")
router.register("access-requests", DemandeAccesViewSet, basename="access-request")
router.register("profile-types", ProfileTypeViewSet, basename="profile-type")

urlpatterns = router.urls
