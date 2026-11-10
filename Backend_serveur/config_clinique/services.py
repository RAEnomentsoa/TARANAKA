import json
from pathlib import Path

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Max
from django.utils import timezone
from jsonschema import Draft202012Validator
from rest_framework.exceptions import ValidationError

from synchro.models import JournalAudit

from .models import ConfigurationClinique, StatutPublication, StatutValidation

SCHEMA = json.loads((Path(__file__).parent / "schema.json").read_text(encoding="utf-8"))
VALIDATEUR = Draft202012Validator(SCHEMA)
EXEMPLE = Path(__file__).parent / "exemples" / "config_clinique_exemple.json"
ESSAIS_NUMERO = 5


def config_active():
    """The published version with the highest number, or None."""
    return (
        ConfigurationClinique.objects.filter(statut=StatutPublication.PUBLIEE)
        .order_by("-version")
        .first()
    )


def valider_contenu(contenu):
    erreurs = sorted(VALIDATEUR.iter_errors(contenu), key=lambda e: list(e.path))
    if erreurs:
        raise ValidationError(
            {
                "contenu": [
                    f"{'/'.join(str(p) for p in erreur.path) or '(racine)'} : {erreur.message}"
                    for erreur in erreurs[:20]
                ]
            }
        )


def creer_version(donnees, user=None, ip=None):
    valider_contenu(donnees["contenu"])
    for _ in range(ESSAIS_NUMERO):
        try:
            with transaction.atomic():
                dernier = ConfigurationClinique.objects.aggregate(n=Max("version"))["n"]
                config = ConfigurationClinique.objects.create(
                    version=(dernier or 0) + 1,
                    cree_par=user,
                    **donnees,
                )
                _journaliser("config_creee", config, user, ip)
                return config
        except IntegrityError:
            continue
    raise ValidationError({"version": ["Impossible d'attribuer un numéro. Réessayez."]})


def modifier_brouillon(config, donnees, user=None, ip=None):
    with transaction.atomic():
        config = ConfigurationClinique.objects.select_for_update().get(pk=config.pk)
        if config.statut != StatutPublication.BROUILLON:
            raise ValidationError(
                {"statut": ["Une version publiée ne change plus : créez une nouvelle version."]}
            )
        if "contenu" in donnees:
            valider_contenu(donnees["contenu"])
        for champ, valeur in donnees.items():
            setattr(config, champ, valeur)
        config.save()
        _journaliser("config_modifiee", config, user, ip, champs=sorted(donnees))
    return config


def publier(config, user=None, ip=None):
    with transaction.atomic():
        config = ConfigurationClinique.objects.select_for_update().get(pk=config.pk)
        if config.statut != StatutPublication.BROUILLON:
            raise ValidationError({"statut": ["Seul un brouillon peut être publié."]})
        valider_contenu(config.contenu)
        if settings.TARANAKA_CONFIG_VALIDEE_OBLIGATOIRE and not est_validee(config):
            raise ValidationError(
                {
                    "statut_validation": [
                        "Cette version n'est pas validée par écrit : "
                        "renseignez valide_par, reference_validation et date_validation."
                    ]
                }
            )
        config.statut = StatutPublication.PUBLIEE
        config.publiee_le = timezone.now()
        config.save(update_fields=["statut", "publiee_le", "updated_at"])
        _journaliser("config_publiee", config, user, ip)
    return config


def retirer(config, user=None, ip=None):
    with transaction.atomic():
        config = ConfigurationClinique.objects.select_for_update().get(pk=config.pk)
        if config.statut != StatutPublication.PUBLIEE:
            raise ValidationError({"statut": ["Seule une version publiée peut être retirée."]})
        config.statut = StatutPublication.RETIREE
        config.save(update_fields=["statut", "updated_at"])
        _journaliser("config_retiree", config, user, ip)
    return config


def est_validee(config):
    return (
        config.statut_validation == StatutValidation.VALIDEE
        and bool(config.valide_par)
        and bool(config.reference_validation)
        and config.date_validation is not None
    )


def _journaliser(action, config, user, ip, **details):
    JournalAudit.objects.create(
        user=user,
        action=action,
        table_nom=ConfigurationClinique._meta.db_table,
        details={"ip": ip, "version": config.version, **details},
    )
