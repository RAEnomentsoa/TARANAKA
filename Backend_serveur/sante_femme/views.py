from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema

from comptes.models import CodeProfile
from comptes.permissions import acces
from synchro.views import SyncViewSet

from . import services
from .filters import CycleFilter, DangerGrossesseFilter, GrossesseFilter
from .serializers import (
    CycleSerializer,
    DangerCreeSerializer,
    DangerGrossesseSerializer,
    GrossesseSerializer,
)


class CycleViewSet(SyncViewSet):
    serializer_class = CycleSerializer
    filterset_class = CycleFilter
    profils_par_action = acces(
        lecture=(CodeProfile.BENEFICIAIRE, CodeProfile.ADMIN),
        ecriture=(CodeProfile.BENEFICIAIRE, CodeProfile.ADMIN),
    )

    def visibles(self):
        return services.cycles_visibles(self.request.user)


class GrossesseViewSet(SyncViewSet):
    serializer_class = GrossesseSerializer
    filterset_class = GrossesseFilter
    profils_par_action = acces(
        lecture=tuple(CodeProfile.values),
        ecriture=(CodeProfile.BENEFICIAIRE, CodeProfile.ASC, CodeProfile.ADMIN),
    )

    def visibles(self):
        return services.grossesses_visibles(self.request.user)

    def perform_destroy(self, instance):
        services.supprimer_grossesse(instance, self.contexte())


@extend_schema(
    parameters=[
        OpenApiParameter("grossesse_pk", OpenApiTypes.UUID, OpenApiParameter.PATH),
    ]
)
class DangerGrossesseViewSet(SyncViewSet):
    """/pregnancies/{id}/dangers/. A pregnancy outside the user's scope gives a 404."""

    serializer_class = DangerGrossesseSerializer
    filterset_class = DangerGrossesseFilter
    profils_par_action = GrossesseViewSet.profils_par_action

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        self.grossesse = get_object_or_404(
            services.grossesses_visibles(request.user),
            pk=kwargs["grossesse_pk"],
        )

    def get_serializer_class(self):
        if self.action == "create":
            return DangerCreeSerializer
        return DangerGrossesseSerializer

    def visibles(self):
        return services.dangers_visibles(self.request.user).filter(
            grossesse=self.grossesse
        )

    def perform_create(self, serializer):
        danger, referencement, avertissement = services.signaler_danger(
            self.grossesse,
            serializer.validated_data,
            self.contexte(),
        )
        danger.referencement = referencement
        danger.avertissement = avertissement
        serializer.instance = danger
