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

`200` – Connexion réussie. `region_id` vaut `null` si l'utilisateur n'a pas de région, et `csb_id` vaut `null` sauf pour un agent de CSB.

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
    "region_id": null,
    "csb_id": null
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
  "region_id": null,
  "csb_id": null
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

---

# TARANAKA – API principale

**Adresse de base :** `/api/`. Tous ces endpoints exigent l'en-tête `Authorization: Bearer <access>`.

**Documentation à tester :** `/api/docs/` (Swagger) et `/api/schema/` (OpenAPI). Elles sont générées depuis le code. Elles sont ouvertes quand `DEBUG=True`. Sinon, seuls les comptes staff connectés à `/admin/` y ont accès. La page Swagger charge ses fichiers depuis Internet.

## Résumé

| Endpoint | Méthodes | Rôle |
|---|---|---|
| `/api/profiles/` | GET, POST, PUT, PATCH | Comptes utilisateurs |
| `/api/profile-types/` | GET | Liste des profils |
| `/api/provinces/`, `/api/regions/` | GET | Listes de référence |
| `/api/facilities/` | GET | Liste des CSB |
| `/api/danger-types/` | GET | Liste des signes de danger |
| `/api/cycles/` | GET, POST, PUT, PATCH, DELETE | Cycles menstruels |
| `/api/pregnancies/` | GET, POST, PUT, PATCH, DELETE | Grossesses |
| `/api/pregnancies/{id}/dangers/` | GET, POST, PUT, PATCH, DELETE | Signes de danger d'une grossesse |
| `/api/children/` | GET, POST, PUT, PATCH, DELETE | Enfants |
| `/api/children/{id}/measurements/` | GET, POST, PUT, PATCH, DELETE | Mesures d'un enfant |
| `/api/measurements/` | GET, POST, PUT, PATCH, DELETE | Toutes les mesures visibles |
| `/api/referrals/` | GET, POST, PUT, PATCH, DELETE | Référencements |
| `/api/referrals/{id}/status/` | POST | Changer le statut d'un référencement |

Un endpoint de détail ajoute `{id}/`, par exemple `/api/children/{id}/`. `PUT` remplace toute la ligne, `PATCH` seulement les champs envoyés.

## Qui peut faire quoi

| Profil | Enfants et mesures | Grossesses | Cycles | Référencements | Comptes |
|---|---|---|---|---|---|
| `beneficiaire` | Lecture de ses enfants (`mere` = elle) | Accès complet aux siennes | Accès complet aux siens | Lecture des siens et de ceux de ses enfants | Lecture de son compte |
| `asc` | Création et modification de ses enfants (`asc` = lui) | Lecture et modification de celles des bénéficiaires de sa région | Aucun accès | Création et lecture : ses enfants et les grossesses de sa région | Création de bénéficiaires, lecture de celles de sa région |
| `agent_csb` | Lecture de ceux liés à un référencement vers son CSB | Lecture de celles liées à un référencement vers son CSB, avec le nom de la femme | Aucun accès | Lecture de ceux envoyés à son CSB, changement du `status` | Aucun accès (voir `/api/auth/me/`) |
| `admin` | Tout | Tout | Tout | Tout | Tout |

- **`403`** : le profil n'a pas le droit de faire cette action.
- **`404`** : la ligne n'existe pas, a été supprimée, ou n'est pas accessible à cet utilisateur. La réponse ne révèle pas laquelle de ces trois situations s'applique.

## Règles des tables synchronisées

Elles s'appliquent à `cycles`, `pregnancies`, `dangers`, `children`, `measurements` et `referrals`.

**`id` :** le téléphone peut envoyer un UUID créé hors ligne. Sinon, le serveur en crée un.

**Renvoi d'une création :** si la réponse s'est perdue, renvoyez la même requête avec le même `id`. Si l'utilisateur voit cette ligne, le serveur répond `200` avec la ligne, sans rien changer ni créer. Sinon, il répond `400` :

```json
{ "id": ["Cet identifiant est déjà utilisé."] }
```

**`version` :** chaque `PUT` ou `PATCH` doit envoyer la `version` connue du téléphone. Une mise à jour réussie l'augmente de 1. Sans `version`, la réponse est `400` :

```json
{ "version": ["Ce champ est obligatoire."] }
```

Si la version ne correspond pas, la réponse est `409` avec la ligne actuelle, et rien n'est enregistré :

