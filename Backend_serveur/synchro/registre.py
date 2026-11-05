"""The synced tables, as /sync sees them.

Each table reuses its REST ViewSet: same permissions, same serializer, same
services. An operation sent through /sync is checked exactly like the same
request sent to the row's endpoint.
"""

from dataclasses import dataclass
from functools import cache


@dataclass(frozen=True)
class TableSync:
    nom: str
    vue: type
    visibles: object
    # Clinical data: a conflict is queued for a person, never overwritten (§9).
    clinique: bool
    # (attribute set on the view, visible parents, field of the parent's id)
    parent: tuple | None = None

    @property
    def modele(self):
        return self.vue.serializer_class.Meta.model


@cache
def tables():
    from nutrition import services as nutrition
    from nutrition.views import (
        ConsultationViewSet,
        EnfantViewSet,
        JournalAlimentaireViewSet,
        MesureViewSet,
    )
    from referencement import services as referencement
    from referencement.views import ReferencementViewSet, RendezVousViewSet
    from sante_femme import services as sante_femme
    from sante_femme.views import CycleViewSet, DangerGrossesseViewSet, GrossesseViewSet

    # Order matters for a first pull: parents before children.
    liste = (
        TableSync("cycle", CycleViewSet, sante_femme.cycles_visibles, clinique=False),
        TableSync("grossesse", GrossesseViewSet, sante_femme.grossesses_visibles, clinique=True),
        TableSync(
            "danger_grossesse",
            DangerGrossesseViewSet,
            sante_femme.dangers_visibles,
            clinique=True,
            parent=("grossesse", sante_femme.grossesses_visibles, "grossesse_id"),
        ),
        TableSync("enfant", EnfantViewSet, nutrition.enfants_visibles, clinique=True),
        TableSync("mesure", MesureViewSet, nutrition.mesures_visibles, clinique=True),
        TableSync(
            "journal_alimentaire",
            JournalAlimentaireViewSet,
            nutrition.journaux_visibles,
            clinique=False,
        ),
        TableSync(
            "referencement",
            ReferencementViewSet,
            referencement.referencements_visibles,
            clinique=True,
        ),
        TableSync(
            "consultation_nutritionnelle",
            ConsultationViewSet,
            nutrition.consultations_visibles,
            clinique=True,
        ),
        TableSync(
            "rendez_vous",
            RendezVousViewSet,
            referencement.rendez_vous_visibles,
            clinique=True,
        ),
    )
    return {table.nom: table for table in liste}


NOMS_TABLES = (
    "cycle",
    "grossesse",
    "danger_grossesse",
    "enfant",
    "mesure",
    "journal_alimentaire",
    "referencement",
    "consultation_nutritionnelle",
    "rendez_vous",
)
