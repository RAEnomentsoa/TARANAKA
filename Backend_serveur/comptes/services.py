import math
from datetime import timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)
from rest_framework_simplejwt.tokens import RefreshToken

from synchro.models import JournalAudit
from synchro.services import journaliser_ligne

from .exceptions import (
    AncienPinIncorrect,
    CompteBloque,
    IdentifiantsIncorrects,
    PinNonModifiable,
    ProfilInconnu,
)
from .models import CodeProfile, User

DUREES_BLOCAGE = {
    5: timedelta(minutes=15),
    10: timedelta(hours=1),
}
SEUIL_BLOCAGE_ADMIN = 15
MESSAGE_IDENTIFIANT_UTILISE = "Cet identifiant est déjà utilisé."


def beneficiaires_visibles(user):
    """The women this user may link a row to."""
    beneficiaires = User.objects.filter(profile__code=CodeProfile.BENEFICIAIRE)
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return beneficiaires
    if code == CodeProfile.BENEFICIAIRE:
        return beneficiaires.filter(pk=user.pk)
    # Guard against filter(region_id=None), which would match every empty region.
    if code == CodeProfile.ASC and user.region_id is not None:
        return beneficiaires.filter(region_id=user.region_id)
    return User.objects.none()


def asc_visibles(user):
    """The ASCs this user may name on a row: an ASC can only name themself."""
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return User.objects.filter(profile__code=CodeProfile.ASC)
    if code == CodeProfile.ASC:
        return User.objects.filter(pk=user.pk)
    return User.objects.none()


def comptes_visibles(user):
    if user.profile.code == CodeProfile.ADMIN:
        return User.objects.all()
    return beneficiaires_visibles(user)


def creer_compte(donnees, contexte):
    donnees = dict(donnees)
    pin = donnees.pop("pin")
    user = User(**donnees)
    user.set_password(pin)
    return _enregistrer_compte(
        user,
        "create",
        contexte,
        force_insert=True,
        profil=user.profile.code,
    )


def modifier_compte(user, donnees, contexte):
    with transaction.atomic():
        courant = User.objects.select_for_update(of=("self",)).get(pk=user.pk)
        for champ, valeur in donnees.items():
            setattr(courant, champ, valeur)
        return _enregistrer_compte(courant, "update", contexte, champs=sorted(donnees))


def _enregistrer_compte(user, action, contexte, force_insert=False, **details):
    try:
        with transaction.atomic():
            user.save(force_insert=force_insert)
    except IntegrityError as erreur:
        raise ValidationError(
            {"identifiant": [MESSAGE_IDENTIFIANT_UTILISE]}
        ) from erreur
    journaliser_ligne(action, user, contexte, **details)
    return user


def est_bloque(user):
    if user.tentatives_echouees >= SEUIL_BLOCAGE_ADMIN:
        return True
    return bool(user.bloque_jusqu_a and user.bloque_jusqu_a > timezone.now())


def connecter(identifiant, pin, ip):
    """Check the PIN and return the user with a new refresh token."""
    # The errors are raised outside the transaction, so that the failed
    # attempt and the audit line are kept.
    with transaction.atomic():
        user = (
            User.objects.select_for_update(of=("self",))
            .filter(identifiant=identifiant)
            .first()
        )
        erreur = _verifier_connexion(user, identifiant, pin, ip)
    if erreur:
        raise erreur
    return user, RefreshToken.for_user(user)


def changer_pin(user, ancien_pin, nouveau_pin, ip):
    """Change the PIN, revoke the user's sessions and return a new refresh token."""
    if user.is_staff:
        raise PinNonModifiable()
    with transaction.atomic():
        user = User.objects.select_for_update(of=("self",)).get(pk=user.pk)
        erreur = _verifier_ancien_pin(user, ancien_pin, ip)
        if not erreur:
            user.set_password(nouveau_pin)
            user.tentatives_echouees = 0
            user.bloque_jusqu_a = None
            user.save(
                update_fields=[
                    "password",
                    "tentatives_echouees",
                    "bloque_jusqu_a",
                    "updated_at",
                ]
            )
            _revoquer_tokens(user)
            journaliser("changer_pin_succes", user, ip)
    if erreur:
        raise erreur
    return RefreshToken.for_user(user)


