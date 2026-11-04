from rest_framework.routers import SimpleRouter

from .views import ReferencementViewSet

router = SimpleRouter()
router.register("referrals", ReferencementViewSet, basename="referral")

urlpatterns = router.urls
