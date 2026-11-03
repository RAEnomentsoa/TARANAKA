# TARANAKA – API d'authentification

Ce document décrit les endpoints de connexion de l'API : ce qu'ils font, ce dont ils ont besoin, et ce qu'ils renvoient.

## Principes généraux

- **Adresse de base :** `/api/auth/`
- **Format :** toutes les requêtes et réponses sont en JSON (`Content-Type: application/json`).
- **Token d'accès :** quand un endpoint l'exige, envoyez l'en-tête `Authorization: Bearer <access>`.

| Token | Durée | Rôle |
|---|---|---|
| `access` | 1 heure | Authentifie chaque requête |
| `refresh` | 30 jours | Permet d'obtenir un nouveau `access` |

**Important : chaque `refresh` ne sert qu'une seule fois.** Chaque appel à `/refresh/` renvoie un nouveau `refresh`, que l'application doit enregistrer à la place de l'ancien. L'ancien est ensuite refusé.

Si la réponse se perd (mauvais réseau), l'ancien token ne fonctionne plus et l'utilisateur doit se reconnecter.

**Comportement conseillé pour l'application :**

1. Si une requête renvoie `401` avec `token_not_valid`, appelez `/refresh/` et réessayez la requête.
2. Si `/refresh/` renvoie aussi `401`, affichez l'écran de connexion.

Après 7 jours hors ligne, le `access` a expiré mais le `refresh` reste valable : l'application peut se resynchroniser sans demander le PIN. Après 30 jours sans connexion, le `refresh` a expiré et l'utilisateur doit se reconnecter.

## Résumé

| Méthode | Endpoint | Token d'accès requis | Rôle |
|---|---|---|---|
| POST | `/api/auth/login/` | Non | Se connecter avec l'identifiant et le PIN |
| POST | `/api/auth/refresh/` | Non | Obtenir de nouveaux tokens |
| POST | `/api/auth/logout/` | Non | Se déconnecter |
| GET | `/api/auth/me/` | Oui | Lire l'utilisateur connecté |
| POST | `/api/auth/changer-pin/` | Oui | Changer le PIN |

---

## POST `/api/auth/login/`

**Ce qu'il fait :** vérifie l'identifiant et le PIN, puis renvoie les tokens et les informations de l'utilisateur. Chaque tentative est enregistrée dans `journal_audit`.

**Ce dont il a besoin :**

```json
{
  "identifiant": "0341112233",
  "pin": "1234"
}
```

**Réponses :**

`200` – Connexion réussie. `region_id` vaut `null` si l'utilisateur n'a pas de région.

```json
{
  "access": "<access>",
  "refresh": "<refresh>",
  "utilisateur": {
    "id": "0aa5a6f7-ba14-4ff9-8303-37fef7fdd866",
    "nom": "Rabe",
    "prenom": "Soa",
    "profile": {
      "code": "asc",
      "libelle": "Agent de santé communautaire"
    },
    "region_id": null
  }
}
```

`400` – Champ manquant.

```json
{
  "identifiant": ["Ce champ est obligatoire."],
  "pin": ["Ce champ est obligatoire."]
}
```

`401` – Mauvais PIN, identifiant inconnu ou compte désactivé. Le message est le même dans les trois cas.

```json
{
  "detail": "Identifiant ou PIN incorrect",
  "code": "identifiants_incorrects"
}
```

`423` – Compte bloqué pour un temps limité. `secondes_restantes` indique le temps restant.

```json
{
  "detail": "Compte bloqué. Réessayez dans 15 minute(s).",
  "code": "compte_bloque",
  "secondes_restantes": 900
}
```

`423` – Compte bloqué jusqu'à l'intervention d'un administrateur. `secondes_restantes` vaut `null`.

```json
{
  "detail": "Compte bloqué. Contactez un administrateur pour le débloquer.",
  "code": "compte_bloque",
  "secondes_restantes": null
}
```

`403` – PIN correct, mais le profil de l'utilisateur n'est pas reconnu par l'API.

```json
{
  "detail": "Votre profil n'a pas accès à l'application.",
  "code": "profil_inconnu"
}
```

`429` – Plus de 10 requêtes par minute depuis la même adresse IP.

```json
{
  "detail": "Requête ralentie. Disponible à nouveau dans 60 secondes."
}
```

### Blocage après des échecs

| PIN incorrects d'affilée | Conséquence |
|---|---|
| 5 | Compte bloqué 15 minutes |
| 10 | Compte bloqué 1 heure |
| 15 | Compte bloqué jusqu'au déblocage par un administrateur |

- Seul un PIN correct remet le compteur à zéro. La fin d'un blocage ne le remet pas à zéro.
- Pendant un blocage, même le bon PIN est refusé, et les essais ne sont pas comptés.
- La réponse qui atteint le seuil renvoie déjà `423`.

---

## POST `/api/auth/refresh/`

**Ce qu'il fait :** remplace le `refresh` par un nouveau et renvoie un nouveau `access`. L'ancien `refresh` est mis sur liste noire.

