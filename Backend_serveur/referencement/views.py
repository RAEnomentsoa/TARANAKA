from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.models import CodeProfile
from comptes.permissions import PROFILS_DOSSIERS, acces, profil_requis
from synchro.views import SyncViewSet

from . import services
from .filters import ReferencementFilter, RendezVousFilter
from .serializers import (
    ReferencementSerializer,
    RendezVousSerializer,
    StatusSerializer,
)

LIMITE_RELANCES = 200


class ReferencementViewSet(SyncViewSet):
    serializer_class = ReferencementSerializer
    filterset_class = ReferencementFilter
    profils_par_action = acces(
        lecture=PROFILS_DOSSIERS,
        ecriture=(CodeProfile.ADMIN,),
        create=(CodeProfile.ASC, CodeProfile.ADMIN),
        changer_status=(CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
        entrants=(CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
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
        """Patient arrivé (recu), prise en charge, suivi, sortie (spec §7, §10)."""
        serializer = StatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        referencement = services.changer_status(
            self.get_object(),
            contexte=self.contexte(),
            **serializer.validated_data,
        )
        return Response(self.serialiser(referencement))

    @extend_schema(responses=ReferencementSerializer(many=True))
    @action(detail=False, methods=["get"], url_path="incoming")
    def entrants(self, request):
        """Queue of the centre: not yet taken in charge, red first, then oldest."""
        referencements = services.trier_par_urgence(
            self.filter_queryset(self.visibles()).filter(
                status__in=(services.Status.ENVOYE, services.Status.RECU)
            )
        )
        page = self.paginate_queryset(referencements)
        return self.get_paginated_response(
            self.get_serializer(page, many=True).data
        )


class RendezVousViewSet(SyncViewSet):
    """/appointments/: follow-up visits; ?manque=true lists the missed ones."""

    serializer_class = RendezVousSerializer
    filterset_class = RendezVousFilter
    profils_par_action = acces(
        lecture=PROFILS_DOSSIERS,
        ecriture=(CodeProfile.ASC, CodeProfile.AGENT_CSB, CodeProfile.ADMIN),
    )

    def visibles(self):
        return services.rendez_vous_visibles(self.request.user)


class EnfantARevoirSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    nom = serializers.CharField()
    date_naissance = serializers.DateField()
    sexe = serializers.CharField()
    statut_prise_en_charge = serializers.CharField()
    prochain_controle = serializers.DateField()
    derniere_classification = serializers.CharField()


class RelancesSerializer(serializers.Serializer):
    delai_non_arrivee_heures = serializers.IntegerField(allow_null=True)
    referencements_non_arrives = ReferencementSerializer(many=True)
    rendez_vous_manques = RendezVousSerializer(many=True)
    enfants_a_revoir = EnfantARevoirSerializer(many=True)


class RelancesView(APIView):
    """/follow-ups/: referrals not arrived, missed visits, children to see again."""

    permission_classes = [
        profil_requis(CodeProfile.ASC, CodeProfile.AGENT_CSB, CodeProfile.ADMIN)
    ]

    @extend_schema(responses=RelancesSerializer)
    def get(self, request):
        listes = services.relances(request.user)
        donnees = {
            cle: (valeur[:LIMITE_RELANCES] if hasattr(valeur, "filter") else valeur)
            for cle, valeur in listes.items()
        }
        return Response(
            RelancesSerializer(donnees, context={"request": request}).data
        )
