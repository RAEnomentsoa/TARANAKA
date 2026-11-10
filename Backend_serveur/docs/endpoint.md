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
| GET | `/api/auth/2fa/` | Oui | État de la double authentification |
| POST | `/api/auth/2fa/setup/`, `/activate/`, `/disable/` | Oui | Mettre en place, activer, désactiver la double authentification |
| GET | `/api/auth/my-data/` | Oui | Mes données (droit d'accès, loi 2014-038) |
| POST | `/api/auth/my-data/erase/` | Oui | Effacer mes données (droit à l'effacement, bénéficiaires) |
| POST | `/api/auth/access-request/` | Non | Demander un compte web (infirmier, médecin, superviseur) |
| GET | `/api/auth/access-request/options/` | Non | Régions et centres pour le formulaire de demande |

---

## POST `/api/auth/login/`

**Ce qu'il fait :** vérifie l'identifiant et le PIN, puis renvoie les tokens et les informations de l'utilisateur. Chaque tentative est enregistrée dans `journal_audit`.

**Majuscules :** l'identifiant ne tient pas compte de la casse. `Rasoa`, `rasoa` et `RASOA` ouvrent le même compte, et deux comptes (ou une demande d'accès en attente) ne peuvent pas avoir des identifiants qui ne diffèrent que par la casse (contrainte en base `utilisateur_identifiant_insensible_casse`). L'identifiant est gardé tel qu'il a été saisi.

**Ce dont il a besoin :**

```json
{
  "identifiant": "0341112233",
  "pin": "1234"
}
```

`code_totp` (facultatif) : le code à 6 chiffres de l'application d'authentification, **obligatoire seulement pour un compte qui a activé la double authentification** (voir plus bas). Les autres comptes ne l'envoient pas.

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
  },
  "totp_a_configurer": false
}
```

`totp_a_configurer` vaut `true` seulement si `TOTP_OBLIGATOIRE=True` et que ce compte web n'a pas encore activé la double authentification : le jeton n'ouvre alors que `/api/auth/me/`, `/api/auth/changer-pin/` et `/api/auth/2fa/…` (`403` ailleurs).

`401` – Compte avec double authentification : PIN correct mais `code_totp` absent. Redemandez avec le code. Cet essai ne compte pas comme un échec.

```json
{
  "detail": "Saisissez le code à 6 chiffres de votre application d'authentification.",
  "code": "totp_requis"
}
```

`401` – Code faux, expiré ou déjà utilisé. **Compte comme un échec** (même blocage qu'un mauvais PIN).

```json
{ "detail": "Code d'authentification incorrect.", "code": "totp_invalide" }
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

## Double authentification (comptes web)

Pour `agent_csb`, `superviseur` et `admin` (spec §2). Codes TOTP à 6 chiffres, 30 secondes, compatibles avec Google Authenticator, FreeOTP, Aegis… Les autres profils reçoivent `403` (`totp_non_disponible`).

| Méthode | Endpoint | Rôle |
|---|---|---|
| GET | `/api/auth/2fa/` | `{"active", "requise_pour_ce_profil", "obligatoire", "a_configurer"}` |
| POST | `/api/auth/2fa/setup/` | Nouveau secret : `{"secret": "JBSW…", "uri": "otpauth://totp/TARANAKA:…"}`. Affichez `uri` en QR code. `400 totp_deja_actif` si déjà active. |
| POST | `/api/auth/2fa/activate/` | `{"code": "123456"}`. Active, ferme les autres sessions et renvoie `{"detail", "access", "refresh"}` : remplacez les deux tokens. `400 totp_invalide` ou `totp_non_prepare`. |
| POST | `/api/auth/2fa/disable/` | `{"pin": "1234", "code": "123456"}`. Un mauvais PIN ou code compte comme un échec (`401 totp_invalide`, `423`). `403 totp_obligatoire` si `TOTP_OBLIGATOIRE=True`. |
| POST | `/api/profiles/{id}/reset-2fa/` | Admin : téléphone perdu. Désactive la double authentification du compte et ferme ses sessions. |

Un code n'est accepté qu'une fois, avec une tolérance de 30 secondes avant ou après.

---

## Données personnelles (loi n° 2014-038)