```json
{
  "detail": "Cette ligne a été modifiée entre-temps. Nouvelle version jointe.",
  "code": "conflit_version",
  "current": { "id": "4c09f399-823d-4c4d-9209-21464f87cc2d", "version": 2, "...": "..." }
}
```

**`DELETE` :** répond `204`. La ligne est masquée (suppression logique) et n'apparaît plus dans les listes ni les détails. `version` n'est pas demandée. Pour l'instant, un téléphone ne peut donc pas apprendre une suppression avec `updated_since` : ce sera le rôle de `/sync`.

**`X-Device-Id` :** envoyez l'identifiant du téléphone dans cet en-tête. Le serveur le copie dans `device_id` (100 caractères au plus).

**Champs gérés par le serveur :** `created_at`, `updated_at`, `device_id` et `deleted_at`. S'ils sont envoyés, ils sont ignorés.

**Journal :** chaque création, modification, suppression et changement de statut est écrit dans `journal_audit`.

## Listes

Toutes les listes sont paginées par 50 et triées du plus récent au plus ancien. Utilisez `?page=2` ou suivez `next`.

```json
{ "count": 51, "next": "http://serveur/api/children/?page=2", "previous": null, "results": [] }
```

| Endpoint | Filtres |
|---|---|
| Toutes les tables synchronisées | `updated_since` (date et heure ISO, lignes modifiées à ce moment ou après) |
| `/api/children/` | `region`, `asc`, `statut_prise_en_charge`, `search` (nom) |
| `/api/measurements/` et `/api/children/{id}/measurements/` | `date_min`, `date_max`, `alerte` |
| `/api/referrals/` | `status`, `priorite`, `csb`, `origine` |
| `/api/pregnancies/` | `danger_sans_referencement` (`true` ou `false`) |
| `/api/facilities/` | `region` |

Les filtres s'appliquent uniquement aux lignes que l'utilisateur a le droit de voir. Dans une date avec un fuseau horaire, encodez `+` en `%2B`.

---

## `/api/profiles/`

**Ce qu'il fait :** gère les comptes. Il n'y a pas de suppression : un admin désactive un compte avec `is_active`.

**Créer (ASC) :** `POST`. Le compte est toujours `beneficiaire`, dans la région de l'ASC. L'ASC doit donc avoir une région.

```json
{
  "identifiant": "0340000000",
  "nom": "Rasoa",
  "prenom": "Vola",
  "pin": "4321",
  "phone": "0340000000",
  "consentement": true
}
```

**Créer (admin) :** ajoutez `profile_code` (`beneficiaire`, `asc`, `agent_csb` ou `admin`). `region_id` est obligatoire pour une bénéficiaire et `csb_id` pour un agent de CSB. Un compte `admin` créé ici se connecte avec un PIN et n'a pas accès à `/admin/`.

**Modifier (admin seulement) :** `PUT` ou `PATCH`. Ces routes ne changent pas le PIN.

`201` – Le PIN n'est jamais renvoyé.

```json
{
  "id": "846ea2ed-d1ff-4f38-8930-5f1d3186f16e",
  "identifiant": "0340000000",
  "nom": "Rasoa",
  "prenom": "Vola",
  "email": "",
  "phone": "0340000000",
  "consentement": true,
  "profile": { "code": "beneficiaire", "libelle": "Bénéficiaire" },
  "region_id": 1,
  "csb_id": null,
  "is_active": true,
  "date_creation": "2026-11-04T05:12:15.330071Z",
  "updated_at": "2026-11-04T05:12:15.330079Z"
}
```

`403` – Un ASC essaie de créer un autre profil.

```json
{ "detail": "Un agent de santé communautaire ne peut créer que des bénéficiaires." }
```

`400` – Exemples.

```json
{ "csb_id": ["Le CSB est obligatoire pour un agent de CSB."] }
```

```json
{ "identifiant": ["Cet identifiant est déjà utilisé."] }
```

## Listes de référence (lecture seule)

Chaque liste a le même format paginé. Voici le contenu de `results`.

`GET /api/profile-types/`

```json
[{ "code": "asc", "libelle": "Agent de santé communautaire" }]
```

`GET /api/provinces/`

```json
[{ "id": 1, "nom": "Antananarivo" }]
```

`GET /api/regions/`

```json
[{ "id": 1, "nom": "Analamanga", "province_id": 1 }]
```

`GET /api/facilities/?region=1`

```json
[{ "id": 1, "name": "CSB A", "region_id": 1, "tel": "1" }]
```

