"""Access requests for web accounts (D15).

A person asks from the login page; an admin approves or refuses. Nothing is
created in `utilisateur` before the approval, so a pending request opens no
access at all.
"""

from django.contrib.auth.hashers import make_password
from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from synchro.services import journaliser_ligne

from .models import (
    MESSAGE_CSB_OBLIGATOIRE,
    MESSAGE_IDENTIFIANT_UTILISE,
    CodeProfile,
    DemandeAcces,
    Profile,
    StatutDemande,
    User,
)

MESSAGE_DEMANDE_TRAITEE = "Cette demande a déjà été traitée."


def verifier_rattachement(profil, csb, region):
    """The centre of a nurse, the region of a supervisor. Return (csb, region)."""
    if profil == CodeProfile.AGENT_CSB:
        if csb is None:
            raise ValidationError({"csb_id": [MESSAGE_CSB_OBLIGATOIRE]})
        # The centre decides the region: they can't disagree.
        return csb, csb.region
    # A supervisor without a region is national / programme level (D1).
    return None, region


def identifiant_libre(identifiant, sauf_demande=None):
    """Free when no account and no pending request use it, whatever the case."""
    if User.objects.filter(identifiant__iexact=identifiant).exists():
        return False
    attente = DemandeAcces.objects.filter(
        identifiant__iexact=identifiant, statut=StatutDemande.EN_ATTENTE
    )
    if sauf_demande is not None:
        attente = attente.exclude(pk=sauf_demande.pk)
    return not attente.exists()


def creer_demande(donnees, contexte):
    donnees = dict(donnees)
    pin = donnees.pop("pin")
    if not identifiant_libre(donnees["identifiant"]):
        raise ValidationError({"identifiant": [MESSAGE_IDENTIFIANT_UTILISE]})
    donnees["csb"], donnees["region"] = verifier_rattachement(
        donnees["profil_demande"], donnees.get("csb"), donnees.get("region")
    )
    demande = DemandeAcces(pin_hash=make_password(pin), **donnees)
    try:
        with transaction.atomic():
            demande.save(force_insert=True)
    except IntegrityError as erreur:
        # Two requests sent at the same time with the same identifiant.
        raise ValidationError({"identifiant": [MESSAGE_IDENTIFIANT_UTILISE]}) from erreur
    journaliser_ligne(
        "demande_acces_creee", demande, contexte, profil=demande.profil_demande
    )
    return demande


def _verrouiller_en_attente(demande):
    demande = DemandeAcces.objects.select_for_update().get(pk=demande.pk)
    if demande.statut != StatutDemande.EN_ATTENTE:
        raise ValidationError({"statut": [MESSAGE_DEMANDE_TRAITEE]})
    return demande


def approuver(demande, corrections, contexte):
    """Create the account with the PIN chosen in the request.

    `corrections` may change the profile, centre or region the person asked
    for: the admin decides what the account can see.
    """
    with transaction.atomic():
        demande = _verrouiller_en_attente(demande)
        profil = corrections.get("profil_demande", demande.profil_demande)
        csb, region = verifier_rattachement(
            profil,
            corrections["csb"] if "csb" in corrections else demande.csb,
            corrections["region"] if "region" in corrections else demande.region,
        )
        if not identifiant_libre(demande.identifiant, sauf_demande=demande):
            raise ValidationError({"identifiant": [MESSAGE_IDENTIFIANT_UTILISE]})
        user = User(
            identifiant=demande.identifiant,
            nom=demande.nom,
            prenom=demande.prenom,
            email=demande.email,
            phone=demande.phone,
            profile=Profile.objects.get(code=profil),
            csb=csb,
            region=region,
            # Already hashed when the request was made.
            password=demande.pin_hash,
        )
        try:
            with transaction.atomic():
                user.save(force_insert=True)
        except IntegrityError as erreur:
            raise ValidationError({"identifiant": [MESSAGE_IDENTIFIANT_UTILISE]}) from erreur

        demande.profil_demande = profil
        demande.csb = csb
        demande.region = region
        demande.statut = StatutDemande.APPROUVEE
        demande.utilisateur = user
        demande.pin_hash = ""
        demande.traitee_par = contexte.user
        demande.date_traitement = timezone.now()
        demande.save()
        journaliser_ligne("create", user, contexte, profil=profil, demande_acces=str(demande.pk))
        journaliser_ligne("demande_acces_approuvee", demande, contexte, profil=profil)
    return demande


def refuser(demande, motif, contexte):
    with transaction.atomic():
        demande = _verrouiller_en_attente(demande)
        demande.statut = StatutDemande.REFUSEE
        demande.motif_refus = motif
        demande.pin_hash = ""
        demande.traitee_par = contexte.user
        demande.date_traitement = timezone.now()
        demande.save()
        journaliser_ligne("demande_acces_refusee", demande, contexte)
    return demande