**`GET /api/auth/my-data/`** (tout profil) : toutes les données du serveur sur la personne connectée : `compte` (sans le PIN), et pour une bénéficiaire `cycles`, `grossesses`, `signes_danger`, `enfants`, `mesures`, `journaux_alimentaires`, `referencements`, `rendez_vous`, `consultations`, plus `journal` (actions du journal d'audit sur son compte : date, action, table). Chaque export est journalisé (`acces_donnees`).

**`GET /api/profiles/{id}/data/`** (admin) : le même export, pour répondre à une demande écrite.

**`POST /api/auth/my-data/erase/`** (bénéficiaire) :

```json
{ "pin": "1234", "inclure_enfants": false }
```

Un mauvais PIN répond `400` (`pin_incorrect`) et compte comme un échec. `200` :

```json
{
  "detail": "Les données ont été effacées.",
  "resume": {
    "cycles_supprimes": 3,
    "grossesses_supprimees": 1,
    "grossesses_conservees_anonymes": 0,
    "enfants_detaches": 1,
    "enfants_supprimes": 0,
    "enfants_conserves_anonymes": 0
  }
}
```

- Cycles supprimés définitivement. Grossesses sans référencement supprimées (les téléphones des ASC l'apprennent par `/api/sync/pull/`). Grossesses avec référencement conservées par le centre, sans identité.
- Enfants : détachés de la mère. Avec `inclure_enfants: true`, le nom est effacé, et un enfant sans référencement est supprimé avec ses mesures, journaux, rendez-vous et consultations.
- Le compte est anonymisé, désactivé et toutes ses sessions sont fermées. Le journal d'audit est conservé (traçabilité) et l'effacement y est noté (`effacement_donnees`, avec des nombres seulement).

**`POST /api/profiles/{id}/erase/`** (admin) : `{"inclure_enfants": false}`, même effet, pour une demande écrite. Seuls les comptes `beneficiaire` s'effacent (`400` sinon : un compte professionnel se désactive). `400` si déjà effacé.

---

## Demande d'accès (comptes web)

Décision D15 (`docs/DECISIONS.md`). Une personne demande un compte web depuis la page de connexion du tableau de bord. **Aucun compte n'existe avant qu'un admin approuve** : la demande n'ouvre aucun accès.

**`GET /api/auth/access-request/options/`** (public) : `{"regions": [{"id", "nom"}], "centres": [{"id", "name", "type_centre", "region_id"}]}`. Noms et types seulement, aucune donnée personnelle.

**`POST /api/auth/access-request/`** (public, 5 demandes par heure et par adresse, `429` au-delà) :

```json
{
  "nom": "Rakoto", "prenom": "Hery", "phone": "034 00 000 01", "email": "",
  "identifiant": "hery.crenas", "pin": "2468",
  "profil_demande": "agent_csb", "csb_id": 3, "region_id": null,
  "fonction": "Infirmier", "message": ""
}
```

- `profil_demande` : `agent_csb` ou `superviseur` seulement. Un ASC est créé par son superviseur (spec §2), une bénéficiaire n'a pas besoin de compte, un admin ne se déclare pas.
- `agent_csb` : `csb_id` obligatoire ; la région est celle du centre. `superviseur` : `region_id` facultatif (vide = national), pas de centre.
- `phone` obligatoire (l'admin appelle pour vérifier), `email` facultatif.
- `identifiant` refusé s'il est déjà pris par un compte ou par une autre demande en attente. `pin` : 4 à 6 chiffres, gardé haché, jamais renvoyé, effacé quand la demande est traitée.
- Réponse `201` : la demande avec `statut: "en_attente"`. Journal : `demande_acces_creee`.

**`/api/access-requests/`** (admin seulement) : `GET` liste, filtres `?statut=en_attente|approuvee|refusee` et `?profil_demande=`. Chaque demande donne aussi `region_nom`, `csb_nom`, `csb_type`, `traitee_par`, `date_traitement`, `utilisateur_id`. Jamais le PIN.

- **`POST /api/access-requests/{id}/approve/`** : crée le compte avec le PIN choisi dans la demande. Corps facultatif pour corriger ce qui a été demandé : `{"profil_demande": "superviseur", "region_id": 2, "csb_id": null}`. Journal : `create` (compte) et `demande_acces_approuvee`. Le compte doit ensuite activer la double authentification (`TOTP_OBLIGATOIRE`).
- **`POST /api/access-requests/{id}/refuse/`** : `{"motif": "..."}` (facultatif, pour la trace ; la personne ne reçoit pas de message). Aucun compte créé ; l'identifiant redevient libre. Journal : `demande_acces_refusee`.
- Une demande déjà traitée répond `400` (`statut`).

Les demandes apparaissent aussi dans `/admin/` (« Demandes d'accès »), en lecture seule, avec les actions « Approuver » et « Refuser » qui passent par le même code.

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
| `/api/referrals/{id}/status/` | POST | Faire avancer le dossier (patient arrivé, prise en charge, suivi, sortie) |
| `/api/referrals/incoming/` | GET | File entrante du centre, triée par urgence puis ancienneté |
| `/api/appointments/` | GET, POST, PUT, PATCH, DELETE | Rendez-vous de contrôle ou de dépistage |
| `/api/consultations/` | GET, POST, PUT, PATCH, DELETE | Consultations nutritionnelles au centre |
| `/api/food-logs/` | GET, POST, PUT, PATCH, DELETE | Journal alimentaire (8 groupes) |
| `/api/follow-ups/` | GET | Relances : non arrivés, rendez-vous manqués, enfants à revoir |
| `/api/sync/push/` | POST | Envoyer la file d'attente (outbox) du téléphone |
| `/api/sync/pull/` | GET | Recevoir les changements, suppressions comprises |
| `/api/conflicts/` | GET | Conflits de synchronisation à arbitrer |
| `/api/conflicts/{id}/resolve/` | POST | Arbitrer un conflit |
| `/api/clinical-config/` | GET, POST, PUT, PATCH | Configuration clinique versionnée |
| `/api/clinical-config/current/` | GET | Version à utiliser par les applications |
| `/api/clinical-config/{version}/publish/`, `/retire/` | POST | Publier ou retirer une version (admin) |
| `/api/stats/`, `/api/stats/export/` | GET | Statistiques agrégées et anonymes, export CSV |
| `/api/who-reference/` | GET | Courbes de croissance OMS 2006 (tables chargées) |
| `/api/audit/` | GET | Journal d'audit (admin) |
| `/api/profiles/{id}/reset-pin/` | POST | Réinitialiser le PIN (superviseur, admin) |
| `/api/access-requests/` | GET | Demandes d'accès aux comptes web (admin) |
| `/api/access-requests/{id}/approve/`, `/refuse/` | POST | Approuver (crée le compte) ou refuser une demande (admin) |

Le fichier OpenAPI complet est dans `docs/openapi.yaml` à la racine du dépôt.

Un endpoint de détail ajoute `{id}/`, par exemple `/api/children/{id}/`. `PUT` remplace toute la ligne, `PATCH` seulement les champs envoyés.

## Qui peut faire quoi

L = lecture, É = écriture (création, modification), — = refusé (`403`). Le tableau est vérifié par `comptes/tests_permissions.py`.

| Ressource | `beneficiaire` | `asc` | `agent_csb` | `superviseur` | `admin` |
|---|---|---|---|---|---|
| Enfants, mesures | L (ses enfants) | L É (ses enfants) | L (enfants référés à son centre) | — | L É |
| Grossesses, signes de danger | L É (les siennes) | L É (sa région) | L (référées à son centre) | — | L É |
| Cycles | L É (les siens) | — | — | — | L É |
| Journal alimentaire | L É (ses enfants) | L É | L | — | L É |
| Référencements | L | L, création | L, statut (sauf sortie : agent du centre seulement) | — | L É, statut sauf sortie |
| File entrante | — | — | L | — | L |
| Rendez-vous | L | L É | L É (dans son centre) | — | L É |
| Consultations | L | L | L É (son centre) | — | L É |
| Relances | — | L | L | — | L |
| Conflits | L (les siens) | L (les siens) | L, arbitrage | — | L, arbitrage |
| Comptes | L (le sien) | L, création de bénéficiaires | — | L et création d'ASC de sa zone, réinitialisation du PIN | L É |
| Configuration clinique | L (publiées) | L (publiées) | L (publiées) | L (publiées) | L É, publication |
| Statistiques | — | — | — | L (sa région) | L |
| Journal d'audit | — | — | — | — | L |
| Demandes d'accès | — | — | — | — | L, approbation, refus |
| Double authentification (`/auth/2fa/`) | — | — | Oui | Oui | Oui, et réinitialisation pour un autre compte |
| Mes données (`/auth/my-data/`) | L, effacement | L | L | L | L, et export ou effacement d'une bénéficiaire sur demande |
| `/sync/push/`, `/sync/pull/` | Selon les droits ci-dessus, table par table | | | | |

Le superviseur ne lit **aucun dossier individuel**, même par son identifiant.

- **`403`** : le profil n'a pas le droit de faire cette action.
- **`404`** : la ligne n'existe pas, a été supprimée, ou n'est pas accessible à cet utilisateur. La réponse ne révèle pas laquelle de ces trois situations s'applique.

## Règles des tables synchronisées

Elles s'appliquent à `cycles`, `pregnancies`, `dangers`, `children`, `measurements`, `food-logs`, `referrals`, `consultations` et `appointments`.

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

**`DELETE` :** répond `204`. La ligne est masquée (suppression logique) et n'apparaît plus dans les listes ni les détails. `version` n'est pas demandée. Un téléphone apprend les suppressions avec `GET /api/sync/pull/`, qui renvoie aussi les lignes supprimées (avec `deleted_at`).

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
| `/api/measurements/` et `/api/children/{id}/measurements/` | `date_min`, `date_max`, `alerte`, `classification` |
| `/api/referrals/` | `status`, `priorite`, `csb`, `type_centre`, `origine`, `enfant`, `code` (sans tenir compte des majuscules), `en_retard` (`true`/`false`) |
| `/api/appointments/` | `statut`, `type_rendez_vous`, `enfant`, `csb`, `date_min`, `date_max`, `manque` (`true`/`false`) |
| `/api/consultations/` | `enfant`, `decision` |
| `/api/food-logs/` | `enfant`, `date_min`, `date_max` |
| `/api/pregnancies/` | `danger_sans_referencement` (`true` ou `false`) |
| `/api/facilities/` | `region`, `type_centre` (`csb`, `crenam`, `crenas`, `creni`) |
| `/api/conflicts/` | `statut` (`a_verifier`, `resolu`), `table`, `ligne_id` |
| `/api/audit/` | `user`, `action`, `table`, `ligne_id`, `depuis`, `jusqu_a` |

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

**Créer (superviseur) :** `POST`, sans `profile_code`. Le compte est toujours `asc`, dans la région du superviseur s'il en a une (sinon `region_id` peut être envoyé). Le superviseur lit les comptes ASC de sa zone.

**Modifier (admin seulement) :** `PUT` ou `PATCH`. Ces routes ne changent pas le PIN.

**PIN oublié (mode agent) :** `POST /api/profiles/{id}/reset-pin/` avec `{"nouveau_pin": "4321"}`. Réservé au superviseur (ASC de sa zone) et à l'admin. Le compte est débloqué, toutes ses sessions sont fermées, et l'action est journalisée (`reinitialiser_pin`). Après connexion, le téléphone récupère ses données avec `/api/sync/pull/`. Réponse `200` : `{"detail": "PIN réinitialisé."}`. Un compte hors de la zone donne `404`.

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
[{ "id": 1, "name": "CSB A", "type_centre": "csb", "region_id": 1, "tel": "1" }]
```

`type_centre` vaut `csb`, `crenam`, `crenas` ou `creni` : les CRENAS, CRENI et CRENAM sont des lignes de cette liste.

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

**Z-scores :** `waz`, `haz` et `whz` sont calculés par le serveur (OMS 2006) quand les tables OMS sont chargées (`python manage.py importer_tables_oms <dossier>`). Sinon, les valeurs du téléphone sont gardées.

**Classification (calculée par le serveur avec la configuration clinique publiée) :**

| Champ | Contenu |
|---|---|
| `classification` | `mas`, `mam`, `normal`, `nourrisson_a_risque`, ou vide sans configuration publiée ou hors de 0 à 59 mois |
| `orientation_centre` | `creni`, `crenas`, `crenam`, `csb` ou vide |
| `urgence` | `rouge`, `orange`, `jaune` ou vide |
| `date_prochain_controle` | Prochain dépistage ou contrôle |
| `config_version` | Version de la configuration utilisée |

`flag_aberrant` : la valeur du téléphone est gardée, et le serveur le met à `true` si un z-score sort des bornes de plausibilité de la configuration. `alerte` et `motif_alerte` sont gardés tels que le téléphone les envoie.

**Saisie de l'ASC :** `signes_danger` (liste de codes de la configuration, par exemple `["convulsions"]`), `complications_medicales`, `appetit` (`non_teste`, `bon`, `mauvais`), `difficultes_allaitement`.

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
  "signes_danger": [],
  "complications_medicales": false,
  "appetit": "non_teste",
  "difficultes_allaitement": false,
  "classification": "normal",
  "orientation_centre": "",
  "urgence": "",
  "date_prochain_controle": "2027-02-02",
  "config_version": 1,
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
- `code_unique` : le téléphone envoie le code créé hors ligne (par exemple `TRK-7F3K-92`).
- `date_referencement` : date et heure du référencement sur le téléphone. Sans elle, l'heure du serveur.
- En lecture : `urgence` (`urgente` = `rouge`, `haute` = `orange`, `normale` = `jaune`) et `en_retard` (toujours `envoye` après le délai de la configuration, 48 h dans l'exemple).
- `asc` : `{ "nom", "prenom", "phone" }` de l'agent communautaire, pour savoir qui appeler. Visible par l'ASC, l'agent de CSB et l'admin ; `null` pour une bénéficiaire.

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
  "asc": { "nom": "Rasoanirina", "prenom": "Rasoa", "phone": "034 00 000 01" },
  "csb_id": 1,
  "priorite": "haute",
  "motif": "PB bas",
  "status": "envoye",
  "urgence": "orange",
  "date_referencement": "2026-11-04T05:12:15.487541Z",
  "date_reception": null,
  "date_prise_en_charge": null,
  "date_suivi": null,
  "date_sortie": null,
  "issue_sortie": "",
  "en_retard": false,
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

**Ce qu'il fait :** fait avancer le dossier (spec §7). Réservé à l'agent du centre destinataire et à l'admin. **La sortie est réservée à l'agent du centre destinataire** (`403` pour l'admin).

`envoye` (Référé) → `recu` (patient arrivé) → `pris_en_charge` → `en_suivi` → `sortie`

La sortie est aussi possible depuis `recu` et `pris_en_charge` (transfert, décès…). Le serveur remplit `date_reception`, `date_prise_en_charge`, `date_suivi` et `date_sortie`. Un dossier sorti avec `date_suivi` à `null` n'est pas passé par le suivi. Pour un enfant, `statut_prise_en_charge` suit : `pris_en_charge`, `suivi`, puis l'issue de sortie, et la `version` de l'enfant augmente.

**Patient arrivé :**

```json
{ "status": "recu", "version": 1 }
```

**Sortie :** `issue_sortie` est obligatoire : `gueri`, `transfere`, `non_repondant`, `abandon` ou `decede`.

```json
{ "status": "sortie", "version": 4, "issue_sortie": "gueri" }
```

`200` – Le référencement complet, avec le nouveau `status` et `version` augmentée de 1.

`400` – Retour en arrière, ou même statut.

```json
{ "status": ["Le statut ne peut pas revenir en arrière."] }
```

`400` – Étape sautée.

```json
{ "status": ["Le statut suivant doit être « recu »."] }
```

`400` – Issue manquante pour une sortie, ou envoyée pour un autre statut.

```json
{ "issue_sortie": ["L'issue de sortie est obligatoire."] }
```

`403` – Sortie demandée par quelqu'un d'autre que l'agent du centre.

`409` – Version différente, même format que plus haut.

## GET `/api/referrals/incoming/`

**Ce qu'il fait :** la file des référencements entrants du centre (`envoye` et `recu`), triée par urgence (`rouge`, `orange`, `jaune`) puis du plus ancien au plus récent (`date_referencement`). Même format paginé et mêmes filtres que `/api/referrals/`. Pour l'agent de CSB et l'admin.

Recherche par code : `GET /api/referrals/?code=TRK-7F3K-92`.

## `/api/appointments/`

**Ce qu'il fait :** programme un contrôle (`controle`) ou un dépistage (`depistage`). L'agent de CSB crée toujours le rendez-vous dans son centre (`csb_id` imposé). `manque` vaut `true` quand le rendez-vous est encore `prevu` après sa date ; `?manque=true` liste les rendez-vous manqués.

```json
{
  "enfant_id": "4c09f399-823d-4c4d-9209-21464f87cc2d",
  "referencement_id": "ee711d85-d6bf-4cdc-a3d8-54469227d2c6",
  "date_prevue": "2026-11-11",
  "type_rendez_vous": "controle",
  "motif": "Contrôle PB"
}
```

Réponse : les mêmes champs, plus `id`, `csb_id`, `statut` (`prevu`, `honore`, `annule`), `manque` et les colonnes de synchronisation. Pour noter la venue : `PATCH` avec `{"statut": "honore", "version": 1}`.

## `/api/consultations/`

**Ce qu'il fait :** la prise en charge enregistrée par l'agent du centre : `enfant_id`, `mesure_id` et `referencement_id` (facultatifs, du même enfant), `date`, `diagnostic`, `decision` (`conseil`, `reference`, `prise_en_charge`), `observations`. Pour un agent de CSB, `csb_id` et `agent_medical_id` sont imposés (son centre, lui-même). Un admin doit les envoyer.

## `/api/food-logs/`

**Ce qu'il fait :** le journal alimentaire d'un enfant de 6 à 23 mois, un par jour : `enfant_id`, `date_jour`, `type_allaitement`, `g1_lait_maternel` … `g8_autres_fruits_legumes`, `notes`. En lecture : `score_diversite` (nombre de groupes) et `diversite_minimale_atteinte` (seuil de la configuration, `null` sans configuration).

## GET `/api/follow-ups/`

**Ce qu'il fait :** ce qu'il faut relancer (spec §7, §10), pour l'ASC (ses enfants), l'agent de CSB (son centre) et l'admin.

```json
{
  "delai_non_arrivee_heures": 48,
  "referencements_non_arrives": [{ "id": "…", "code_unique": "TRK-DEMO-06", "urgence": "jaune", "...": "..." }],
  "rendez_vous_manques": [{ "id": "…", "date_prevue": "2026-11-02", "manque": true, "...": "..." }],
  "enfants_a_revoir": [
    {
      "id": "…",
      "nom": "Lova",
      "date_naissance": "2024-08-11",
      "sexe": "M",
      "statut_prise_en_charge": "aucun",
      "prochain_controle": "2026-11-03",
      "derniere_classification": "mam"
    }
  ]
}
```

Sans configuration publiée, `delai_non_arrivee_heures` vaut `null` et la liste des non arrivés est vide. Chaque liste est limitée à 200 lignes.

---

# Synchronisation hors ligne

## POST `/api/sync/push/`

**Ce qu'il fait :** applique la file d'attente du téléphone (modèle outbox, spec §9), **dans l'ordre envoyé**, chaque opération séparément : une opération refusée ne bloque pas les suivantes. Chaque opération passe par les mêmes droits et les mêmes règles que l'endpoint REST de sa table. Corps compressé accepté (`Content-Encoding: gzip`). 100 opérations au plus.

```json
{
  "operations": [
    {
      "cle_idempotence": "0b6f8f0e-0f43-4c55-9a51-6f3c1c6b8a01",
      "table": "mesure",
      "operation": "create",
      "id": "5a0c9d55-6c47-4a40-8b47-3a2f0c1d7e01",
      "donnees": { "enfant_id": "…", "date_mesure": "2026-11-04", "poids_kg": "8.60", "taille_cm": "77.5", "position": "couche", "pb_mm": 112, "alerte": "rouge" }
    },
    {
      "cle_idempotence": "0b6f8f0e-0f43-4c55-9a51-6f3c1c6b8a02",
      "table": "enfant",
      "operation": "update",
      "id": "4c09f399-823d-4c4d-9209-21464f87cc2d",
      "version": 2,
      "donnees": { "nom": "Soa Fanja" }
    }
  ]
}
```

- `table` : `cycle`, `grossesse`, `danger_grossesse`, `enfant`, `mesure`, `journal_alimentaire`, `referencement`, `consultation_nutritionnelle`, `rendez_vous`.
- `operation` : `create`, `update` (`version` obligatoire : celle que le téléphone connaît) ou `delete` (`version` facultative, vérifiée si envoyée).
- `cle_idempotence` : un UUID par opération, gardé jusqu'à la réponse. **Le même envoi répété ne fait rien deux fois** : la réponse enregistrée est renvoyée avec `rejoue: true`.

`200` – Une réponse par opération, dans le même ordre :

```json
{
  "horodatage_serveur": "2026-11-04T08:00:00.123456Z",
  "resultats": [
    {
      "cle_idempotence": "0b6f8f0e-…01",
      "table": "mesure",
      "operation": "create",
      "id": "5a0c9d55-…01",
      "statut": "applique",
      "ligne": { "classification": "mas", "orientation_centre": "crenas", "urgence": "orange", "...": "..." },
      "conflit_id": null,
      "erreurs": null,
      "rejoue": false
    },
    {
      "cle_idempotence": "0b6f8f0e-…02",
      "table": "enfant",
      "operation": "update",
      "id": "4c09f399-…",
      "statut": "conflit",
      "ligne": { "nom": "Soa Nirina", "version": 3, "...": "..." },
      "conflit_id": "d3c1…",
      "erreurs": null,
      "rejoue": false
    }
  ]
}
```

| `statut` | Signification | Affichage conseillé (spec §9) |
|---|---|---|
| `applique` | Enregistré | Synchronisé (vert) |
| `deja_applique` | La ligne existait déjà (renvoi), rien n'est créé | Synchronisé (vert) |
| `conflit` | La ligne a changé entre-temps. `ligne` = version du serveur. Données cliniques : rien n'est écrasé, les deux versions sont gardées et `conflit_id` est en file d'arbitrage. Données personnelles (`cycle`, `journal_alimentaire`) : pas de file, le téléphone décide. | Conflit (rouge) |
| `erreur` | Données refusées, détail dans `erreurs`. Non mémorisé : le même envoi peut être refait une fois corrigé. | À synchroniser (orange) |
| `refuse` | Profil sans ce droit | À synchroniser (orange) |
| `introuvable` | Ligne inconnue, supprimée ou hors de portée | — |

`400` – Enveloppe invalide (pas de liste, plus de 100 opérations). Un référencement reste « Non transmis » sur le téléphone tant que sa réponse n'est pas `applique` ou `deja_applique`.

## GET `/api/sync/pull/`

**Ce qu'il fait :** renvoie, table par table, les lignes que l'utilisateur peut lire et qui ont changé depuis `depuis`, **suppressions comprises** (`deleted_at` rempli), l'état de ses conflits et la configuration clinique si elle est plus récente.

| Paramètre | Rôle |
|---|---|
| `depuis` | Date et heure ISO. Absent : tout (première synchronisation) |
| `tables` | Liste séparée par des virgules. Absent : toutes les tables lisibles |
| `limite` | Lignes par table, 500 par défaut, 1000 au plus |
| `apres_id` | Avec `depuis`, pour continuer une table (voir `suite`) |
| `config_version` | Version de configuration du téléphone |

```json
{
  "horodatage_serveur": "2026-11-04T07:59:55.123456Z",
  "tables": {
    "referencement": {
      "lignes": [{ "id": "…", "status": "recu", "...": "..." }],
      "suite": false,
      "prochain_depuis": "2026-11-04T07:59:55.123456Z",
      "apres_id": null
    }
  },
  "conflits": [{ "id": "d3c1…", "table_nom": "enfant", "ligne_id": "…", "statut": "resolu", "resolution": "serveur", "version_finale": 4, "resolu_le": "…" }],
  "config_clinique": { "version": 1, "mise_a_jour": null }
}
```

- Enregistrez `horodatage_serveur` et renvoyez-le comme `depuis` la prochaine fois. Il est 5 secondes avant la requête : une ligne peut revenir deux fois, sans conséquence.
- Si `suite` vaut `true`, rappelez avec `tables=<cette table>&depuis=<prochain_depuis>&apres_id=<apres_id>`.
- `config_clinique.mise_a_jour` contient la configuration complète si `config_version` est absente ou plus ancienne.

## `/api/conflicts/`

**Ce qu'il fait :** la file des conflits sur les données cliniques (spec §9, §10). L'agent de CSB voit ceux des dossiers de son centre, l'admin tous, l'ASC et la bénéficiaire ceux qu'ils ont envoyés (lecture seule). Chaque conflit contient `donnees_telephone`, `donnees_serveur`, `version_base`, `version_serveur`, `user_id` et `device_id` de l'envoi.

**Arbitrer :** `POST /api/conflicts/{id}/resolve/` (agent de CSB, admin)

```json
{ "choix": "fusion", "donnees": { "nom": "Soa Nirina" }, "commentaire": "Nom vérifié avec la mère" }
```

`expediteur` : `{ "nom", "prenom", "phone" }` de la personne qui a envoyé la version du téléphone (visible par l'ASC, l'agent de CSB et l'admin, `null` pour une bénéficiaire). Pour une suppression, `donnees_telephone` vaut `{}`.

`choix` : `serveur` (garder la version du serveur), `telephone` (appliquer celle du téléphone) ou `fusion` (`donnees` obligatoire). La ligne reçoit toujours une nouvelle version, pour que chaque téléphone récupère la décision. `400` si le conflit est déjà résolu ou si les données sont refusées. L'arbitrage est journalisé (`conflit_resolu`).

---

# Configuration clinique

## `/api/clinical-config/`

**Ce qu'il fait :** les règles cliniques versionnées (spec §11) : seuils et orientation de la malnutrition, signes de danger, calendriers PEV, CPN et postnatal, conseils et aliments. Aucune de ces règles n'est dans le code.

- `GET /api/clinical-config/current/` : la version publiée la plus récente, avec `contenu`. En-tête `ETag: "v<version>"` ; avec `If-None-Match`, réponse `304` si rien n'a changé. `404` si aucune version n'est publiée.
- `GET /api/clinical-config/` : les versions (sans `contenu`). Les brouillons ne sont visibles que par l'admin.
- `POST` (admin) : crée un brouillon `{ "libelle": "…", "contenu": { … }, "notes": "…" }`. La section `malnutrition` est vérifiée par `config_clinique/schema.json`.
- `PATCH /api/clinical-config/{version}/` (admin) : seulement un brouillon, y compris `statut_validation`, `valide_par`, `reference_validation`, `date_validation`.
- `POST /api/clinical-config/{version}/publish/` et `/retire/` (admin). Une version publiée ne change plus. Avec `CONFIG_VALIDEE_OBLIGATOIRE=True`, seule une version validée par écrit peut être publiée.

Le fichier d'exemple, marqué « À VALIDER », est `config_clinique/exemples/config_clinique_exemple.json` : `python manage.py charger_config_clinique --publier`.

---

# Supervision

## GET `/api/stats/` et `/api/stats/export/`

**Ce qu'il fait :** statistiques **agrégées et sans identité** (spec §10), pour le superviseur (limité à sa région s'il en a une) et l'admin. `export/` renvoie le même contenu en CSV (`groupe,indicateur,valeur`, `Content-Type: text/csv; charset=utf-8`, quel que soit l'en-tête `Accept`) et chaque export est journalisé.

| Paramètre | Rôle |
|---|---|
| `date_debut`, `date_fin` | Période (30 derniers jours par défaut) |
| `region` ou `province` | Zone. Une autre région que la sienne : `403` |
| `grouper_par` | `region` ou `mois` |

```json
{
  "periode": { "date_debut": "2026-10-05", "date_fin": "2026-11-04" },
  "seuil_petits_effectifs": 5,
  "grouper_par": null,
  "total": {
    "indicateurs": {
      "depistages": 17, "enfants_depistes": 17, "cas_mas": 7, "cas_mam": null, "nourrissons_a_risque": 0,
      "referencements": 9, "referencements_arrives": 6, "rendez_vous_manques": null,
      "taux_arrivee_pct": 66.7, "delai_moyen_arrivee_heures": 27.5,
      "sorties_gueri": null, "sorties_transfere": 0, "sorties_non_repondant": 0, "sorties_abandon": null, "sorties_decede": 0
    },
    "masques": ["cas_mam", "rendez_vous_manques", "sorties_gueri", "sorties_abandon"]
  },
  "groupes": []
}
```

Avec `grouper_par`, `groupes` contient un élément par région ou par mois : `{ "cle": "2026-11", "libelle": "11/2026", "indicateurs": { … }, "masques": [ … ] }`, avec les mêmes indicateurs que `total`.

Règles de masquage, identiques à l'écran et dans le CSV :

- Un effectif de 1 à 4 est remplacé par `null` et cité dans `masques` (`<5` dans le CSV). 0 reste affiché.
- Un taux ou un délai moyen calculé sur moins de 5 cas est masqué.
- Si 1 à 4 référencements ne sont pas arrivés, `referencements_arrives` et `taux_arrivee_pct` sont masqués (sinon la différence le révélerait).
- **Suppression complémentaire :** avec des groupes, si une seule valeur d'un indicateur est masquée alors que le total est visible, la plus petite autre valeur est masquée aussi, pour qu'on ne puisse pas la retrouver par soustraction.

## GET `/api/who-reference/`

**Ce qu'il fait :** les standards de croissance OMS 2006, **depuis les tables officielles chargées seulement** (`python manage.py importer_tables_oms`). Pour tout profil connecté.

| Paramètre | Rôle |
|---|---|
| `indicateur` | `wfa` (poids/âge), `lhfa` (taille/âge), `wfl` (poids/longueur), `wfh` (poids/taille) — obligatoire |
| `sexe` | `M` ou `F` — obligatoire |
| `cle_min`, `cle_max` | Bornes de la clé (jours pour `wfa`/`lhfa`, cm pour `wfl`/`wfh`) |
| `pas` | Garder une clé sur `pas`, par exemple `30` (jours) ou `1` (cm) |

```json
{
  "source": "OMS 2006, tables LMS officielles chargées (reference_oms)",
  "indicateur": "wfl",
  "sexe": "M",
  "unite_cle": "cm",
  "unite_valeur": "kg",
  "points": [
    {
      "cle": "75.0", "l": "-0.3521", "m": "9.5032", "s": "0.08295", "mesure_type": "L",
      "courbes": { "-3": 7.486, "-2": 8.088, "0": 9.503, "2": 11.275, "3": 12.33 }
    }
  ]
}
```

Les courbes sont calculées à partir des valeurs LMS avec la formule OMS. `404` si la table n'est pas chargée : aucune valeur n'est inventée.

## GET `/api/audit/`

**Ce qu'il fait :** le journal d'audit, en lecture seule, pour l'admin : `id`, `user_id`, `action`, `table_nom`, `ligne_id`, `details` (adresse IP, `device_id`, noms des champs changés, jamais de valeurs de santé), `date_creation`.

## Créer les premiers comptes

Les listes de référence (provinces, régions, CSB, types de danger) sont vides tant que personne ne les a remplies. Remplissez-les dans `/admin/`.

1. Créez un administrateur depuis le dossier `Backend_serveur` :

```
python manage.py createsuperuser
```

2. Connectez-vous à `/api/auth/login/` avec son identifiant et son mot de passe dans le champ `pin`.
3. Créez les autres comptes avec `POST /api/profiles/`.

Pour la production, voir `deployment.md` (réglages `TOTP_OBLIGATOIRE`, `CONFIG_VALIDEE_OBLIGATOIRE`, `USE_X_FORWARDED_HOST`, `CORS_ALLOWED_ORIGINS`) et `.env.production.example`.

Pour une démonstration, `python manage.py charger_demo` remplit une base vide avec des données fictives et la configuration d'exemple (voir `docs/DEMO.md` à la racine). Les tables OMS se chargent avec `python manage.py importer_tables_oms <dossier>`.
