import math
from datetime import timedelta

from django.conf import settings
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

from . import totp
from .exceptions import (
    AncienPinIncorrect,
    CompteBloque,
    ErreurTotp,
    IdentifiantsIncorrects,
    PinIncorrect,
    PinNonModifiable,
    ProfilInconnu,
    TotpInvalide,
    TotpNonDisponible,
    TotpObligatoire,
    TotpRequis,
)
from .models import PROFILS_TOTP, CodeProfile, User

DUREES_BLOCAGE = {
    5: timedelta(minutes=15),
    10: timedelta(hours=1),
}
SEUIL_BLOCAGE_ADMIN = 15
MESSAGE_IDENTIFIANT_UTILISE = "Cet identifiant est déjà utilisé."


def beneficiaires_visibles(user):
    """The women this user may link a row to."""
    # An erased account can't be linked to or listed any more.
    beneficiaires = User.objects.filter(
        profile__code=CodeProfile.BENEFICIAIRE,
        efface_le__isnull=True,
    )
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
    code = user.profile.code
    if code == CodeProfile.ADMIN:
        return User.objects.all()
    if code == CodeProfile.SUPERVISEUR:
        # The supervisor manages the ASC accounts of their zone (spec §2, §8).
        ascs = User.objects.filter(profile__code=CodeProfile.ASC)
        if user.region_id is None:
            return ascs
        return ascs.filter(region_id=user.region_id)
    return beneficiaires_visibles(user)


def reinitialiser_pin(cible, nouveau_pin, contexte):
    """PIN forgotten in agent mode: the supervisor sets a new one (spec §8).

    The account is unblocked and every session is closed. The phone gets its
    synced data back with /api/sync/pull/ after the next login.
    """
    if cible.is_staff:
        raise PinNonModifiable()
    with transaction.atomic():
        cible = User.objects.select_for_update(of=("self",)).get(pk=cible.pk)
        cible.set_password(nouveau_pin)
        cible.tentatives_echouees = 0
        cible.bloque_jusqu_a = None
        cible.save(
            update_fields=[
                "password",
                "tentatives_echouees",
                "bloque_jusqu_a",
                "updated_at",
            ]
        )
        _revoquer_tokens(cible)
        journaliser(
            "reinitialiser_pin",
            contexte.user,
            contexte.ip,
            cible=cible,
            device_id=contexte.device_id,
        )
    return cible


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


def connecter(identifiant, pin, ip, device_id="", code_totp=None):
    """Check the PIN (and the TOTP code if the account uses one).

    Return the user with a new refresh token. A web account that must use
    two-factor login but hasn't set it up gets a token marked
    `totp_a_configurer`: it only opens the /api/auth/2fa/ endpoints.
    """
    # The errors are raised outside the transaction, so that the failed
    # attempt and the audit line are kept.
    with transaction.atomic():
        user = (
            User.objects.select_for_update(of=("self",))
            .filter(identifiant=identifiant)
            .first()
        )
        erreur = _verifier_connexion(user, identifiant, pin, ip, device_id, code_totp)
    if erreur:
        raise erreur
    return user, jetons(user)


def jetons(user):
    refresh = RefreshToken.for_user(user)
    if totp_a_configurer(user):
        refresh["totp_a_configurer"] = True
    return refresh


def totp_requis_pour(user):
    return user.profile.code in PROFILS_TOTP


def totp_a_configurer(user):
    return (
        settings.TARANAKA_TOTP_OBLIGATOIRE
        and totp_requis_pour(user)
        and not user.totp_active
    )


def preparer_totp(user, ip):
    """New secret for the authenticator app. Active only once a code is checked."""
    if not totp_requis_pour(user):
        raise TotpNonDisponible()
    with transaction.atomic():
        user = User.objects.select_for_update(of=("self",)).get(pk=user.pk)
        if user.totp_active:
            raise ErreurTotp(
                "La double authentification est déjà active.",
                "totp_deja_actif",
            )
        user.totp_secret = totp.nouveau_secret()
        user.save(update_fields=["totp_secret", "updated_at"])
        journaliser("totp_preparation", user, ip)
    return user.totp_secret, totp.uri_provisionnement(user.totp_secret, user.identifiant)


def activer_totp(user, code, ip):
    """Check a first code, turn two-factor login on, and close the other sessions."""
    if not totp_requis_pour(user):
        raise TotpNonDisponible()
    with transaction.atomic():
        user = User.objects.select_for_update(of=("self",)).get(pk=user.pk)
        if user.totp_active:
            raise ErreurTotp(
                "La double authentification est déjà active.",
                "totp_deja_actif",
            )
        if not user.totp_secret:
            raise ErreurTotp(
                "Appelez d'abord /api/auth/2fa/setup/.",
                "totp_non_prepare",
            )
        pas = totp.verifier(user.totp_secret, code)
        if pas is None:
            raise ErreurTotp("Code d'authentification incorrect.", "totp_invalide")
        user.totp_active = True
        user.totp_dernier_pas = pas
        user.save(update_fields=["totp_active", "totp_dernier_pas", "updated_at"])
        _revoquer_tokens(user)
        journaliser("totp_active", user, ip)
    return jetons(user)


