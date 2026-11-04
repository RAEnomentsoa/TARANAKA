"""Outbox synchronisation (spec §9).

push: the phone sends its outbox as a list of operations, each with an
idempotency key. They are applied in order, each in its own savepoint, so one
refused operation never blocks the others.

pull: the phone asks for every row changed since its last pull, deleted rows
included, plus the state of its conflicts and the clinical config if newer.
"""

import copy
import json
from datetime import timedelta

from django.core.serializers.json import DjangoJSONEncoder
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.http import Http404
from django.utils import timezone
from rest_framework.exceptions import (
    APIException,
    NotFound,
    PermissionDenied,
    ValidationError,
)
from rest_framework.request import Request

from comptes.models import CodeProfile
from config_clinique.serializers import ConfigSerializer
from config_clinique.services import config_active

from .exceptions import ConflitVersion
from .models import (
    ConflitSync,
    HistoriqueVersion,
    OperationSync,
    Resolution,
    StatutConflit,
    StatutOperation,
    TypeOperation,
)
from .registre import tables
from .services import Contexte, contexte_depuis, journaliser_ligne

ACTIONS = {
    TypeOperation.CREATE: "create",
    TypeOperation.UPDATE: "partial_update",
    TypeOperation.DELETE: "destroy",
}
STATUTS_DEFINITIFS = {
    StatutOperation.APPLIQUE,
    StatutOperation.DEJA_APPLIQUE,
    StatutOperation.CONFLIT,
}
# Rows committed just before the pull may carry an earlier updated_at than
# the pull's start: the next pull starts a little earlier to catch them.
MARGE_PULL = timedelta(seconds=5)


def en_json(donnees):
    return json.loads(json.dumps(donnees, cls=DjangoJSONEncoder))


def vue_pour(table, requete, action):
    vue = table.vue()
    vue.request = requete
    vue.args = ()
    vue.kwargs = {}
    vue.action = action
    vue.format_kwarg = None
    vue.headers = {}
    return vue


def peut(table, user, action):
    return user.profile.code in table.vue.profils_par_action.get(action, ())


# ---------------------------------------------------------------- push


def executer_lot(requete, operations):
    return [executer(requete, operation) for operation in operations]


def executer(requete, operation):
    """operation is already validated by OperationSerializer."""
    cle = operation["cle_idempotence"]
    deja = OperationSync.objects.filter(cle_idempotence=cle).first()
    if deja is not None:
        return _rejouer(deja, requete, operation)

    table = tables()[operation["table"]]
    try:
        with transaction.atomic():
            resultat = _appliquer(requete, table, operation)
            if resultat["statut"] in STATUTS_DEFINITIFS:
                OperationSync.objects.create(
                    cle_idempotence=cle,
                    user=requete.user,
                    device_id=contexte_depuis(requete).device_id,
                    table_nom=table.nom,
                    operation=operation["operation"],
                    ligne_id=operation["id"],
                    statut=resultat["statut"],
                    reponse=en_json(resultat),
                )
            return resultat
    except IntegrityError:
        # The same key arrived twice at the same time: give the stored answer.
        deja = OperationSync.objects.filter(cle_idempotence=cle).first()
        if deja is not None:
            return _rejouer(deja, requete, operation)
        return _resultat(
            operation,
            StatutOperation.ERREUR,
            erreurs={"detail": "Enregistrement impossible : donnée en double."},
        )
    except ValidationError as erreur:
        return _resultat(operation, StatutOperation.ERREUR, erreurs=erreur.detail)
    except PermissionDenied as erreur:
        return _resultat(operation, StatutOperation.REFUSE, erreurs={"detail": erreur.detail})
    except (Http404, NotFound):
        return _resultat(
            operation,
            StatutOperation.INTROUVABLE,
            erreurs={"detail": "Ligne introuvable ou non accessible."},
        )
    except APIException as erreur:
        return _resultat(operation, StatutOperation.ERREUR, erreurs=erreur.detail)


def _rejouer(deja, requete, operation):
    if deja.user_id != requete.user.pk:
        return _resultat(
            operation,
            StatutOperation.ERREUR,
            erreurs={"cle_idempotence": ["Cette clé est déjà utilisée."]},
        )
    return {**deja.reponse, "rejoue": True}


def _resultat(operation, statut, ligne=None, conflit_id=None, erreurs=None):
    return {
        "cle_idempotence": operation.get("cle_idempotence"),
        "table": operation.get("table"),
        "operation": operation.get("operation"),
        "id": operation.get("id"),
        "statut": statut,
        "ligne": ligne,
        "conflit_id": conflit_id,
        "erreurs": erreurs,
        "rejoue": False,
    }