`GET /api/danger-types/`

```json
[{ "id": 1, "description": "Saignement" }]
```

## `/api/cycles/`

**Ce qu'il fait :** gère l'historique menstruel. Les ASC et les agents de CSB n'y ont pas accès (`403`).

**Créer :** `POST`. Une bénéficiaire n'envoie pas `user_id`. Un admin doit l'envoyer.

```json
{
  "id": "c58fff37-2705-4278-9fb3-0ffc0ae0a78e",
  "date_debut": "2026-10-01",
  "date_fin": "2026-10-05",
  "intensite": "moyenne",
  "symptome": "Fatigue"
}
```

`201`

```json
{
  "id": "c58fff37-2705-4278-9fb3-0ffc0ae0a78e",
  "user_id": "016db879-1264-425f-873d-1ef748463800",
  "date_debut": "2026-10-01",
  "date_fin": "2026-10-05",
  "intensite": "moyenne",
  "symptome": "Fatigue",
  "duree_cycle": null,
  "duree_regle": null,
  "estimation_prochain": null,
  "version": 1,
  "created_at": "2026-11-04T05:12:15.365142Z",
  "updated_at": "2026-11-04T05:12:15.365153Z",
  "device_id": "tel-1",
  "deleted_at": null
}
```

## `/api/pregnancies/`

**Ce qu'il fait :** gère les grossesses. `femme` donne le nom de la femme.

**Créer :** `POST`. Une bénéficiaire n'envoie pas `user_id`. Un ASC doit envoyer une bénéficiaire de sa région. `user_id` ne peut plus changer ensuite.

```json
{
  "user_id": "016db879-1264-425f-873d-1ef748463800",
  "ddr": "2026-06-01",
  "dpa": "2027-03-08"
}
```

`201`

```json
{
  "id": "9662e08c-651e-4e35-88bb-2a895ac4de65",
  "user_id": "016db879-1264-425f-873d-1ef748463800",
  "femme": { "nom": "Rasoa", "prenom": "Vola" },
  "ddr": "2026-06-01",
  "dpa": "2027-03-08",
  "version": 1,
  "created_at": "2026-11-04T05:12:15.375125Z",
  "updated_at": "2026-11-04T05:12:15.375138Z",
  "device_id": "tel-1",
  "deleted_at": null
}
```

**Cas à traiter en priorité :** `GET /api/pregnancies/?danger_sans_referencement=true` liste les grossesses qui ont un signe de danger enregistré après leur dernier référencement, ou sans aucun référencement. Une grossesse sort de cette liste quand un référencement est créé.

**Supprimer :** les signes de danger sont masqués avec la grossesse. Une grossesse qui a un référencement ne peut pas être supprimée (`400`) :

```json
{
  "detail": "Cette grossesse a un référencement et ne peut pas être supprimée.",
  "code": "referencement_existant"
}
```

## `/api/pregnancies/{id}/dangers/`

**Ce qu'il fait :** enregistre un signe de danger. **Un signe de danger avec un type valide est toujours enregistré**, avec ou sans référencement.

| Qui enregistre | `csb_id` | Résultat |
|---|---|---|
| ASC | CSB existant | Signe enregistré, référencement `grossesse` de priorité `urgente` créé |
| ASC | Absent, `null` ou illisible | Signe enregistré, sans référencement, avec un avertissement |
| ASC | CSB inconnu | Signe enregistré, sans référencement, avec un avertissement |
| Bénéficiaire ou admin | Ignoré | Signe enregistré, sans référencement ni avertissement. Il apparaît pour les ASC de la région dans `danger_sans_referencement`. |

Seuls un `type_danger_grossesse_id` absent ou inconnu et une date illisible sont refusés (`400`), car le signe ne peut alors pas être enregistré. Si `date_signalement` est absente, le serveur met la date et l'heure actuelles.

**Créer :** `POST`

```json
{
  "type_danger_grossesse_id": 1,
  "date_signalement": "2026-11-04T08:30:00Z",
  "csb_id": 1
}
```

`201` – Référencement créé.

```json
{
  "id": "cf5c0470-abf0-416c-a587-d6ff31606dc6",
  "grossesse_id": "9662e08c-651e-4e35-88bb-2a895ac4de65",
  "type_danger_grossesse_id": 1,
  "date_signalement": "2026-11-04T08:30:00Z",
  "version": 1,
  "created_at": "2026-11-04T05:12:15.385379Z",
  "updated_at": "2026-11-04T05:12:15.385388Z",
  "device_id": "tel-1",
  "deleted_at": null,
  "referencement_id": "8e9c2d6c-ed34-4f3c-bb29-73531e8af4a7",
  "code_unique": "R-712d-1104-01",
  "avertissement": null
}
```

