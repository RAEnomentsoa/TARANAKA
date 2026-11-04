# API — problèmes relevés par le tableau de bord web

Ce document liste les écarts entre l'API actuelle (`Backend_serveur/`, branche `Backend_Serveur`) et ce dont le tableau de bord web (`web/`) a besoin pour couvrir la section 10 de `docs/SPEC.md`.

Le backend n'a **pas** été modifié. Pour chaque point, le tableau de bord appelle le contrat proposé ci-dessous. Tant que l'endpoint n'existe pas, l'écran affiche « Cette fonction n'est pas encore disponible sur le serveur. » : le client traite un `404`, `405` ou `501` sur un endpoint proposé comme `not_implemented` (`web/src/api/http.ts`).

Sources consultées : le code Django (`urls.py`, `views.py`, `serializers.py`, `services.py`, `permissions.py`) et `Backend_serveur/docs/endpoint.md`.

---

## 0. Documents de référence absents

| Document demandé | État | Conséquence |
|---|---|---|
| `docs/openapi.yaml` | Absent du dépôt (toutes branches). | Contrat déduit du code Django. Le schéma est généré à la volée par drf-spectacular (`/api/schema/`) : il faudrait l'exporter et le versionner (`python manage.py spectacular --file docs/openapi.yaml`). |
| `docs/BACKEND_STATUS.md` | Absent. | État des endpoints établi en lisant le code (tableau ci-dessous). |
| `skill.md` (design) | Absent du dépôt. | Utilisation du guide de design générique disponible dans l'environnement, avec les consignes « bleu clair et blanc ». |

### Ce que le tableau de bord utilise déjà tel quel

| Endpoint | Usage |
|---|---|
| `POST /api/auth/login/`, `POST /api/auth/refresh/`, `POST /api/auth/logout/`, `GET /api/auth/me/` | Connexion, rotation des tokens, déconnexion, restauration de session. |
| `GET /api/referrals/?status=…` | File des référencements (un appel par statut). |
| `GET /api/referrals/{id}/` | Fiche de référencement. |
| `POST /api/referrals/{id}/status/` | « Patient arrivé » (`recu`), examiné (`vu`), prise en charge (`pris_en_charge`), sortie (`clos`). Gestion du `409` avec `current`. |
| `GET /api/children/{id}/`, `GET /api/children/{id}/measurements/`, `GET /api/measurements/{id}/` | Fiche enfant, historique et courbes. |
| `GET /api/regions/`, `GET /api/facilities/` | Filtres de zone, nom du centre. |

---

## 1. Pas de double authentification (TOTP) — **bloquant**

**Constat.** La spec (section 2) exige un « compte nominatif, double authentification » pour les infirmiers et médecins. `POST /api/auth/login/` renvoie directement les tokens après le PIN. Aucun endpoint TOTP.

**Choix côté web.** Par défaut, le tableau de bord **refuse** une connexion qui n'a pas demandé de code TOTP : il blackliste aussitôt le refresh token reçu et affiche un message. Pour le développement local seulement : `VITE_ALLOW_LOGIN_WITHOUT_TOTP=true`. Ce contrôle côté client n'est pas une protection : seule l'API peut imposer le second facteur.

**Contrat proposé.**

```http
POST /api/auth/login/            { "identifiant": "...", "pin": "..." }
200 → { "double_auth": { "etape": "verification", "jeton": "<jeton court, 5 min>" } }
200 → { "double_auth": { "etape": "enrolement", "jeton": "...", "otpauth_uri": "otpauth://totp/TARANAKA:<id>?secret=...&issuer=TARANAKA" } }

POST /api/auth/totp/verifier/    { "jeton": "...", "code": "123456" }  → 200 { access, refresh, utilisateur }
POST /api/auth/totp/activer/     { "jeton": "...", "code": "123456" }  → 200 { access, refresh, utilisateur }
```

- Le `jeton` n'est pas un token d'accès : il ne sert qu'à l'étape 2.
- `400`/`401` si le code est faux ; même blocage progressif que pour le PIN (`423`).
- Seuls les profils web (`agent_csb`, `superviseur`, `admin`) passent par cette étape ; l'application mobile garde le login par PIN.

---

## 2. Pas de profil « superviseur » — **bloquant**

**Constat.** `CodeProfile` = `beneficiaire`, `asc`, `agent_csb`, `admin`. La spec décrit un superviseur (district, région, programme) qui ne voit **que** des statistiques agrégées.

