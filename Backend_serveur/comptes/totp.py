"""TOTP (RFC 6238, HMAC-SHA1, 30 s, 6 digits), with the standard library only.

Compatible with the usual authenticator apps (Google Authenticator, FreeOTP,
Aegis…). A code is accepted one step before or after the current one, to
allow for a phone clock that is a little off, and never twice.
"""

import base64
import hashlib
import hmac
import secrets
import struct
import time
from urllib.parse import quote, urlencode

PAS_SECONDES = 30
CHIFFRES = 6
FENETRE = 1
EMETTEUR = "TARANAKA"


def nouveau_secret():
    """160 random bits, base32 without padding (what the apps expect)."""
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def _cle(secret):
    secret = secret.upper()
    return base64.b32decode(secret + "=" * (-len(secret) % 8))


def code_au_pas(cle, pas, chiffres=CHIFFRES):
    """HOTP (RFC 4226) of a raw key at a counter value."""
    empreinte = hmac.new(cle, struct.pack(">Q", pas), hashlib.sha1).digest()
    decalage = empreinte[-1] & 0x0F
    valeur = struct.unpack(">I", empreinte[decalage : decalage + 4])[0] & 0x7FFFFFFF
    return str(valeur % 10**chiffres).zfill(chiffres)


def pas_courant(instant=None):
    return int((time.time() if instant is None else instant) // PAS_SECONDES)


def verifier(secret, code, dernier_pas=None, instant=None):
    """Return the time step the code matches, or None.

    A step at or before `dernier_pas` is refused, so a code can't be replayed.
    """
    code = (code or "").strip().replace(" ", "")
    if not code.isdigit() or len(code) != CHIFFRES:
        return None
    cle = _cle(secret)
    courant = pas_courant(instant)
    for pas in range(courant - FENETRE, courant + FENETRE + 1):
        if dernier_pas is not None and pas <= dernier_pas:
            continue
        if hmac.compare_digest(code_au_pas(cle, pas), code):
            return pas
    return None


def uri_provisionnement(secret, identifiant):
    """otpauth:// URI, to show as a QR code in the web dashboard."""
    libelle = quote(f"{EMETTEUR}:{identifiant}")
    parametres = urlencode(
        {"secret": secret, "issuer": EMETTEUR, "digits": CHIFFRES, "period": PAS_SECONDES}
    )
    return f"otpauth://totp/{libelle}?{parametres}"
