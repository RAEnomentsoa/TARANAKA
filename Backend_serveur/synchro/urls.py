from rest_framework.routers import SimpleRouter

from .views import JournalAuditViewSet

router = SimpleRouter()
router.register("audit", JournalAuditViewSet, basename="audit")

urlpatterns = router.urls
