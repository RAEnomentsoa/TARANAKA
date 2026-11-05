from rest_framework import status
from rest_framework.exceptions import APIException

from comptes.exceptions import ErreurCompte

MESSAGE_ID_UTILISE = "Cet identifiant est déjà utilisé."


class ConflitVersion(APIException):
    """The view answers with the current row: see SyncViewSet.handle_exception."""

    status_code = status.HTTP_409_CONFLICT
    default_detail = "Cette ligne a été modifiée entre-temps. Nouvelle version jointe."
    default_code = "conflit_version"

    def __init__(self, ligne):
        super().__init__()
        self.ligne = ligne


class LigneProtegee(ErreurCompte):
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, message):
        super().__init__(message, "referencement_existant")
