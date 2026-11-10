from drf_spectacular.utils import extend_schema
from rest_framework import viewsets
from rest_framework.exceptions import NotFound
from rest_framework.response import Response
from rest_framework.views import APIView

from nutrition.zscores import valeur_a_z

from .filters import CSBFilter
from .models import CSB, Indicateur, Province, ReferenceOms, Region, TypeDangerGrossesse
from .serializers import (
    CSBSerializer,
    ProvinceSerializer,
    ReferenceOmsParametresSerializer,
    ReferenceOmsSerializer,
    RegionSerializer,
    TypeDangerGrossesseSerializer,
)

COURBES_Z = (-3, -2, 0, 2, 3)


class ProvinceViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Province.objects.all()
    serializer_class = ProvinceSerializer


class RegionViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Region.objects.all()
    serializer_class = RegionSerializer


class CSBViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = CSB.objects.all()
    serializer_class = CSBSerializer
    filterset_class = CSBFilter


class TypeDangerGrossesseViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = TypeDangerGrossesse.objects.all()
    serializer_class = TypeDangerGrossesseSerializer


class ReferenceOmsView(APIView):
    """/who-reference/: WHO 2006 growth standards, from the loaded tables only.

    Each point gives the official LMS values and the -3, -2, 0, +2, +3 SD
    curves computed from them (WHO formula). Nothing is served for a table
    that was not imported with `importer_tables_oms`.
    """

    @extend_schema(
        parameters=[ReferenceOmsParametresSerializer],
        responses=ReferenceOmsSerializer,
    )
    def get(self, request):
        parametres = ReferenceOmsParametresSerializer(data=request.query_params)
        parametres.is_valid(raise_exception=True)
        donnees = parametres.validated_data
        lignes = ReferenceOms.objects.filter(
            indicateur=donnees["indicateur"],
            sexe=donnees["sexe"],
        ).order_by("cle")
        if "cle_min" in donnees:
            lignes = lignes.filter(cle__gte=donnees["cle_min"])
        if "cle_max" in donnees:
            lignes = lignes.filter(cle__lte=donnees["cle_max"])
        lignes = list(lignes)
        if not lignes:
            raise NotFound(
                "Table OMS non chargée pour cet indicateur "
                "(python manage.py importer_tables_oms)."
            )
        pas = donnees.get("pas")
        if pas is not None:
            debut = lignes[0].cle
            lignes = [ligne for ligne in lignes if (ligne.cle - debut) % pas == 0]
        unite_cle = "jours" if donnees["indicateur"] in (Indicateur.WFA, Indicateur.LHFA) else "cm"
        unite_valeur = "cm" if donnees["indicateur"] == Indicateur.LHFA else "kg"
        return Response(
            {
                "source": "OMS 2006, tables LMS officielles chargées (reference_oms)",
                "indicateur": donnees["indicateur"],
                "sexe": donnees["sexe"],
                "unite_cle": unite_cle,
                "unite_valeur": unite_valeur,
                "points": [
                    {
                        "cle": ligne.cle,
                        "l": ligne.valeur_l,
                        "m": ligne.valeur_m,
                        "s": ligne.valeur_s,
                        "mesure_type": ligne.mesure_type,
                        "courbes": {
                            str(z): round(
                                valeur_a_z(ligne.valeur_l, ligne.valeur_m, ligne.valeur_s, z),
                                3,
                            )
                            for z in COURBES_Z
                        },
                    }
                    for ligne in lignes
                ],
            }
        )
