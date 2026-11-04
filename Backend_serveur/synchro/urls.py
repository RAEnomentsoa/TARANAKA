from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import ConflitViewSet, JournalAuditViewSet, PullView, PushView

router = SimpleRouter()
router.register("audit", JournalAuditViewSet, basename="audit")
router.register("conflicts", ConflitViewSet, basename="conflict")

urlpatterns = [
    path("sync/push/", PushView.as_view(), name="sync-push"),
    path("sync/pull/", PullView.as_view(), name="sync-pull"),
    *router.urls,
]
