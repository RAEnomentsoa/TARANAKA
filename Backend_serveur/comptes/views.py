from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from . import services
from .serializers import (
    ChangerPinSerializer,
    LoginSerializer,
    LogoutSerializer,
    UtilisateurSerializer,
)
from .throttles import LoginRateThrottle


def _adresse_ip(request):
    return request.META.get("REMOTE_ADDR")


class LoginView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [LoginRateThrottle]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user, refresh = services.connecter(
            ip=_adresse_ip(request),
            **serializer.validated_data,
        )
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "utilisateur": UtilisateurSerializer(user).data,
            }
        )


class LogoutView(APIView):
    """Only needs the refresh token: the access token may already have expired."""

    authentication_classes = []
    permission_classes = [AllowAny]

    def get_authenticate_header(self, request):
        # Without a header, DRF turns the 401 of an invalid token into a 403.
        return "Bearer"

    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.deconnecter(serializer.validated_data["refresh"])
        return Response({"detail": "Déconnexion réussie."})


class MeView(APIView):
    def get(self, request):
        return Response(UtilisateurSerializer(request.user).data)


class ChangerPinView(APIView):
    def post(self, request):
        serializer = ChangerPinSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        refresh = services.changer_pin(
            request.user,
            ip=_adresse_ip(request),
            **serializer.validated_data,
        )
        return Response(
            {
                "detail": "PIN modifié.",
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            }
        )
