from drf_spectacular.utils import extend_schema
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound
from rest_framework.response import Response

from comptes.models import CodeProfile
from comptes.permissions import AccesParAction, acces

from . import services
from .models import ConfigurationClinique, StatutPublication
from .serializers import ConfigResumeSerializer, ConfigSerializer


def _ip(request):
    return request.META.get("REMOTE_ADDR")


class ConfigurationCliniqueViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    """/clinical-config/: versioned clinical rules and content (spec §11).

    Everyone reads the published versions. Only an admin creates a draft,
    edits it and publishes it.
    """

    lookup_field = "version"
    lookup_value_regex = "[0-9]+"
    permission_classes = [AccesParAction]
    profils_par_action = acces(
        lecture=tuple(CodeProfile.values),
        ecriture=(CodeProfile.ADMIN,),
        actuelle=tuple(CodeProfile.values),
        publier=(CodeProfile.ADMIN,),
        retirer=(CodeProfile.ADMIN,),
    )

    def get_queryset(self):
        configs = ConfigurationClinique.objects.order_by("-version")
        if getattr(self, "swagger_fake_view", False):
            return configs.none()
        if self.request.user.profile.code == CodeProfile.ADMIN:
            return configs
        return configs.exclude(statut=StatutPublication.BROUILLON)

    def get_serializer_class(self):
        if self.action == "list":
            return ConfigResumeSerializer
        return ConfigSerializer

    def perform_create(self, serializer):
        serializer.instance = services.creer_version(
            serializer.validated_data,
            self.request.user,
            _ip(self.request),
        )

    def perform_update(self, serializer):
        serializer.instance = services.modifier_brouillon(
            serializer.instance,
            serializer.validated_data,
            self.request.user,
            _ip(self.request),
        )

    @extend_schema(responses=ConfigSerializer)
    @action(detail=False, methods=["get"], url_path="current")
    def actuelle(self, request):
        """The version the apps must use. Send If-None-Match to get a 304."""
        config = services.config_active()
        if config is None:
            raise NotFound("Aucune configuration clinique publiée.")
        etag = f'"v{config.version}"'
        if request.headers.get("If-None-Match") == etag:
            return Response(status=304, headers={"ETag": etag})
        return Response(ConfigSerializer(config).data, headers={"ETag": etag})

    @extend_schema(request=None, responses=ConfigSerializer)
    @action(detail=True, methods=["post"], url_path="publish")
    def publier(self, request, version=None):
        config = services.publier(self.get_object(), request.user, _ip(request))
        return Response(ConfigSerializer(config).data)

    @extend_schema(request=None, responses=ConfigSerializer)
    @action(detail=True, methods=["post"], url_path="retire")
    def retirer(self, request, version=None):
        config = services.retirer(self.get_object(), request.user, _ip(request))
        return Response(ConfigSerializer(config).data)