**Choix côté web.** Le tableau de bord reconnaît un code `superviseur` (`web/src/utils/roles.ts`) : accès aux statistiques seulement, aucune fiche individuelle. `admin` voit les deux espaces. `agent_csb` = infirmier/médecin. `asc` et `beneficiaire` n'ont pas d'écran web (ils utilisent l'application mobile).

**Proposé.** Ajouter `SUPERVISEUR = "superviseur"` à `CodeProfile`, avec une zone (`region_id`, voire district) et **aucun** accès en lecture aux tables cliniques (`referrals`, `children`, `measurements`…).

---

## 3. Pas d'endpoint de statistiques agrégées — **bloquant (superviseur)**

**Constat.** Aucun endpoint d'agrégation. Calculer les statistiques côté client imposerait de télécharger des données individuelles, ce que la spec interdit au superviseur.

**Contrat proposé.**

```http
GET /api/stats/?date_debut=2026-08-01&date_fin=2026-10-31&region_id=1&csb_id=3
200 →
{
  "periode": { "debut": "2026-08-01", "fin": "2026-10-31" },
  "totaux": {
    "depistages": 214, "mam": 17, "mas": 9,
    "referencements": 26, "referencements_arrives": 21,
    "delai_moyen_arrivee_heures": 26.4, "rdv_manques": 6
  },
  "issues_sortie": { "gueri": 11, "transfere": 2, "non_repondant": 0, "abandon": 5, "deces": 1 },
  "par_zone":    [ { "zone_id": 3, "zone_nom": "CRENAS …", "depistages": 120, … } ],
  "par_periode": [ { "periode": "2026-10", "depistages": 83, "mam": 6, "mas": 4 } ]
}
```

- **Petits effectifs.** Le serveur doit remplacer par `null` tout compte de 1 à 4 et toute moyenne ou taux calculé sur moins de 5 cas. Le tableau de bord applique **aussi** cette règle (`web/src/utils/privacy.ts`), plus une suppression secondaire (une seule cellule masquée dans une colonne dont le total est visible → la plus petite autre cellule est masquée), pour qu'une erreur serveur ne puisse rien révéler.
- **Export CSV.** Fait côté client à partir des données déjà protégées : l'export ne peut pas contenir un chiffre masqué à l'écran. Un `GET /api/stats/export.csv` serveur reste utile pour DHIS2 (post-MVP).
- Le périmètre doit être limité par le serveur à la zone du superviseur.

---

## 4. Pas de file des conflits de synchronisation

**Constat.** `HistoriqueVersion.conflit` existe dans le modèle, mais aucun endpoint ne liste ni n'arbitre les conflits. Aujourd'hui une modification concurrente reçoit un `409` et le téléphone doit gérer seul ; la spec (section 9) demande une file « à vérifier » sur le web, sans écrasement automatique.

**Contrat proposé.**

```http
GET  /api/sync/conflits/?statut=ouvert
200 → page de {
  "id": 7, "table_nom": "mesure", "ligne_id": "<uuid>", "date_creation": "...",
  "version_serveur":  { "version": 3, "device_id": "...", "date": "...", "donnees": { ... } },
  "version_appareil": { "version": 3, "device_id": "...", "date": "...", "donnees": { ... } }
}

POST /api/sync/conflits/{id}/resoudre/
     { "choix": "serveur" | "appareil" }
     { "choix": "fusion", "donnees": { "<champ>": <valeur>, ... } }
```

Le web n'envoie que des champs cliniques (les champs de synchro `version`, `updated_at`… sont ignorés). La résolution doit être journalisée dans `journal_audit`.

---

## 5. Pas d'endpoint pour les soins (consultations)

**Constat.** Le modèle `ConsultationNutritionnelle` existe (`nutrition/models.py`) mais n'est routé nulle part. Sans lui, l'infirmier ne peut pas « enregistrer la prise en charge » au-delà du changement de statut.

**Contrat proposé.** `SyncViewSet` standard sur `/api/consultations/`, filtre `?enfant=<uuid>`, écriture réservée à `agent_csb` et `admin`, `agent_medical` = utilisateur connecté.

```json
{ "id": "<uuid client>", "enfant_id": "...", "referencement_id": "...", "csb_id": 3,
  "date": "2026-11-04", "diagnostic": "...", "decision": "prise_en_charge", "observations": "..." }
```

---

## 6. Pas de rendez-vous de contrôle

**Constat.** Aucun modèle ni endpoint pour « programmer un contrôle », ni pour la liste des rendez-vous manqués (spec 7 et 10), qui alimente aussi la statistique `rdv_manques`.

**Contrat proposé.** `/api/rendez-vous/` (`SyncViewSet`), filtre `?enfant=`, champs `enfant_id`, `referencement_id`, `date_prevue`, `motif`, `statut` (`prevu` / `honore` / `manque`, ce dernier calculé par le serveur après la date).

---

## 7. La sortie n'enregistre pas son issue

**Constat.** `POST /api/referrals/{id}/status/` n'accepte que `status` et `version`. La spec impose une issue de sortie (guéri, transféré, non-répondant, abandon / perdu de vue, décédé). `Enfant.statut_prise_en_charge` n'a que `gueri` et `abandon`, et `agent_csb` ne peut pas écrire sur `/children/`.

**Choix côté web.** Avec `status: "clos"`, le web envoie déjà `issue_sortie`, `date_sortie` et `notes`. DRF ignore aujourd'hui ces champs : le dossier est clos, mais **l'issue est perdue**.

**Proposé.** Ajouter `issue_sortie` (+ `date_sortie`, `notes`) au `Referencement`, obligatoire quand `status = clos`, et l'exposer dans `ReferencementSerializer` ; mettre à jour `Enfant.statut_prise_en_charge` dans le même service.

---

## 8. Statuts différents de la spec

| Spec (section 7) | Backend | Libellé web |
|---|---|---|
| Référé | `envoye` | Référé |
| Reçu | `recu` | Patient arrivé |
| — | `vu` | Examiné |
| Pris en charge | `pris_en_charge` | Pris en charge |
| En suivi | — | (absent) |
| Sortie | `clos` | Sortie |

Le backend n'accepte que le statut suivant (`_verifier_ordre`) : le web propose donc une seule action à la fois. « En suivi » manque : à ajouter ou à confirmer avec l'équipe produit.

De même, l'urgence est stockée en `urgente` / `haute` / `normale` alors que la spec parle de rouge / orange / jaune. Le web fait la correspondance (`web/src/utils/triage.ts`) ; des valeurs alignées sur la spec éviteraient l'ambiguïté.

---

## 9. Filtres manquants sur `/api/referrals/`

| Besoin | État | Contournement web |
|---|---|---|
| Recherche par code (`?code_unique=`) | Pas de filtre : le paramètre est ignoré et **toute** la liste est renvoyée. | Le web lit toutes les pages et compare le code exact. Coûteux quand la liste grandit. |
| Référencements d'un enfant (`?enfant=`) | Pas de filtre. | Même contournement. |
| Plusieurs statuts (`?status__in=recu,vu`) | Un seul statut. | Un appel par statut. |
| Tri par urgence puis ancienneté | Tri imposé `-created_at`. | Tri côté client. Proposé : `?ordering=priorite,created_at` avec un ordre explicite des priorités. |

**Proposé.** Ajouter `code_unique` (exact, insensible à la casse), `enfant`, `status__in` et `ordering` à `ReferencementFilter`.

---

## 10. Informations manquantes pour l'infirmier

- **Nom de l'agent communautaire.** `asc_id` seulement ; `agent_csb` ne peut pas lire `/api/profiles/`. Le web affiche « Agent n° 0aa5a6f7 ». Proposé : un champ `asc` imbriqué en lecture seule (`{ nom, prenom, phone }`) dans le référencement.
- **Courbes de référence OMS.** La table `reference_oms` (LMS) existe mais n'est pas exposée : le web trace les mesures de l'enfant et les seuils MAS/MAM, sans les courbes −3 / −2 / 0 / +2 z. Proposé : `GET /api/who-reference/?indicateur=wfa&sexe=F`.
- **Z-scores.** Calculés par le téléphone ; le serveur ne les recalcule pas encore (`TODO` dans `nutrition/services.py`). Le web l'indique sous les courbes.

---

## 11. Divers

- **CORS** non configuré (`django-cors-headers` absent). En développement, le web passe par le proxy Vite (`/api` → `VITE_API_PROXY_TARGET`). En production, servir le web et l'API sur le même domaine, ou ajouter CORS.
- **Messages d'erreur seulement en français.** `Accept-Language` est envoyé (`mg` ou `fr`) mais `LANGUAGE_CODE = 'fr'` et les messages sont écrits en dur. Le web affiche ses propres messages traduits selon le `code` / le statut HTTP. Mais les erreurs de champ (`400`) n'ont pas de code stable et restent en français. Proposé : un `code` par erreur de validation.
- **Lien `next` absolu** dans la pagination : il pointe vers l'hôte du backend, inutilisable derrière le proxy. Le web suit le numéro de page à la place. Proposé : liens relatifs, ou `USE_X_FORWARDED_HOST`.
- **Journal d'audit des consultations web.** Les changements de statut sont journalisés. Il faudra vérifier la même chose pour les endpoints proposés (consultations, rendez-vous, conflits).
