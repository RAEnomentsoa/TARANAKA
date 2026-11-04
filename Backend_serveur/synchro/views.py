import uuid
from collections.abc import Mapping

from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.models import CodeProfile
from comptes.permissions import AccesParAction, IsAdmin, ProfilReconnu, acces

from . import services, sync
from .exceptions import ConflitVersion
from .filters import ConflitFilter, JournalAuditFilter
from .models import ConflitSync, JournalAudit, StatutOperation
from .serializers import (
    ConflitSerializer,
    JournalAuditSerializer,
    OperationSerializer,
    PullParametresSerializer,
    PullReponseSerializer,
    PushReponseSerializer,
    PushSerializer,
    ResolutionSerializer,
)


class SyncViewSet(viewsets.ModelViewSet):
    """Common behaviour of the synced tables. Subclasses provide visibles()."""

    permission_classes = [AccesParAction]
    profils_par_action = {}

    def visibles(self):
        raise NotImplementedError

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return self.serializer_class.Meta.model.objects.none()
        return self.visibles().order_by("-created_at", "-id")

    def contexte(self):
        return services.contexte_depuis(self.request)

    def serialiser(self, ligne):
        return self.serializer_class(ligne, context=self.get_serializer_context()).data

    def create(self, request, *args, **kwargs):
        # A phone resends its create if the response got lost: answer with the
        # row, so nothing is created twice. A row the user can't see gets a 400.
        existante = self._ligne_deja_recue(request.data)
        if existante is not None:
            return Response(self.serialiser(existante))
        return super().create(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.instance = services.creer_ligne(
            self.serializer_class.Meta.model,
            serializer.validated_data,
            self.contexte(),
        )

    def perform_update(self, serializer):
        serializer.instance = services.modifier_ligne(
            serializer.instance,
            serializer.validated_data,
            self.contexte(),
        )

    def perform_destroy(self, instance):
        services.supprimer_ligne(instance, self.contexte())

    def handle_exception(self, exc):
        if isinstance(exc, ConflitVersion):
            return Response(
                {
                    "detail": exc.detail,
                    "code": exc.default_code,
                    "current": self.serialiser(exc.ligne),
                },
                status=status.HTTP_409_CONFLICT,
            )
        return super().handle_exception(exc)

    def _ligne_deja_recue(self, donnees):
        if not isinstance(donnees, Mapping):
            return None
        try:
            identifiant = uuid.UUID(str(donnees.get("id")))
        except ValueError:
            return None
        return self.get_queryset().filter(pk=identifiant).first()


class JournalAuditViewSet(viewsets.ReadOnlyModelViewSet):
    """/audit/: read-only audit log, for admins (spec §2: who, what, when, device)."""

    permission_classes = [IsAdmin]
    serializer_class = JournalAuditSerializer
    filterset_class = JournalAuditFilter

    def get_queryset(self):
        return JournalAudit.objects.order_by("-date_creation", "-id")


class PushView(APIView):
    """POST /sync/push/: apply the phone's outbox (spec §9)."""

    permission_classes = [ProfilReconnu]

    @extend_schema(request=PushSerializer, responses=PushReponseSerializer)
    def post(self, request):
        enveloppe = PushSerializer(data=request.data)
        enveloppe.is_valid(raise_exception=True)
        resultats = []
        for brute in enveloppe.validated_data["operations"]:
            operation = OperationSerializer(data=brute)
            if not operation.is_valid():
                resultats.append(
                    sync._resultat(
                        brute if isinstance(brute, dict) else {},
                        StatutOperation.ERREUR,
                        erreurs=operation.errors,
                    )
                )
                continue
            resultats.append(sync.executer(request, operation.validated_data))
        return Response(
            {
                "horodatage_serveur": timezone.now(),
                "resultats": sync.en_json(resultats),
            }
        )


class PullView(APIView):
    """GET /sync/pull/: rows changed since `depuis`, deletions included."""

    permission_classes = [ProfilReconnu]

    @extend_schema(
        parameters=[PullParametresSerializer],
        responses=PullReponseSerializer,
    )
    def get(self, request):
        parametres = PullParametresSerializer(data=request.query_params)
        parametres.is_valid(raise_exception=True)
        donnees = parametres.validated_data
        return Response(
            sync.en_json(
                sync.tirer(
                    request,
                    depuis=donnees.get("depuis"),
                    noms=donnees.get("tables"),
                    limite=donnees["limite"],
                    config_version=donnees.get("config_version"),
                    apres_id=donnees.get("apres_id"),
                )
            )
        )


class ConflitViewSet(viewsets.ReadOnlyModelViewSet):
    """/conflicts/: clinical conflicts waiting for a person (spec §9, §10)."""

    serializer_class = ConflitSerializer
    filterset_class = ConflitFilter
    permission_classes = [AccesParAction]
    profils_par_action = acces(
        lecture=(
            CodeProfile.BENEFICIAIRE,
            CodeProfile.ASC,
            CodeProfile.AGENT_CSB,
            CodeProfile.ADMIN,
        ),
        resoudre=(CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
    )

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return ConflitSync.objects.none()
        return sync.conflits_visibles(self.request.user).order_by("-created_at", "-id")

    @extend_schema(request=ResolutionSerializer, responses=ConflitSerializer)
    @action(detail=True, methods=["post"], url_path="resolve")
    def resoudre(self, request, pk=None):
        serializer = ResolutionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        conflit = sync.resoudre(request, self.get_object(), **serializer.validated_data)
        return Response(ConflitSerializer(conflit).data)
