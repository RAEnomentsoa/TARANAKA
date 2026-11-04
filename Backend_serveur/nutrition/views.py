from collections.abc import Mapping

from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema

from comptes.models import CodeProfile
from comptes.permissions import PROFILS_DOSSIERS, acces
from synchro.views import SyncViewSet

from . import services
from .filters import ConsultationFilter, EnfantFilter, JournalAlimentaireFilter, MesureFilter
from .serializers import (
    ConsultationSerializer,
    EnfantSerializer,
    JournalAlimentaireSerializer,
    MesureSerializer,
)

PROFILS = acces(
    lecture=PROFILS_DOSSIERS,
    ecriture=(CodeProfile.ASC, CodeProfile.ADMIN),
)


class EnfantViewSet(SyncViewSet):
    serializer_class = EnfantSerializer
    filterset_class = EnfantFilter
    profils_par_action = PROFILS

    def visibles(self):
        return services.enfants_visibles(self.request.user)

    def perform_update(self, serializer):
        serializer.instance = services.modifier_enfant(
            serializer.instance,
            serializer.validated_data,
            self.contexte(),
        )

    def perform_destroy(self, instance):
        services.supprimer_enfant(instance, self.contexte())


class MesureViewSet(SyncViewSet):
    serializer_class = MesureSerializer
    filterset_class = MesureFilter
    profils_par_action = PROFILS

    def visibles(self):
        return services.mesures_visibles(self.request.user)

    def perform_create(self, serializer):
        serializer.instance = services.creer_mesure(
            serializer.validated_data,
            self.contexte(),
        )

    def perform_update(self, serializer):
        serializer.instance = services.modifier_mesure(
            serializer.instance,
            serializer.validated_data,
            self.contexte(),
        )


@extend_schema(
    parameters=[
        OpenApiParameter("enfant_pk", OpenApiTypes.UUID, OpenApiParameter.PATH),
    ]
)
class MesureEnfantViewSet(MesureViewSet):
    """/children/{id}/measurements/. A child outside the user's scope gives a 404."""

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)
        self.enfant = get_object_or_404(
            services.enfants_visibles(request.user),
            pk=kwargs["enfant_pk"],
        )

    def visibles(self):
        return super().visibles().filter(enfant=self.enfant)

    def get_serializer(self, *args, **kwargs):
        donnees = kwargs.get("data")
        if isinstance(donnees, Mapping):
            donnees = donnees.copy()
            donnees["enfant_id"] = str(self.enfant.pk)
            kwargs["data"] = donnees
        return super().get_serializer(*args, **kwargs)


class JournalAlimentaireViewSet(SyncViewSet):
    """/food-logs/: 8-group food diary of a child of 6 to 23 months (spec §6)."""

    serializer_class = JournalAlimentaireSerializer
    filterset_class = JournalAlimentaireFilter
    profils_par_action = acces(
        lecture=PROFILS_DOSSIERS,
        ecriture=(CodeProfile.BENEFICIAIRE, CodeProfile.ASC, CodeProfile.ADMIN),
    )

    def visibles(self):
        return services.journaux_visibles(self.request.user)


class ConsultationViewSet(SyncViewSet):
    """/consultations/: what the centre's health worker records (spec §10)."""

    serializer_class = ConsultationSerializer
    filterset_class = ConsultationFilter
    profils_par_action = acces(
        lecture=PROFILS_DOSSIERS,
        ecriture=(CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
    )

    def visibles(self):
        return services.consultations_visibles(self.request.user)
