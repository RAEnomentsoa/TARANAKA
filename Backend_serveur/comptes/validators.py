import re

from django.core.exceptions import ValidationError

FORMAT_PIN = re.compile(r"[0-9]{4,6}")


def valider_pin(valeur):
    if not FORMAT_PIN.fullmatch(valeur):
        raise ValidationError("Le PIN doit contenir de 4 à 6 chiffres.")
