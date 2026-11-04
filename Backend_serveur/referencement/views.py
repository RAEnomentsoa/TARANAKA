from drf_spectacular.utils import extend_schema
from rest_framework.decorators import action
from rest_framework.response import Response

from comptes.models import CodeProfile
from comptes.permissions import acces
from synchro.views import SyncViewSet

from . import services
from .filters import ReferencementFilter
from .serializers import ReferencementSerializer, StatusSerializer


class ReferencementViewSet(SyncViewSet):
    serializer_class = ReferencementSerializer
    filterset_class = ReferencementFilter
    profils_par_action = acces(
        lecture=tuple(CodeProfile.values),
        ecriture=(CodeProfile.ADMIN,),
        create=(CodeProfile.ASC, CodeProfile.ADMIN),
        changer_status=(CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
    )

    def visibles(self):
        return services.referencements_visibles(self.request.user)

    def perform_create(self, serializer):
        serializer.instance = services.creer_referencement(
            serializer.validated_data,
            self.contexte(),
        )

    @extend_schema(request=StatusSerializer, responses=ReferencementSerializer)
    @action(detail=True, methods=["post"], url_path="status")
    def changer_status(self, request, pk=None):
        serializer = StatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        referencement = services.changer_status(
            self.get_object(),
            contexte=self.contexte(),
            **serializer.validated_data,
        )
        return Response(self.serialiser(referencement))
