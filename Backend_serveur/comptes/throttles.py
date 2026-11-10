from rest_framework.throttling import AnonRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    scope = "login"


class DemandeAccesRateThrottle(AnonRateThrottle):
    """The access request is public: a few per hour and per address."""

    scope = "demande_acces"