def _appliquer(requete, table, operation):
    type_operation = operation["operation"]
    vue = vue_pour(table, requete, ACTIONS[type_operation])
    vue.check_permissions(requete)
    donnees = dict(operation.get("donnees") or {})
    ligne_id = operation["id"]

    if type_operation == TypeOperation.CREATE:
        if table.parent:
            _fixer_parent(table, vue, requete.user, donnees.get(table.parent[2]))
        existante = vue.get_queryset().filter(pk=ligne_id).first()
        if existante is not None:
            # The phone didn't get the first answer: same row, nothing created.
            return _resultat(
                operation,
                StatutOperation.DEJA_APPLIQUE,
                ligne=en_json(vue.serialiser(existante)),
            )
        serializer = vue.get_serializer(data={**donnees, "id": str(ligne_id)})
        serializer.is_valid(raise_exception=True)
        vue.perform_create(serializer)
        return _resultat(operation, StatutOperation.APPLIQUE, ligne=en_json(serializer.data))

    instance = _trouver(table, vue, requete.user, ligne_id)
    if type_operation == TypeOperation.DELETE:
        if instance is None:
            if table.visibles(requete.user, True).filter(pk=ligne_id).exists():
                return _resultat(operation, StatutOperation.DEJA_APPLIQUE)
            raise NotFound
        version = operation.get("version")
        if version is not None and version != instance.version:
            return _conflit(requete, table, vue, operation, instance)
        vue.perform_destroy(instance)
        return _resultat(operation, StatutOperation.APPLIQUE)

    if instance is None:
        raise NotFound
    serializer = vue.get_serializer(
        instance,
        data={**donnees, "version": operation["version"]},
        partial=True,
    )
    serializer.is_valid(raise_exception=True)
    try:
        vue.perform_update(serializer)
    except ConflitVersion as conflit:
        return _conflit(requete, table, vue, operation, conflit.ligne)
    return _resultat(
        operation,
        StatutOperation.APPLIQUE,
        ligne=en_json(vue.serialiser(serializer.instance)),
    )


def _fixer_parent(table, vue, user, parent_id):
    attribut, visibles, champ = table.parent
    parent = visibles(user).filter(pk=parent_id).first() if parent_id else None
    if parent is None:
        raise ValidationError({champ: ["Ce champ est obligatoire ou n'est pas accessible."]})
    setattr(vue, attribut, parent)


def _trouver(table, vue, user, ligne_id):
    if table.parent:
        ligne = table.visibles(user).filter(pk=ligne_id).first()
        if ligne is None:
            return None
        setattr(vue, table.parent[0], getattr(ligne, table.parent[0]))
    return vue.get_queryset().filter(pk=ligne_id).first()


def _conflit(requete, table, vue, operation, courante):
    """Keep both versions. Clinical data goes to the queue of the web dashboard."""
    donnees_serveur = en_json(vue.serialiser(courante))
    if not table.clinique:
        # Personal data (cycle, food log): the phone gets the server row and
        # decides; nothing is shown to health workers.
        return _resultat(operation, StatutOperation.CONFLIT, ligne=donnees_serveur)

    contexte = contexte_depuis(requete)
    donnees_telephone = en_json(operation.get("donnees") or {})
    conflit = ConflitSync.objects.create(
        table_nom=table.nom,
        ligne_id=courante.pk,
        operation=operation["operation"],
        version_base=operation.get("version"),
        version_serveur=courante.version,
        donnees_telephone=donnees_telephone,
        donnees_serveur=donnees_serveur,
        user=requete.user,
        device_id=contexte.device_id,
    )
    _historiser(table.nom, courante.pk, courante.version, courante.device_id, donnees_serveur)
    _historiser(
        table.nom,
        courante.pk,
        (operation.get("version") or courante.version) + 1,
        contexte.device_id,
        donnees_telephone,
    )
    journaliser_ligne(
        "conflit_sync",
        courante,
        contexte,
        conflit_id=str(conflit.pk),
        version_base=operation.get("version"),
        version_serveur=courante.version,
    )
    return _resultat(
        operation,
        StatutOperation.CONFLIT,
        ligne=donnees_serveur,
        conflit_id=str(conflit.pk),
    )


def _historiser(table_nom, ligne_id, version, device_id, donnees):
    ligne, cree = HistoriqueVersion.objects.get_or_create(
        table_nom=table_nom,
        ligne_id=ligne_id,
        version=version,
        device_id=device_id,
        defaults={"donnees": donnees, "conflit": True},
    )
    if not cree and not ligne.conflit:
        HistoriqueVersion.objects.filter(pk=ligne.pk).update(conflit=True)


# ---------------------------------------------------------------- pull


