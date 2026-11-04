from datetime import date
from decimal import Decimal

from django.test import override_settings
from rest_framework.test import APITestCase

from comptes.models import CodeProfile, Profile, User
from nutrition.models import Enfant, Mesure
from referencement.models import Referencement
from referentiel.models import CSB, Province, Region, TypeDangerGrossesse
from sante_femme.models import Grossesse


@override_settings(
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class BaseApiTest(APITestCase):
    """Two regions, each with its CSB, and one user per case."""

    def setUp(self):
        province = Province.objects.create(nom="Antananarivo")
        self.region = Region.objects.create(nom="Analamanga", province=province)
        self.autre_region = Region.objects.create(nom="Itasy", province=province)
        self.csb = CSB.objects.create(name="CSB A", region=self.region, tel="1")
        self.autre_csb = CSB.objects.create(
            name="CSB B",
            region=self.autre_region,
            tel="2",
        )
        self.type_danger = TypeDangerGrossesse.objects.create(description="Saignement")

        self.admin = self.compte("admin", CodeProfile.ADMIN)
        self.asc = self.compte("asc", CodeProfile.ASC, region=self.region)
        self.asc_meme_region = self.compte("asc2", CodeProfile.ASC, region=self.region)
        self.autre_asc = self.compte("asc3", CodeProfile.ASC, region=self.autre_region)
        self.asc_sans_region = self.compte("asc4", CodeProfile.ASC)
        self.femme = self.compte("femme", CodeProfile.BENEFICIAIRE, region=self.region)
        self.autre_femme = self.compte(
            "femme2",
            CodeProfile.BENEFICIAIRE,
            region=self.autre_region,
        )
        self.femme_sans_region = self.compte("femme3", CodeProfile.BENEFICIAIRE)
        self.agent = self.compte("agent", CodeProfile.AGENT_CSB, csb=self.csb)
        self.autre_agent = self.compte(
            "agent2",
            CodeProfile.AGENT_CSB,
            csb=self.autre_csb,
        )

    def compte(self, identifiant, code, **extra):
        return User.objects.create_user(
            identifiant,
            "1234",
            nom=identifiant.capitalize(),
            prenom="Test",
            profile=Profile.objects.get(code=code),
            **extra,
        )

    def comme(self, user):
        self.client.force_authenticate(user)

    def enfant(self, asc=None, **extra):
        valeurs = {
            "nom": "Hery",
            "asc": asc or self.asc,
            "region": self.region,
            "date_naissance": date(2025, 1, 1),
            "sexe": "M",
            **extra,
        }
        return Enfant.objects.create(**valeurs)

    def mesure(self, enfant, **extra):
        valeurs = {
            "enfant": enfant,
            "asc": enfant.asc,
            "date_mesure": date(2026, 1, 1),
            "poids_kg": Decimal("8.50"),
            "taille_cm": Decimal("70.0"),
            "position": "couche",
            "age_jour": 365,
            "age_mois": 11,
            "taille_corrigee_cm": Decimal("70.0"),
            "alerte": "vert",
            **extra,
        }
        return Mesure.objects.create(**valeurs)

    def grossesse(self, femme=None):
        return Grossesse.objects.create(
            user=femme or self.femme,
            ddr=date(2026, 1, 1),
            dpa=date(2026, 10, 8),
        )

    def referencement(self, code="R-TEST-1", csb=None, enfant=None, grossesse=None, **extra):
        valeurs = {
            "code_unique": code,
            "origine": "enfant" if enfant else "grossesse",
            "enfant": enfant,
            "grossesse": grossesse,
            "asc": self.asc,
            "csb": csb or self.csb,
            "priorite": "normale",
            "motif": "Test",
            **extra,
        }
        return Referencement.objects.create(**valeurs)

    def ids(self, reponse):
        """The ids of a paginated list, as text."""
        return {str(ligne["id"]) for ligne in reponse.data["results"]}
