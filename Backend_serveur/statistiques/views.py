from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.models import CodeProfile
from comptes.permissions import IsSuperviseurOuAdmin
from referentiel.models import Province, Region
from synchro.models import JournalAudit

from . import services
from .renderers import CSVRenderer, ToujoursCsv


class ParametresSerializer(serializers.Serializer):
    date_debut = serializers.DateField(required=False)
    date_fin = serializers.DateField(required=False)
    region = serializers.PrimaryKeyRelatedField(queryset=Region.objects.all(), required=False)
    province = serializers.PrimaryKeyRelatedField(queryset=Province.objects.all(), required=False)
    grouper_par = serializers.ChoiceField(choices=("region", "mois"), required=False)

    def validate(self, attrs):
        debut, fin = services.periode_par_defaut()
        attrs.setdefault("date_debut", debut)
        attrs.setdefault("date_fin", fin)
        if attrs["date_debut"] > attrs["date_fin"]:
            raise serializers.ValidationError(
                {"date_debut": ["La date de début doit précéder la date de fin."]}
            )
        return attrs


class BlocSerializer(serializers.Serializer):
    indicateurs = serializers.DictField(child=serializers.FloatField(allow_null=True))
    masques = serializers.ListField(child=serializers.CharField())


class GroupeSerializer(BlocSerializer):
    cle = serializers.CharField()
    libelle = serializers.CharField()


class StatistiquesSerializer(serializers.Serializer):
    periode = serializers.DictField()
    seuil_petits_effectifs = serializers.IntegerField()
    grouper_par = serializers.CharField(allow_null=True)
    total = BlocSerializer()
    groupes = GroupeSerializer(many=True)


class BaseStatistiquesView(APIView):
    permission_classes = [IsSuperviseurOuAdmin]

    def calculer(self, request):
        parametres = ParametresSerializer(data=request.query_params)
        parametres.is_valid(raise_exception=True)
        donnees = parametres.validated_data
        regions = self.zone(request.user, donnees.get("region"), donnees.get("province"))
        return services.statistiques(
            donnees["date_debut"],
            donnees["date_fin"],
            regions,
            donnees.get("grouper_par"),
        )

    def zone(self, user, region, province):
        """A regional supervisor only sees their own region."""
        if user.profile.code == CodeProfile.SUPERVISEUR and user.region_id is not None:
            if (region and region.pk != user.region_id) or (
                province and province.pk != user.region.province_id
            ):
                raise PermissionDenied("Cette zone ne fait pas partie de votre supervision.")
            return Region.objects.filter(pk=user.region_id)
        if region is not None:
            return Region.objects.filter(pk=region.pk)
        if province is not None:
            return Region.objects.filter(province=province)
        return None


class StatistiquesView(BaseStatistiquesView):
    """/stats/: aggregated and anonymous indicators (spec §10)."""

    @extend_schema(parameters=[ParametresSerializer], responses=StatistiquesSerializer)
    def get(self, request):
        return Response(self.calculer(request))


class ExportCsvView(BaseStatistiquesView):
    """/stats/export/: the same indicators as CSV. Each export is audited."""

    renderer_classes = [CSVRenderer]
    content_negotiation_class = ToujoursCsv

    @extend_schema(
        parameters=[ParametresSerializer],
        responses={
            (200, "text/csv"): OpenApiResponse(
                OpenApiTypes.STR,
                description="Fichier CSV : groupe,indicateur,valeur",
            )
        },
    )
    def get(self, request):
        resultat = self.calculer(request)
        JournalAudit.objects.create(
            user=request.user,
            action="export_csv",
            details={
                "ip": request.META.get("REMOTE_ADDR"),
                "parametres": dict(request.query_params),
            },
        )
        nom = (
            f'taranaka_stats_{resultat["periode"]["date_debut"]}'
            f'_{resultat["periode"]["date_fin"]}.csv'
        )
        return Response(
            list(services.lignes_csv(resultat)),
            headers={"Content-Disposition": f'attachment; filename="{nom}"'},
        )
