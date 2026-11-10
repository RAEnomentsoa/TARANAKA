from django.shortcuts import get_object_or_404
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema

from comptes.models import CodeProfile
from comptes.permissions import PROFILS_DOSSIERS, acces
from comptes.services import suivre
from synchro.views import SyncViewSet

from . import services
from .filters import (
    AlimentationFemmeFilter,
    ContactSoinFilter,
    CycleFilter,
    CycleJourFilter,
    DangerGrossesseFilter,
    GrossesseFilter,
    MouvementBebeFilter,
    MouvementEvenementFilter,
    SuiviGrossesseFilter,
)
from .serializers import (
    AlimentationFemmeSerializer,
    ContactSoinSerializer,
    CycleJourSerializer,
    CycleSerializer,
    DangerCreeSerializer,
    DangerGrossesseSerializer,
    GrossesseSerializer,
    MouvementBebeSerializer,
    MouvementEvenementSerializer,
    SuiviGrossesseSerializer,
)

# Her own data: only she (and the admin) writes it. Health workers read it
# for the women they follow (D16).
PROFILS_FEMME = acces(
    lecture=PROFILS_DOSSIERS,
    ecriture=(CodeProfile.BENEFICIAIRE, CodeProfile.ADMIN),
)
# The pregnancy follow-up: the ASC may also write it, as for the pregnancy.
PROFILS_GROSSESSE = acces(
    lecture=PROFILS_DOSSIERS,
    ecriture=(CodeProfile.BENEFICIAIRE, CodeProfile.ASC, CodeProfile.ADMIN),
)


class CycleViewSet(SyncViewSet):
    """/cycles/: only if she shares her cycle (D16 option a)."""

    serializer_class = CycleSerializer
    filterset_class = CycleFilter
    profils_par_action = PROFILS_FEMME

    def visibles(self):
        return services.cycles_visibles(self.request.user)


class CycleJourViewSet(SyncViewSet):
    """/cycle-days/: "Mon suivi du jour", shared like the cycle."""

    serializer_class = CycleJourSerializer
    filterset_class = CycleJourFilter
    profils_par_action = PROFILS_FEMME

    def visibles(self):
        return services.cycle_jours_visibles(self.request.user)


class AlimentationFemmeViewSet(SyncViewSet):
    """/women-food-logs/: the woman's food groups of the day."""

    serializer_class = AlimentationFemmeSerializer
    filterset_class = AlimentationFemmeFilter
    profils_par_action = PROFILS_FEMME

    def visibles(self):
        return services.alimentations_visibles(self.request.user)


class GrossesseViewSet(SyncViewSet):
    serializer_class = GrossesseSerializer
    filterset_class = GrossesseFilter
    profils_par_action = PROFILS_GROSSESSE

    def visibles(self):
        return services.grossesses_visibles(self.request.user)

    def perform_create(self, serializer):
        super().perform_create(serializer)
        # An ASC who records a pregnancy follows the woman from then on.
        suivre(self.request.user, serializer.instance.user, self.contexte(), "grossesse")

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


class ContactSoinViewSet(SyncViewSet):
    """/care-contacts/: the CPN and postnatal contacts attended."""

    serializer_class = ContactSoinSerializer
    filterset_class = ContactSoinFilter
    profils_par_action = PROFILS_GROSSESSE

    def visibles(self):
        return services.contacts_visibles(self.request.user)


class SuiviGrossesseViewSet(SyncViewSet):
    """/pregnancy-checks/: weight, blood pressure, fundal height..."""

    serializer_class = SuiviGrossesseSerializer
    filterset_class = SuiviGrossesseFilter
    profils_par_action = PROFILS_GROSSESSE

    def visibles(self):
        return services.suivis_grossesse_visibles(self.request.user)


class MouvementBebeViewSet(SyncViewSet):
    """/baby-movements/: movements counted per day."""

    serializer_class = MouvementBebeSerializer
    filterset_class = MouvementBebeFilter
    profils_par_action = PROFILS_FEMME

    def visibles(self):
        return services.mouvements_visibles(self.request.user)


class MouvementEvenementViewSet(SyncViewSet):
    """/baby-movement-events/: each movement felt."""

    serializer_class = MouvementEvenementSerializer
    filterset_class = MouvementEvenementFilter
    profils_par_action = PROFILS_FEMME

    def visibles(self):
        return services.mouvements_evenements_visibles(self.request.user)
