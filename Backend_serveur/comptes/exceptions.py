from rest_framework import status
from rest_framework.exceptions import APIException, AuthenticationFailed
from rest_framework.views import exception_handler


def gestionnaire_exceptions(exc, context):
    """Give every token error a French message: simplejwt's translation is partial."""
    if isinstance(exc, AuthenticationFailed):
        codes = exc.get_codes()
        code = codes.get("code") if isinstance(codes, dict) else codes
        exc.detail = {
            "detail": "Session invalide ou expirée. Veuillez vous reconnecter.",
            "code": code,
        }
    return exception_handler(exc, context)


class ErreurCompte(APIException):
    """Keep the body as given, so that secondes_restantes stays a number."""

    def __init__(self, message, code, **extra):
        self.detail = {"detail": message, "code": code, **extra}


class IdentifiantsIncorrects(ErreurCompte):
    status_code = status.HTTP_401_UNAUTHORIZED

    def __init__(self):
        super().__init__("Identifiant ou PIN incorrect", "identifiants_incorrects")


class CompteBloque(ErreurCompte):
    status_code = status.HTTP_423_LOCKED

    def __init__(self, message, secondes_restantes):
        super().__init__(
            message,
            "compte_bloque",
            secondes_restantes=secondes_restantes,
        )


class ProfilInconnu(ErreurCompte):
    status_code = status.HTTP_403_FORBIDDEN

    def __init__(self):
        super().__init__(
            "Votre profil n'a pas accès à l'application.",
            "profil_inconnu",
        )


class AncienPinIncorrect(ErreurCompte):
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self):
        super().__init__("L'ancien PIN est incorrect.", "ancien_pin_incorrect")


class PinNonModifiable(ErreurCompte):
    status_code = status.HTTP_403_FORBIDDEN

    def __init__(self):
        super().__init__(
            "Les comptes d'administration utilisent un mot de passe, pas un PIN.",
            "pin_non_modifiable",
        )
