from drf_spectacular.utils import extend_schema
from rest_framework import mixins, viewsets
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from synchro.services import contexte_depuis

from . import services
from .models import CodeProfile, Profile
from .permissions import AccesParAction, acces
from .serializers import (
    ChangerPinReponseSerializer,
    ChangerPinSerializer,
    CompteSerializer,
    LoginReponseSerializer,
    LoginSerializer,
    LogoutSerializer,
    MessageSerializer,
    ProfileSerializer,
    UtilisateurSerializer,
)
from .throttles import LoginRateThrottle


def _adresse_ip(request):
    return request.META.get("REMOTE_ADDR")


class LoginView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [LoginRateThrottle]

    @extend_schema(request=LoginSerializer, responses=LoginReponseSerializer)
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

    @extend_schema(request=LogoutSerializer, responses=MessageSerializer)
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.deconnecter(serializer.validated_data["refresh"])
        return Response({"detail": "Déconnexion réussie."})


class MeView(APIView):
    @extend_schema(responses=UtilisateurSerializer)
    def get(self, request):
        return Response(UtilisateurSerializer(request.user).data)


class ChangerPinView(APIView):
    @extend_schema(request=ChangerPinSerializer, responses=ChangerPinReponseSerializer)
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


class CompteViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    """/profiles/: the user accounts, which the specifications call profiles."""

    serializer_class = CompteSerializer
    permission_classes = [AccesParAction]
    profils_par_action = acces(
        lecture=(CodeProfile.BENEFICIAIRE, CodeProfile.ASC, CodeProfile.ADMIN),
        ecriture=(CodeProfile.ADMIN,),
        create=(CodeProfile.ASC, CodeProfile.ADMIN),
    )

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CompteSerializer.Meta.model.objects.none()
        return services.comptes_visibles(self.request.user).order_by(
            "-date_creation", "-id"
        )

    def perform_create(self, serializer):
        serializer.instance = services.creer_compte(
            serializer.validated_data,
            contexte_depuis(self.request),
        )

    def perform_update(self, serializer):
        serializer.instance = services.modifier_compte(
            serializer.instance,
            serializer.validated_data,
            contexte_depuis(self.request),
        )


class ProfileTypeViewSet(viewsets.ReadOnlyModelViewSet):
    """/profile-types/: the profile table."""

    queryset = Profile.objects.all()
    serializer_class = ProfileSerializer
