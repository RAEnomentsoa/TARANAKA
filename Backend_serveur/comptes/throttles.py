from rest_framework.throttling import AnonRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    scope = "login"


class DemandeAccesRateThrottle(AnonRateThrottle):
    """The access request is public: a few per hour and per address."""

    scope = "demande_acces"


class InscriptionRateThrottle(AnonRateThrottle):
    """Public beneficiary registration (D16). Several women may register on
    the same village connection: more generous than the access request."""

    scope = "inscription_beneficiaire"