**Ce dont il a besoin :**

```json
{
  "refresh": "<refresh>"
}
```

**Réponses :**

`200` – Enregistrez les **deux** tokens.

```json
{
  "access": "<access>",
  "refresh": "<refresh>"
}
```

`400` – Champ manquant.

```json
{
  "refresh": ["Ce champ est obligatoire."]
}
```

`401` – Token invalide, expiré ou déjà utilisé. L'utilisateur doit se reconnecter.

```json
{
  "detail": "Session invalide ou expirée. Veuillez vous reconnecter.",
  "code": "token_not_valid"
}
```

Si le compte a été désactivé, la réponse est aussi `401`, avec le code `no_active_account`.

---

## POST `/api/auth/logout/`

**Ce qu'il fait :** met le `refresh` sur liste noire pour qu'il ne puisse plus servir. Le token d'accès n'est pas demandé, car il a peut-être déjà expiré.

Le dernier `access` reste valable jusqu'à son expiration, au plus 1 heure : l'application doit donc le supprimer de son côté.

**Ce dont il a besoin :**

```json
{
  "refresh": "<refresh>"
}
```

**Réponses :**

`200`

```json
{
  "detail": "Déconnexion réussie."
}
```

`400` – Champ manquant.

```json
{
  "refresh": ["Ce champ est obligatoire."]
}
```

`401` – Token invalide, expiré ou déjà sur liste noire.

```json
{
  "detail": "Session invalide ou expirée. Veuillez vous reconnecter.",
  "code": "token_not_valid"
}
```

---

## GET `/api/auth/me/`

**Ce qu'il fait :** renvoie l'utilisateur connecté.

**Ce dont il a besoin :** l'en-tête `Authorization: Bearer <access>`. Pas de corps de requête.

**Réponses :**

`200`

```json
{
  "id": "0aa5a6f7-ba14-4ff9-8303-37fef7fdd866",
  "nom": "Rabe",
  "prenom": "Soa",
  "profile": {
    "code": "asc",
    "libelle": "Agent de santé communautaire"
  },
  "region_id": null
}
```

`401` – Aucun token envoyé.

```json
{
  "detail": "Informations d'authentification non fournies."
}
```

`401` – Token invalide ou expiré. Appelez `/refresh/`.

```json
{
  "detail": "Session invalide ou expirée. Veuillez vous reconnecter.",
  "code": "token_not_valid"
}
```

`403` – Le profil de l'utilisateur n'est pas reconnu par l'API.

```json
{
  "detail": "Votre profil ne permet pas d'accéder à cette ressource."
}
```

---

## POST `/api/auth/changer-pin/`

**Ce qu'il fait :** vérifie l'ancien PIN, enregistre le nouveau, puis ferme toutes les sessions de l'utilisateur sur tous ses téléphones. Il renvoie de nouveaux tokens pour que le téléphone actuel reste connecté.

Un `access` déjà émis sur un autre téléphone reste valable jusqu'à son expiration, au plus 1 heure.

**Ce dont il a besoin :** l'en-tête `Authorization: Bearer <access>`, et :

```json
{
  "ancien_pin": "1234",
  "nouveau_pin": "5678"
}
```

Le nouveau PIN doit contenir de 4 à 6 chiffres.

**Réponses :**

`200` – Remplacez les **deux** tokens enregistrés.

```json
{
  "detail": "PIN modifié.",
  "access": "<access>",
  "refresh": "<refresh>"
}
```

`400` – Champ manquant ou nouveau PIN au mauvais format. Cet essai ne compte pas comme un échec.

```json
{
  "nouveau_pin": ["Le PIN doit contenir de 4 à 6 chiffres."]
}
```

`400` – Ancien PIN incorrect. **Cet essai compte dans les échecs**, comme à la connexion.

```json
{
  "detail": "L'ancien PIN est incorrect.",
  "code": "ancien_pin_incorrect"
}
```

`423` – Compte bloqué. Même format que pour `/login/`.

`401` – Token absent, invalide ou expiré. Même format que pour `/me/`.

`403` – Les comptes d'administration utilisent un mot de passe et ne peuvent pas passer par cet endpoint.

```json
{
  "detail": "Les comptes d'administration utilisent un mot de passe, pas un PIN.",
  "code": "pin_non_modifiable"
}
```

---

## Profils

| `code` | `libelle` |
|---|---|
| `beneficiaire` | Bénéficiaire |
| `asc` | Agent de santé communautaire |
| `agent_csb` | Agent de CSB |
| `admin` | Administrateur |

Utilisez `code` dans la logique de l'application, et `libelle` pour l'affichage.

## Créer un compte de test

Il n'existe pas encore d'endpoint pour créer un compte. Sur le serveur de développement, lancez depuis le dossier `Backend_serveur` :

```
python manage.py shell -c "from comptes.models import Profile, User; User.objects.create_user('0341112233', '1234', nom='Rabe', prenom='Soa', profile=Profile.objects.get(code='beneficiaire'))"
```

Remplacez `beneficiaire` par le code du profil voulu.
