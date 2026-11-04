from dataclasses import dataclass

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.http import Http404
from rest_framework.exceptions import ValidationError

from .exceptions import MESSAGE_ID_UTILISE, ConflitVersion
from .models import JournalAudit

LONGUEUR_DEVICE_ID = 100


@dataclass(frozen=True)
class Contexte:
    """Who makes the change, so that the future /sync can reuse the services."""

    user: object
    ip: str | None = None
    device_id: str = ""


def contexte_depuis(request):
    return Contexte(
        user=request.user,
        ip=request.META.get("REMOTE_ADDR"),
        device_id=request.headers.get("X-Device-Id", "")[:LONGUEUR_DEVICE_ID],
    )


def journaliser_ligne(action, ligne, contexte, **details):
    """Record field names only: health data stays out of the audit log."""
    JournalAudit.objects.create(
        user=contexte.user,
        action=action,
        table_nom=ligne._meta.db_table,
        ligne_id=ligne.pk,
        details={"ip": contexte.ip, "device_id": contexte.device_id, **details},
    )


def valider(ligne):
    """Apply the model rules, CheckConstraints included: DRF doesn't run them."""
    try:
        ligne.full_clean(validate_unique=False)
    except DjangoValidationError as erreur:
        erreurs = dict(erreur.message_dict)
        if "__all__" in erreurs:
            erreurs["non_field_errors"] = erreurs.pop("__all__")
        raise ValidationError(erreurs) from erreur


def creer_ligne(modele, donnees, contexte):
    donnees = {cle: valeur for cle, valeur in donnees.items() if cle != "version"}
    ligne = modele(device_id=contexte.device_id, **donnees)
    valider(ligne)
    with transaction.atomic():
        try:
            # force_insert: an id sent by a phone must never overwrite a row.
            with transaction.atomic():
                ligne.save(force_insert=True)
        except IntegrityError as erreur:
            if modele.all_objects.filter(pk=ligne.pk).exists():
                raise ValidationError({"id": [MESSAGE_ID_UTILISE]}) from erreur
            raise
        journaliser_ligne("create", ligne, contexte, version=ligne.version)
    return ligne


def verrouiller(ligne):
    """Must run in a transaction. A row deleted in the meantime gives a 404."""
    courante = (
        type(ligne).objects.select_for_update(of=("self",)).filter(pk=ligne.pk).first()
    )
    if courante is None:
        raise Http404
    return courante


def verifier_version(ligne, version):
    if ligne.version != version:
        raise ConflitVersion(ligne)


def enregistrer_modification(courante, donnees, contexte, **details):
    """courante must be locked and its version already checked."""
    donnees = {cle: valeur for cle, valeur in donnees.items() if cle != "version"}
    for champ, valeur in donnees.items():
        setattr(courante, champ, valeur)
    courante.version += 1
    courante.device_id = contexte.device_id
    valider(courante)
    courante.save()
    journaliser_ligne(
        "update",
        courante,
        contexte,
        version=courante.version,
        champs=sorted(donnees),
        **details,
    )
    return courante


def modifier_ligne(ligne, donnees, contexte):
    with transaction.atomic():
        courante = verrouiller(ligne)
        verifier_version(courante, donnees["version"])
        return enregistrer_modification(courante, donnees, contexte)


def supprimer_ligne(ligne, contexte):
    with transaction.atomic():
        courante = verrouiller(ligne)
        courante.soft_delete(device_id=contexte.device_id)
        journaliser_ligne("delete", courante, contexte, version=courante.version)
    return courante