def tirer(requete, depuis=None, noms=None, limite=500, config_version=None):
    debut = timezone.now()
    user = requete.user
    resultat = {"tables": {}}
    for nom, table in tables().items():
        if noms and nom not in noms:
            continue
        if not peut(table, user, "list"):
            continue
        lignes = table.visibles(user, True)
        if depuis is not None:
            lignes = lignes.filter(updated_at__gte=depuis)
        lignes = list(lignes.order_by("updated_at", "id")[: limite + 1])
        suite = len(lignes) > limite
        lignes = lignes[:limite]
        vue = vue_pour(table, requete, "list")
        resultat["tables"][nom] = {
            "lignes": [vue.serialiser(ligne) for ligne in lignes],
            "suite": suite,
            "prochain_depuis": lignes[-1].updated_at if suite else debut - MARGE_PULL,
        }

    conflits = ConflitSync.objects.filter(user=user)
    if depuis is not None:
        conflits = conflits.filter(updated_at__gte=depuis)
    resultat["conflits"] = list(
        conflits.order_by("updated_at").values(
            "id",
            "table_nom",
            "ligne_id",
            "statut",
            "resolution",
            "version_finale",
            "resolu_le",
        )
    )

    config = config_active()
    resultat["config_clinique"] = {
        "version": config.version if config else None,
        "mise_a_jour": (
            ConfigSerializer(config).data
            if config and (config_version is None or config_version < config.version)
            else None
        ),
    }
    resultat["horodatage_serveur"] = debut - MARGE_PULL
    return resultat


# ---------------------------------------------------------------- conflicts


def conflits_visibles(user):
    code = user.profile.code
    conflits = ConflitSync.objects.select_related("user", "resolu_par")
    if code == CodeProfile.ADMIN:
        return conflits
    if code == CodeProfile.AGENT_CSB:
        condition = Q(pk__in=[])
        for nom, table in tables().items():
            if table.clinique:
                condition |= Q(
                    table_nom=nom,
                    ligne_id__in=table.visibles(user, True).values("pk"),
                )
        return conflits.filter(condition)
    if code in (CodeProfile.ASC, CodeProfile.BENEFICIAIRE):
        return conflits.filter(user=user)
    return conflits.none()


def resoudre(requete, conflit, choix, donnees=None, commentaire=""):
    """Apply the person's decision. The row always gets a new version, so every
    phone pulls the decided version, even when the server's version is kept."""
    with transaction.atomic():
        conflit = ConflitSync.objects.select_for_update().get(pk=conflit.pk)
        if conflit.statut == StatutConflit.RESOLU:
            raise ValidationError({"statut": ["Ce conflit est déjà résolu."]})
        if choix == Resolution.FUSION and not isinstance(donnees, dict):
            raise ValidationError({"donnees": ["La version fusionnée est obligatoire."]})
        table = tables()[conflit.table_nom]

        # The decided data is checked in the sender's scope (as if their change
        # had gone through), and recorded in the audit log as the arbiter's.
        expediteur = _requete_comme(requete, conflit.user)
        contexte_arbitre = contexte_depuis(requete)
        supprimer = conflit.operation == TypeOperation.DELETE and choix == Resolution.TELEPHONE
        vue = vue_pour(table, expediteur, "destroy" if supprimer else "partial_update")
        vue.contexte = lambda: contexte_arbitre
        instance = _trouver(table, vue, conflit.user, conflit.ligne_id)
        if instance is None:
            raise ValidationError({"ligne": ["Cette ligne n'existe plus."]})

        if supprimer:
            vue.perform_destroy(instance)
            version_finale = instance.version + 1
        else:
            a_appliquer = {
                Resolution.SERVEUR: {},
                Resolution.TELEPHONE: (
                    conflit.donnees_telephone
                    if conflit.operation == TypeOperation.UPDATE
                    else {}
                ),
                Resolution.FUSION: donnees or {},
            }[choix]
            a_appliquer = {
                cle: valeur
                for cle, valeur in a_appliquer.items()
                if cle not in ("id", "version")
            }
            serializer = vue.get_serializer(
                instance,
                data={**a_appliquer, "version": instance.version},
                partial=True,
            )
            serializer.is_valid(raise_exception=True)
            vue.perform_update(serializer)
            version_finale = serializer.instance.version

        conflit.statut = StatutConflit.RESOLU
        conflit.resolution = choix
        conflit.resolu_par = requete.user
        conflit.resolu_le = timezone.now()
        conflit.version_finale = version_finale
        conflit.commentaire = commentaire
        conflit.save()
        journaliser_ligne(
            "conflit_resolu",
            instance,
            Contexte(
                user=requete.user,
                ip=contexte_arbitre.ip,
                device_id=contexte_arbitre.device_id,
            ),
            conflit_id=str(conflit.pk),
            resolution=choix,
            version_finale=version_finale,
        )
    return conflit


def _requete_comme(requete, user):
    copie = copy.copy(requete._request)
    nouvelle = Request(copie, parsers=requete.parsers)
    nouvelle.user = user
    return nouvelle
