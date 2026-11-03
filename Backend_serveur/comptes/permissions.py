from rest_framework.permissions import BasePermission

from .models import CodeProfile


class ProfilRequis(BasePermission):
    """Allow only the logged-in users whose profile code is listed in codes."""

    codes = ()
    message = "Votre profil ne permet pas d'accéder à cette ressource."

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user and user.is_authenticated and user.profile.code in self.codes
        )


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


def profil_requis(*codes):
    """Allow several profiles, for example profil_requis("asc", "agent_csb")."""
    return type("ProfilRequisMultiple", (ProfilRequis,), {"codes": codes})
