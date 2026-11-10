from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    ChangerPinView,
    DemandeAccesView,
    EffacerMesDonneesView,
    LoginView,
    LogoutView,
    MesDonneesView,
    MeView,
    OptionsDemandeAccesView,
    TotpActiverView,
    TotpDesactiverView,
    TotpPreparerView,
    TotpView,
)

urlpatterns = [
    path("login/", LoginView.as_view(), name="auth-login"),
    path("refresh/", TokenRefreshView.as_view(), name="auth-refresh"),
    path("logout/", LogoutView.as_view(), name="auth-logout"),
    path("me/", MeView.as_view(), name="auth-me"),
    path("changer-pin/", ChangerPinView.as_view(), name="auth-changer-pin"),
    path("2fa/", TotpView.as_view(), name="auth-2fa"),
    path("2fa/setup/", TotpPreparerView.as_view(), name="auth-2fa-setup"),
    path("2fa/activate/", TotpActiverView.as_view(), name="auth-2fa-activate"),
    path("2fa/disable/", TotpDesactiverView.as_view(), name="auth-2fa-disable"),
    path("my-data/", MesDonneesView.as_view(), name="auth-my-data"),
    path("access-request/", DemandeAccesView.as_view(), name="auth-access-request"),
    path(
        "access-request/options/",
        OptionsDemandeAccesView.as_view(),
        name="auth-access-request-options",
    ),
    path("my-data/erase/", EffacerMesDonneesView.as_view(), name="auth-my-data-erase"),
]
