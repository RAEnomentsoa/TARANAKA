from django.db import transaction
from django.db.models import ProtectedError, RestrictedError
from drf_spectacular.utils import extend_schema
from rest_framework import viewsets
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from comptes.models import CodeProfile, User
from comptes.permissions import AccesParAction, acces
from nutrition.zscores import valeur_a_z
from synchro.models import JournalAudit
from synchro.services import LONGUEUR_DEVICE_ID

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


class TerritoireViewSet(viewsets.ModelViewSet):
    """Everyone reads the territory; only the admin changes it.

    A row still used elsewhere is never deleted: the answer says why (400).
    """

    permission_classes = [AccesParAction]
    profils_par_action = acces(lecture=tuple(CodeProfile.values), ecriture=(CodeProfile.ADMIN,))
    message_utilise = ""

    def utilisations(self, ligne):
        """Rows that the database would not protect (SET_NULL) but that need it."""
        return False

    def perform_create(self, serializer):
        super().perform_create(serializer)
        self.journaliser("creation", serializer.instance)

    def perform_update(self, serializer):
        super().perform_update(serializer)
        self.journaliser("modification", serializer.instance)

    def perform_destroy(self, ligne):
        if self.utilisations(ligne):
            raise ValidationError({"detail": self.message_utilise})
        try:
            with transaction.atomic():
                ligne.delete()
        except (ProtectedError, RestrictedError) as erreur:
            raise ValidationError({"detail": self.message_utilise}) from erreur
        self.journaliser("suppression", ligne)

    def journaliser(self, action, ligne):
        # Integer ids: they go in the details, ligne_id holds UUIDs only.
        JournalAudit.objects.create(
            user=self.request.user,
            action=f"territoire_{action}",
            table_nom=ligne._meta.db_table,
            details={
                "ip": self.request.META.get("REMOTE_ADDR"),
                "device_id": self.request.headers.get("X-Device-Id", "")[:LONGUEUR_DEVICE_ID],
                "id": ligne.pk,
                "nom": str(ligne),
            },
        )


class ProvinceViewSet(TerritoireViewSet):
    queryset = Province.objects.all()
    serializer_class = ProvinceSerializer
    message_utilise = "Cette province a encore des régions : supprimez-les ou déplacez-les d'abord."


class RegionViewSet(TerritoireViewSet):
    queryset = Region.objects.all()
    serializer_class = RegionSerializer
    message_utilise = (
        "Cette région est encore utilisée (centres, comptes ou dossiers) : "
        "elle ne peut pas être supprimée."
    )

    def utilisations(self, ligne):
        # A user's region is SET_NULL: deleting would silently empty it.
        return User.objects.filter(region=ligne).exists()


class CSBViewSet(TerritoireViewSet):
    queryset = CSB.objects.all()
    serializer_class = CSBSerializer
    filterset_class = CSBFilter
    message_utilise = (
        "Ce centre est encore utilisé (comptes ou référencements) : "
        "il ne peut pas être supprimé."
    )


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