`201` – Sans CSB : affichez l'avertissement.

```json
{
  "id": "dc2681f6-58e5-4a73-b7b5-4fce99256920",
  "grossesse_id": "9662e08c-651e-4e35-88bb-2a895ac4de65",
  "type_danger_grossesse_id": 1,
  "date_signalement": "2026-11-04T09:00:00Z",
  "version": 1,
  "created_at": "2026-11-04T05:12:15.411468Z",
  "updated_at": "2026-11-04T05:12:15.411477Z",
  "device_id": "tel-1",
  "deleted_at": null,
  "referencement_id": null,
  "code_unique": null,
  "avertissement": "Référencement non créé : CSB manquant"
}
```

`referencement_id`, `code_unique` et `avertissement` n'apparaissent que dans la réponse `201`. Modifier ou supprimer un signe ne crée ni ne change aucun référencement.

## `/api/children/`

**Ce qu'il fait :** gère les enfants. Un ASC n'envoie pas `asc_id` : c'est lui. Un admin doit l'envoyer. `mere_id` doit être une bénéficiaire de la région de l'ASC. `grossesse_id` doit être une grossesse de cette mère.

**Créer :** `POST`

```json
{
  "nom": "Hery",
  "mere_id": "016db879-1264-425f-873d-1ef748463800",
  "region_id": 1,
  "date_naissance": "2025-01-15",
  "sexe": "M"
}
```

`201`

```json
{
  "id": "4c09f399-823d-4c4d-9209-21464f87cc2d",
  "nom": "Hery",
  "mere_id": "016db879-1264-425f-873d-1ef748463800",
  "asc_id": "712da08f-311e-437d-84e4-020c47329ef4",
  "grossesse_id": null,
  "region_id": 1,
  "date_naissance": "2025-01-15",
  "sexe": "M",
  "statut_prise_en_charge": "aucun",
  "version": 1,
  "created_at": "2026-11-04T05:12:15.426629Z",
  "updated_at": "2026-11-04T05:12:15.426637Z",
  "device_id": "tel-1",
  "deleted_at": null
}
```

**Modifier :** `PATCH`

```json
{ "nom": "Rivo", "version": 1 }
```

**Changer `date_naissance` :** le serveur recalcule toutes les mesures de l'enfant, dont la `version` augmente. Si une mesure devient invalide, rien n'est enregistré (`400`) :

```json
{ "date_naissance": ["Cette date de naissance rend une mesure déjà enregistrée invalide."] }
```

**Supprimer :** les mesures sont masquées avec l'enfant. Un enfant qui a un référencement ne peut pas être supprimé (`400`, même format que pour une grossesse).

## `/api/children/{id}/measurements/` et `/api/measurements/`

**Ce qu'il fait :** gère les mesures. Avec `/api/measurements/`, envoyez aussi `enfant_id`. Avec `/api/children/{id}/measurements/`, l'enfant vient de l'adresse. Une mesure ne peut pas changer d'enfant.

**Calculé par le serveur :** ces champs sont recalculés à chaque création et modification. Les valeurs envoyées sont ignorées.

| Champ | Calcul |
|---|---|
| `age_jour` | `date_mesure` – `date_naissance`, en jours |
| `age_mois` | `age_jour / 30.4375`, arrondi vers le bas |
| `taille_corrigee_cm` | Moins de 731 jours et `debout` : `taille_cm + 0.7`. 731 jours ou plus et `couche` : `taille_cm - 0.7`. Sinon : `taille_cm`. |

**Pour l'instant :** `waz`, `haz`, `whz`, `alerte`, `motif_alerte` et `flag_aberrant` sont gardés tels que le téléphone les envoie. Le serveur les recalculera à l'étape des Z-scores.

**Créer :** `POST /api/children/{id}/measurements/`

```json
{
  "date_mesure": "2026-11-04",
  "poids_kg": "9.20",
  "taille_cm": "78.0",
  "position": "debout",
  "pb_mm": 130,
  "alerte": "vert"
}
```

`201`

