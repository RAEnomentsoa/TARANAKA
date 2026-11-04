from django.conf import settings
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from rest_framework.exceptions import ValidationError

from synchro.services import LONGUEUR_DEVICE_ID, contexte_depuis

from . import donnees_personnelles, services
from .exceptions import TotpNonDisponible
from .models import CodeProfile, Profile
from .permissions import AccesParAction, IsBeneficiaire, acces
from .serializers import (
    ChangerPinReponseSerializer,
    ChangerPinSerializer,
    CompteSerializer,
    DonneesPersonnellesSerializer,
    EffacementAdminSerializer,
    EffacementReponseSerializer,
    EffacementSerializer,
    LoginReponseSerializer,
    LoginSerializer,
    LogoutSerializer,
    MessageSerializer,
    ProfileSerializer,
    ReinitialiserPinSerializer,
    TotpCodeSerializer,
    TotpDesactivationSerializer,
    TotpEtatSerializer,
    TotpPreparationSerializer,
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
            device_id=request.headers.get("X-Device-Id", "")[:LONGUEUR_DEVICE_ID],
            **serializer.validated_data,
        )
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "utilisateur": UtilisateurSerializer(user).data,
                "totp_a_configurer": bool(refresh.get("totp_a_configurer", False)),
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
    autorise_sans_totp = True

    @extend_schema(responses=UtilisateurSerializer)
    def get(self, request):
        return Response(UtilisateurSerializer(request.user).data)


class ChangerPinView(APIView):
    autorise_sans_totp = True

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
        lecture=(
            CodeProfile.BENEFICIAIRE,
            CodeProfile.ASC,
            CodeProfile.SUPERVISEUR,
            CodeProfile.ADMIN,
        ),
        ecriture=(CodeProfile.ADMIN,),
        create=(CodeProfile.ASC, CodeProfile.SUPERVISEUR, CodeProfile.ADMIN),
        reinitialiser_pin=(CodeProfile.SUPERVISEUR, CodeProfile.ADMIN),
        reinitialiser_totp=(CodeProfile.ADMIN,),
        donnees=(CodeProfile.ADMIN,),
        effacer=(CodeProfile.ADMIN,),
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

    @extend_schema(request=ReinitialiserPinSerializer, responses=MessageSerializer)
    @action(detail=True, methods=["post"], url_path="reset-pin")
    def reinitialiser_pin(self, request, pk=None):
        """PIN forgotten: a supervisor (their ASCs) or an admin sets a new one."""
        serializer = ReinitialiserPinSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.reinitialiser_pin(
            self.get_object(),
            serializer.validated_data["nouveau_pin"],
            contexte_depuis(request),
        )
        return Response({"detail": "PIN réinitialisé."})

    @extend_schema(request=None, responses=MessageSerializer)
    @action(detail=True, methods=["post"], url_path="reset-2fa")
    def reinitialiser_totp(self, request, pk=None):
        """Lost phone: an admin turns two-factor login off for this account."""
        services.reinitialiser_totp(self.get_object(), contexte_depuis(request))
        return Response({"detail": "Double authentification réinitialisée."})

    @extend_schema(responses=DonneesPersonnellesSerializer)
    @action(detail=True, methods=["get"], url_path="data")
    def donnees(self, request, pk=None):
        """Loi 2014-038, right of access, for a request made to the admin."""
        cible = self.get_object()
        donnees_personnelles.journaliser_acces(cible, contexte_depuis(request))
        return Response(donnees_personnelles.exporter(cible, request))

    @extend_schema(request=EffacementAdminSerializer, responses=EffacementReponseSerializer)
    @action(detail=True, methods=["post"], url_path="erase")
    def effacer(self, request, pk=None):
        """Loi 2014-038, right of erasure, for a request made to the admin."""
        serializer = EffacementAdminSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return _effacer(self.get_object(), request, **serializer.validated_data)


class ProfileTypeViewSet(viewsets.ReadOnlyModelViewSet):
    """/profile-types/: the profile table."""

    queryset = Profile.objects.all()
    serializer_class = ProfileSerializer


def _effacer(cible, request, inclure_enfants):
    try:
        resume = donnees_personnelles.effacer(
            cible,
            contexte_depuis(request),
            inclure_enfants=inclure_enfants,
        )
    except donnees_personnelles.EffacementImpossible as erreur:
        raise ValidationError({"detail": str(erreur)}) from erreur
    return Response({"detail": "Les données ont été effacées.", "resume": resume})


class TotpView(APIView):
    """/auth/2fa/: state of two-factor login for the logged-in user."""

    autorise_sans_totp = True

    @extend_schema(responses=TotpEtatSerializer)
    def get(self, request):
        user = request.user
        return Response(
            {
                "active": user.totp_active,
                "requise_pour_ce_profil": services.totp_requis_pour(user),
                "obligatoire": services.totp_requis_pour(user)
                and settings.TARANAKA_TOTP_OBLIGATOIRE,
                "a_configurer": services.totp_a_configurer(user),
            }
        )


class TotpPreparerView(APIView):
    """/auth/2fa/setup/: a new secret, to scan as a QR code (otpauth URI)."""

    autorise_sans_totp = True

    @extend_schema(request=None, responses=TotpPreparationSerializer)
    def post(self, request):
        secret, uri = services.preparer_totp(request.user, _adresse_ip(request))
        return Response({"secret": secret, "uri": uri})


class TotpActiverView(APIView):
    """/auth/2fa/activate/: check a first code. Returns new tokens."""

    autorise_sans_totp = True

    @extend_schema(request=TotpCodeSerializer, responses=ChangerPinReponseSerializer)
    def post(self, request):
        if not services.totp_requis_pour(request.user):
            raise TotpNonDisponible()
        serializer = TotpCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        refresh = services.activer_totp(
            request.user,
            serializer.validated_data["code"],
            _adresse_ip(request),
        )
        return Response(
            {
                "detail": "Double authentification activée.",
                "access": str(refresh.access_token),
                "refresh": str(refresh),
            }
        )


class TotpDesactiverView(APIView):
    """/auth/2fa/disable/: PIN and current code. Refused when it is mandatory."""

    @extend_schema(request=TotpDesactivationSerializer, responses=MessageSerializer)
    def post(self, request):
        serializer = TotpDesactivationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.desactiver_totp(
            request.user,
            ip=_adresse_ip(request),
            **serializer.validated_data,
        )
        return Response({"detail": "Double authentification désactivée."})


class MesDonneesView(APIView):
    """/auth/my-data/: loi 2014-038, right of access to one's own data."""

    @extend_schema(responses=DonneesPersonnellesSerializer)
    def get(self, request):
        donnees_personnelles.journaliser_acces(request.user, contexte_depuis(request))
        return Response(donnees_personnelles.exporter(request.user, request))


class EffacerMesDonneesView(APIView):
    """/auth/my-data/erase/: loi 2014-038, right of erasure (beneficiaries)."""

    permission_classes = [IsBeneficiaire]

    @extend_schema(request=EffacementSerializer, responses=EffacementReponseSerializer)
    def post(self, request):
        serializer = EffacementSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.verifier_pin_pour(
            request.user,
            serializer.validated_data["pin"],
            _adresse_ip(request),
            "effacement",
        )
        return _effacer(
            request.user,
            request,
            serializer.validated_data["inclure_enfants"],
        )
