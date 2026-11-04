from django.conf import settings
from rest_framework.permissions import BasePermission

from .models import CodeProfile

# Profiles that may read individual health records. The supervisor is left out
# on purpose: spec §10 gives them aggregated, anonymous statistics only.
PROFILS_DOSSIERS = (
    CodeProfile.BENEFICIAIRE,
    CodeProfile.ASC,
    CodeProfile.AGENT_CSB,
    CodeProfile.ADMIN,
)


# Health workers who may see a colleague's name and phone (to call the ASC of
# a referral that didn't arrive, or the sender of a conflict).
PROFILS_CONTACT_AGENT = (
    CodeProfile.ASC,
    CodeProfile.AGENT_CSB,
    CodeProfile.ADMIN,
)


class ProfilRequis(BasePermission):
    """Allow only the logged-in users whose profile code is listed in codes."""

    codes = ()
    message = "Votre profil ne permet pas d'accéder à cette ressource."

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated and user.profile.code in self.codes):
            return False
        if totp_a_configurer(request, view):
            self.message = MESSAGE_TOTP_A_CONFIGURER
            return False
        return True


MESSAGE_TOTP_A_CONFIGURER = (
    "Activez la double authentification (/api/auth/2fa/) avant d'utiliser ce compte."
)


def totp_a_configurer(request, view):
    """A token issued before two-factor login was set up opens only the views
    marked `autorise_sans_totp` (2FA setup, /me/)."""
    if getattr(view, "autorise_sans_totp", False):
        return False
    jeton = request.auth
    if jeton is None or not hasattr(jeton, "get") or not jeton.get("totp_a_configurer"):
        return False
    return settings.TARANAKA_TOTP_OBLIGATOIRE and not request.user.totp_active


class ProfilReconnu(ProfilRequis):
    """Default permission: any logged-in user with a profile known to the API."""

    codes = tuple(CodeProfile.values)


class IsBeneficiaire(ProfilRequis):
    codes = (CodeProfile.BENEFICIAIRE,)


class IsASC(ProfilRequis):
    codes = (CodeProfile.ASC,)


class IsAgentCSB(ProfilRequis):
    codes = (CodeProfile.AGENT_CSB,)


class IsAdmin(ProfilRequis):
    codes = (CodeProfile.ADMIN,)


class IsSuperviseurOuAdmin(ProfilRequis):
    codes = (CodeProfile.SUPERVISEUR, CodeProfile.ADMIN)


class AccesParAction(ProfilRequis):
    """Each ViewSet lists the profiles allowed per action; any other action is refused."""

    def has_permission(self, request, view):
        if view.action in (None, "metadata"):
            # Unsupported method: let DRF answer 405 to any known profile.
            self.codes = tuple(CodeProfile.values)
        else:
            self.codes = view.profils_par_action.get(view.action, ())
        return super().has_permission(request, view)


def acces(lecture=(), ecriture=(), **actions):
    """Build profils_par_action; actions overrides one action, such as create=(...)."""
    return {
        "list": lecture,
        "retrieve": lecture,
        "create": ecriture,
        "update": ecriture,
        "partial_update": ecriture,
        "destroy": ecriture,
        **actions,
    }


def profil_requis(*codes):
    """Allow several profiles, for example profil_requis("asc", "agent_csb")."""
    return type("ProfilRequisMultiple", (ProfilRequis,), {"codes": codes})
