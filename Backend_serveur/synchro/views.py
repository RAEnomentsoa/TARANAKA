import uuid
from collections.abc import Mapping

from rest_framework import status, viewsets
from rest_framework.response import Response

from comptes.permissions import AccesParAction

from . import services
from .exceptions import ConflitVersion


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
