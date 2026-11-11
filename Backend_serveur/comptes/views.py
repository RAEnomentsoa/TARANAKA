from django.conf import settings
from django.shortcuts import get_object_or_404
from django.db.models import Q
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError

from referentiel.models import CSB, Region
from synchro.services import LONGUEUR_DEVICE_ID, Contexte, contexte_depuis

from . import beneficiaires, demandes, donnees_personnelles, services
from .exceptions import TotpNonDisponible
from .models import CodeProfile, DemandeAcces, Profile, User
from .permissions import AccesParAction, IsBeneficiaire, acces
from .serializers import (
    BeneficiaireListeSerializer,
    DossierBeneficiaireSerializer,
    InscriptionBeneficiaireSerializer,
    InscriptionReponseSerializer,
    MePatchSerializer,
    PartageCycleReponseSerializer,
    RechercheCodeSerializer,
    ApprobationSerializer,
    DemandeAccesAdminSerializer,
    DemandeAccesSerializer,
    OptionsDemandeSerializer,
    RefusSerializer,
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
from .throttles import (
    DemandeAccesRateThrottle,
    InscriptionRateThrottle,
    LoginRateThrottle,
)


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

    @extend_schema(request=MePatchSerializer, responses=PartageCycleReponseSerializer)
    def patch(self, request):
        """Beneficiary: share her cycle or stop (D16 option a). Stopping
        deletes her cycle rows from the server."""
        if request.user.profile.code != CodeProfile.BENEFICIAIRE:
            raise PermissionDenied("Seule une bénéficiaire partage son cycle.")
        serializer = MePatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user, supprimees = services.changer_partage_cycle(
            request.user,
            serializer.validated_data["partage_cycle"],
            contexte_depuis(request),
        )
        return Response(
            {"utilisateur": UtilisateurSerializer(user).data, "lignes_supprimees": supprimees}
        )


class InscriptionBeneficiaireView(APIView):
    """POST /api/auth/register-beneficiary/: public (D16). The account is
    created at once (no admin approval) and the person is logged in."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [InscriptionRateThrottle]

    @extend_schema(
        request=InscriptionBeneficiaireSerializer,
        responses={201: InscriptionReponseSerializer},
    )
    def post(self, request):
        serializer = InscriptionBeneficiaireSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        contexte = Contexte(
            user=None,
            ip=_adresse_ip(request),
            device_id=request.headers.get("X-Device-Id", "")[:LONGUEUR_DEVICE_ID],
        )
        user, refresh = services.inscrire_beneficiaire(serializer.validated_data, contexte)
        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "utilisateur": UtilisateurSerializer(user).data,
            },
            status=201,
        )


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
        # D16: the ASC or the centre sets a new PIN for a woman in front of them.
        reinitialiser_pin=(
            CodeProfile.ASC,
            CodeProfile.AGENT_CSB,
            CodeProfile.SUPERVISEUR,
            CodeProfile.ADMIN,
        ),
        reinitialiser_totp=(CodeProfile.ADMIN,),
        donnees=(CodeProfile.ADMIN,),
        effacer=(CodeProfile.ADMIN,),
    )

    @extend_schema(
        parameters=[
            OpenApiParameter("profil", OpenApiTypes.STR, description="Code du profil (asc, agent_csb…)"),
            OpenApiParameter("region", OpenApiTypes.INT),
            OpenApiParameter("actif", OpenApiTypes.BOOL),
            OpenApiParameter("q", OpenApiTypes.STR, description="Nom, prénom, identifiant ou téléphone"),
        ]
    )
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CompteSerializer.Meta.model.objects.none()
        comptes = services.comptes_visibles(self.request.user)
        if self.action == "list":
            comptes = self.filtrer(comptes, self.request.query_params)
        return comptes.order_by("-date_creation", "-id")

    @staticmethod
    def filtrer(comptes, parametres):
        if parametres.get("profil"):
            comptes = comptes.filter(profile__code=parametres["profil"])
        if parametres.get("region", "").isdigit():
            comptes = comptes.filter(region_id=int(parametres["region"]))
        if parametres.get("actif") in ("true", "false"):
            comptes = comptes.filter(is_active=parametres["actif"] == "true")
        texte = parametres.get("q", "").strip()
        if texte:
            comptes = comptes.filter(
                Q(nom__icontains=texte)
                | Q(prenom__icontains=texte)
                | Q(identifiant__icontains=texte)
                | Q(phone__icontains=texte)
            )
        return comptes

    def perform_create(self, serializer):
        serializer.instance = services.creer_compte(
            serializer.validated_data,
            contexte_depuis(self.request),
        )

    def perform_update(self, serializer):
        donnees = serializer.validated_data
        if serializer.instance.pk == self.request.user.pk:
            # The admin would lock themselves out.
            if donnees.get("is_active") is False or (
                "profile" in donnees and donnees["profile"].code != CodeProfile.ADMIN
            ):
                raise ValidationError(
                    {"detail": "Vous ne pouvez pas désactiver votre propre compte ni retirer votre profil d'administrateur."}
                )
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


# ---------- Access requests (D15) ----------


class DemandeAccesView(APIView):
    """POST /api/auth/access-request/: public. Creates a pending request only."""

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [DemandeAccesRateThrottle]

    @extend_schema(request=DemandeAccesSerializer, responses={201: DemandeAccesSerializer})
    def post(self, request):
        serializer = DemandeAccesSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        contexte = Contexte(
            user=None,
            ip=_adresse_ip(request),
            device_id=request.headers.get("X-Device-Id", "")[:LONGUEUR_DEVICE_ID],
        )
        demande = demandes.creer_demande(serializer.validated_data, contexte)
        return Response(DemandeAccesSerializer(demande).data, status=201)


class OptionsDemandeAccesView(APIView):
    """GET /api/auth/access-request/options/: public. Regions and centres
    (names and types only) to fill the request form."""

    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(responses=OptionsDemandeSerializer)
    def get(self, request):
        return Response(
            OptionsDemandeSerializer(
                {
                    "regions": Region.objects.order_by("nom"),
                    "centres": CSB.objects.order_by("name"),
                }
            ).data
        )


class DemandeAccesViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """/access-requests/: the admin reads, approves or refuses the requests."""

    serializer_class = DemandeAccesAdminSerializer
    permission_classes = [AccesParAction]
    profils_par_action = acces(
        lecture=(CodeProfile.ADMIN,),
        ecriture=(CodeProfile.ADMIN,),
        approuver=(CodeProfile.ADMIN,),
        refuser=(CodeProfile.ADMIN,),
    )
    filterset_fields = ("statut", "profil_demande")

    def get_queryset(self):
        return DemandeAcces.objects.select_related(
            "region", "csb", "traitee_par__profile"
        ).order_by("-date_creation", "-id")

    @extend_schema(request=ApprobationSerializer, responses=DemandeAccesAdminSerializer)
    @action(detail=True, methods=["post"], url_path="approve")
    def approuver(self, request, pk=None):
        serializer = ApprobationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        demande = demandes.approuver(
            self.get_object(), serializer.validated_data, contexte_depuis(request)
        )
        return Response(DemandeAccesAdminSerializer(demande).data)

    @extend_schema(request=RefusSerializer, responses=DemandeAccesAdminSerializer)
    @action(detail=True, methods=["post"], url_path="refuse")
    def refuser(self, request, pk=None):
        serializer = RefusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        demande = demandes.refuser(
            self.get_object(), serializer.validated_data["motif"], contexte_depuis(request)
        )
        return Response(DemandeAccesAdminSerializer(demande).data)


# ---------- Beneficiaries for health workers (D16) ----------


@extend_schema(
    parameters=[
        OpenApiParameter(
            "q",
            OpenApiTypes.STR,
            description="Prénom, nom, téléphone, identifiant ou code.",
        )
    ]
)
class BeneficiaireViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """/beneficiaries/: the list of the zone, and her whole file.

    Opening a file (retrieve or lookup) makes the worker follow her: their
    next /sync/pull/ carries her data.
    """

    serializer_class = BeneficiaireListeSerializer
    permission_classes = [AccesParAction]
    profils_par_action = acces(
        lecture=(CodeProfile.ASC, CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
        par_code=(CodeProfile.ASC, CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
        ne_plus_suivre=(CodeProfile.ASC, CodeProfile.AGENT_CSB),
    )

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return User.objects.none()
        user = self.request.user
        lignes = beneficiaires.accessibles(user)
        if self.action == "list":
            lignes = beneficiaires.rechercher(lignes, self.request.query_params.get("q"))
        return beneficiaires.annoter(lignes, user).order_by("prenom", "nom", "id")

    @extend_schema(responses=DossierBeneficiaireSerializer)
    def retrieve(self, request, *args, **kwargs):
        femme = self.get_object()
        return Response(
            beneficiaires.ouvrir(
                femme, request.user, contexte_depuis(request), request, "dossier"
            )
        )

    @extend_schema(request=RechercheCodeSerializer, responses=DossierBeneficiaireSerializer)
    @action(detail=False, methods=["post"], url_path="lookup")
    def par_code(self, request):
        """The code she shows (typed or scanned), from any region."""
        serializer = RechercheCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        femme = beneficiaires.par_code(serializer.validated_data["code"])
        if femme is None:
            raise NotFound("Aucune bénéficiaire avec ce code.")
        return Response(
            beneficiaires.ouvrir(
                femme, request.user, contexte_depuis(request), request, "code"
            )
        )

    @extend_schema(request=None, responses=MessageSerializer)
    @action(detail=True, methods=["post"], url_path="unfollow")
    def ne_plus_suivre(self, request, pk=None):
        femme = get_object_or_404(
            User.objects.filter(pk__in=services.beneficiaires_suivies(request.user)),
            pk=pk,
        )
        services.ne_plus_suivre(request.user, femme, contexte_depuis(request))
        return Response({"detail": "Vous ne suivez plus cette bénéficiaire."})
