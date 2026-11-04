from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import ReferencementViewSet, RelancesView, RendezVousViewSet

router = SimpleRouter()
router.register("referrals", ReferencementViewSet, basename="referral")
router.register("appointments", RendezVousViewSet, basename="appointment")

urlpatterns = [
    path("follow-ups/", RelancesView.as_view(), name="follow-ups"),
    *router.urls,
]