def desactiver_totp(user, pin, code, ip):
    if settings.TARANAKA_TOTP_OBLIGATOIRE and totp_requis_pour(user):
        raise TotpObligatoire()
    with transaction.atomic():
        user = User.objects.select_for_update(of=("self",)).get(pk=user.pk)
        if not user.totp_active:
            raise ErreurTotp(
                "La double authentification n'est pas active.",
                "totp_inactif",
            )
        erreur = None
        if est_bloque(user):
            erreur = _erreur_blocage(user)
        else:
            pas = (
                totp.verifier(user.totp_secret, code, user.totp_dernier_pas)
                if user.check_password(pin)
                else None
            )
            if pas is None:
                _enregistrer_echec(user)
                journaliser("totp_desactivation_echec", user, ip)
                erreur = _erreur_blocage(user) if est_bloque(user) else TotpInvalide()
            else:
                _effacer_totp(user)
                journaliser("totp_desactive", user, ip)
    if erreur:
        raise erreur


def reinitialiser_totp(cible, contexte):
    """Lost phone: an admin turns two-factor login off; the person sets it up again."""
    with transaction.atomic():
        cible = User.objects.select_for_update(of=("self",)).get(pk=cible.pk)
        _effacer_totp(cible)
        _revoquer_tokens(cible)
        journaliser(
            "totp_reinitialise",
            contexte.user,
            contexte.ip,
            cible=cible,
            device_id=contexte.device_id,
        )
    return cible


def _effacer_totp(user):
    user.totp_secret = ""
    user.totp_active = False
    user.totp_dernier_pas = None
    user.save(
        update_fields=["totp_secret", "totp_active", "totp_dernier_pas", "updated_at"]
    )


def verifier_pin_pour(user, pin, ip, action):
    """Confirm a sensitive action with the PIN. A wrong PIN counts as a failure."""
    with transaction.atomic():
        user = User.objects.select_for_update(of=("self",)).get(pk=user.pk)
        if est_bloque(user):
            erreur = _erreur_blocage(user)
        elif user.check_password(pin):
            return
        else:
            _enregistrer_echec(user)
            journaliser(f"{action}_echec", user, ip, tentatives=user.tentatives_echouees)
            erreur = _erreur_blocage(user) if est_bloque(user) else PinIncorrect()
    raise erreur


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


def _verifier_connexion(user, identifiant, pin, ip, device_id="", code_totp=None):
    if user is None or not user.is_active:
        # Hash anyway, so the response time doesn't reveal if the account exists.
        User().set_password(pin)
        journaliser(
            "login_echec",
            None,
            ip,
            identifiant=identifiant,
            motif="identifiant_inconnu" if user is None else "compte_inactif",
            device_id=device_id,
        )
        return IdentifiantsIncorrects()

    if est_bloque(user):
        journaliser("login_bloque", user, ip, device_id=device_id)
        return _erreur_blocage(user)

    if not user.check_password(pin):
        _enregistrer_echec(user)
        journaliser(
            "login_echec",
            user,
            ip,
            tentatives=user.tentatives_echouees,
            device_id=device_id,
        )
        return _erreur_blocage(user) if est_bloque(user) else IdentifiantsIncorrects()

    if user.totp_active:
        # The failure counter is only reset once the second factor is right too.
        if not code_totp:
            journaliser("login_totp_requis", user, ip, device_id=device_id)
            return TotpRequis()
        pas = totp.verifier(user.totp_secret, code_totp, user.totp_dernier_pas)
        if pas is None:
            _enregistrer_echec(user)
            journaliser(
                "login_echec",
                user,
                ip,
                motif="totp_invalide",
                tentatives=user.tentatives_echouees,
                device_id=device_id,
            )
            return _erreur_blocage(user) if est_bloque(user) else TotpInvalide()
        user.totp_dernier_pas = pas

    user.tentatives_echouees = 0
    user.bloque_jusqu_a = None
    user.last_login = timezone.now()
    user.save(
        update_fields=[
            "tentatives_echouees",
            "bloque_jusqu_a",
            "last_login",
            "totp_dernier_pas",
        ]
    )

    if user.profile.code not in CodeProfile.values:
        journaliser(
            "login_refuse",
            user,
            ip,
            profil=user.profile.code,
            device_id=device_id,
        )
        return ProfilInconnu()

    journaliser("login_succes", user, ip, device_id=device_id)
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