def deconnecter(refresh):
    try:
        RefreshToken(refresh).blacklist()
    except TokenError as erreur:
        raise InvalidToken(erreur.args[0]) from erreur


def debloquer(user, admin, ip):
    user.tentatives_echouees = 0
    user.bloque_jusqu_a = None
    user.save(update_fields=["tentatives_echouees", "bloque_jusqu_a", "updated_at"])
    journaliser("compte_debloque", admin, ip, cible=user)


def journaliser(action, user, ip, cible=None, **details):
    ligne = cible or user
    JournalAudit.objects.create(
        user=user,
        action=action,
        table_nom="utilisateur" if ligne else "",
        ligne_id=ligne.pk if ligne else None,
        details={"ip": ip, **details},
    )


def _verifier_connexion(user, identifiant, pin, ip):
    if user is None or not user.is_active:
        # Hash anyway, so the response time doesn't reveal if the account exists.
        User().set_password(pin)
        journaliser(
            "login_echec",
            None,
            ip,
            identifiant=identifiant,
            motif="identifiant_inconnu" if user is None else "compte_inactif",
        )
        return IdentifiantsIncorrects()

    if est_bloque(user):
        journaliser("login_bloque", user, ip)
        return _erreur_blocage(user)

    if not user.check_password(pin):
        _enregistrer_echec(user)
        journaliser("login_echec", user, ip, tentatives=user.tentatives_echouees)
        return _erreur_blocage(user) if est_bloque(user) else IdentifiantsIncorrects()

    user.tentatives_echouees = 0
    user.bloque_jusqu_a = None
    user.last_login = timezone.now()
    user.save(update_fields=["tentatives_echouees", "bloque_jusqu_a", "last_login"])

    if user.profile.code not in CodeProfile.values:
        journaliser("login_refuse", user, ip, profil=user.profile.code)
        return ProfilInconnu()

    journaliser("login_succes", user, ip)
    return None


def _verifier_ancien_pin(user, ancien_pin, ip):
    if est_bloque(user):
        journaliser("changer_pin_bloque", user, ip)
        return _erreur_blocage(user)
    if user.check_password(ancien_pin):
        return None
    _enregistrer_echec(user)
    journaliser("changer_pin_echec", user, ip, tentatives=user.tentatives_echouees)
    return _erreur_blocage(user) if est_bloque(user) else AncienPinIncorrect()


def _enregistrer_echec(user):
    """The counter keeps growing after a block ends: only a success resets it."""
    user.tentatives_echouees += 1
    duree = DUREES_BLOCAGE.get(user.tentatives_echouees)
    user.bloque_jusqu_a = timezone.now() + duree if duree else None
    user.save(update_fields=["tentatives_echouees", "bloque_jusqu_a"])


def _erreur_blocage(user):
    if user.tentatives_echouees >= SEUIL_BLOCAGE_ADMIN:
        return CompteBloque(
            "Compte bloqué. Contactez un administrateur pour le débloquer.",
            secondes_restantes=None,
        )
    restant = (user.bloque_jusqu_a - timezone.now()).total_seconds()
    return CompteBloque(
        f"Compte bloqué. Réessayez dans {math.ceil(restant / 60)} minute(s).",
        secondes_restantes=math.ceil(restant),
    )


def _revoquer_tokens(user):
    tokens = OutstandingToken.objects.filter(user=user, blacklistedtoken__isnull=True)
    BlacklistedToken.objects.bulk_create(
        [BlacklistedToken(token=token) for token in tokens],
        ignore_conflicts=True,
    )