```json
{
  "id": "e4951e35-b4a0-428a-8aaf-1515fb39e005",
  "enfant_id": "4c09f399-823d-4c4d-9209-21464f87cc2d",
  "asc_id": "712da08f-311e-437d-84e4-020c47329ef4",
  "date_mesure": "2026-11-04",
  "poids_kg": "9.20",
  "taille_cm": "78.0",
  "position": "debout",
  "pb_mm": 130,
  "oedemes_bilateraux": "aucun",
  "age_jour": 658,
  "age_mois": 21,
  "taille_corrigee_cm": "78.7",
  "waz": null,
  "haz": null,
  "whz": null,
  "flag_aberrant": false,
  "alerte": "vert",
  "motif_alerte": "",
  "ref_oms": "WHO2006",
  "version": 1,
  "created_at": "2026-11-04T05:12:15.462092Z",
  "updated_at": "2026-11-04T05:12:15.462101Z",
  "device_id": "tel-1",
  "deleted_at": null
}
```

`400` – Exemple : PB hors de 6 à 59 mois.

```json
{ "pb_mm": ["Le périmètre brachial ne peut être saisi qu'entre 6 et 59 mois."] }
```

## `/api/referrals/`

**Ce qu'il fait :** gère les référencements. L'ASC et l'admin créent. Seul l'admin peut modifier ou supprimer.

- Un ASC n'envoie pas `asc_id` : c'est lui. Un admin doit l'envoyer pour une grossesse.
- Sans `code_unique`, le serveur crée `R-<4 premiers caractères de l'id de l'ASC>-<MMJJ>-<n>`.
- Seul le lien correspondant à `origine` est accepté, et `mesure_id` doit être une mesure de cet enfant.
- Un référencement d'origine `enfant` passe l'enfant à `statut_prise_en_charge` = `refere`, et la `version` de l'enfant augmente. Le téléphone doit relire l'enfant, sinon sa prochaine modification recevra `409`.
- `femme` donne le nom de la femme pour une grossesse, et vaut `null` pour un enfant.

**Créer :** `POST`

```json
{
  "origine": "enfant",
  "enfant_id": "4c09f399-823d-4c4d-9209-21464f87cc2d",
  "mesure_id": "e4951e35-b4a0-428a-8aaf-1515fb39e005",
  "csb_id": 1,
  "priorite": "haute",
  "motif": "PB bas"
}
```

`201`

```json
{
  "id": "ee711d85-d6bf-4cdc-a3d8-54469227d2c6",
  "code_unique": "R-712d-1104-02",
  "origine": "enfant",
  "enfant_id": "4c09f399-823d-4c4d-9209-21464f87cc2d",
  "grossesse_id": null,
  "mesure_id": "e4951e35-b4a0-428a-8aaf-1515fb39e005",
  "asc_id": "712da08f-311e-437d-84e4-020c47329ef4",
  "csb_id": 1,
  "priorite": "haute",
  "motif": "PB bas",
  "status": "envoye",
  "femme": null,
  "version": 1,
  "created_at": "2026-11-04T05:12:15.487541Z",
  "updated_at": "2026-11-04T05:12:15.487550Z",
  "device_id": "tel-1",
  "deleted_at": null
}
```

`400` – Code déjà utilisé, y compris par une ligne supprimée.

```json
{ "code_unique": ["Ce code de référencement existe déjà."] }
```

## POST `/api/referrals/{id}/status/`

**Ce qu'il fait :** fait avancer le statut d'une étape. Réservé à l'agent du CSB destinataire et à l'admin.

`envoye` → `recu` → `vu` → `pris_en_charge` → `clos`

**Ce dont il a besoin :**

```json
{ "status": "recu", "version": 1 }
```

`200` – Le référencement complet, avec le nouveau `status` et `version` augmentée de 1.

`400` – Retour en arrière, ou même statut.

```json
{ "status": ["Le statut ne peut pas revenir en arrière."] }
```

`400` – Étape sautée.

```json
{ "status": ["Le statut suivant doit être « vu »."] }
```

`409` – Version différente, même format que plus haut.

## Créer les premiers comptes

Les listes de référence (provinces, régions, CSB, types de danger) sont vides tant que personne ne les a remplies. Remplissez-les dans `/admin/`.

1. Créez un administrateur depuis le dossier `Backend_serveur` :

```
python manage.py createsuperuser
```

2. Connectez-vous à `/api/auth/login/` avec son identifiant et son mot de passe dans le champ `pin`.
3. Créez les autres comptes avec `POST /api/profiles/`.
