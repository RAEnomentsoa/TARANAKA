# API — problèmes relevés par le tableau de bord web

Ce document liste ce que le tableau de bord web (`web/`) a constaté en utilisant l'API décrite dans `docs/openapi.yaml`, `docs/BACKEND_STATUS.md` et `Backend_serveur/docs/endpoint.md` (branche `Backend_Serveur`, 4 nov. 2026).

Au moment du constat, le backend n'avait pas été modifié ; ce qui a été corrigé depuis est indiqué dans chaque section (« ✅ Corrigé ») et dans le tableau d'état ci-dessous. Les constats ont été vérifiés de deux façons :

- tests unitaires du client ;
- parcours de bout en bout dans un navigateur, sur le vrai serveur Django + PostgreSQL 16 avec `python manage.py charger_demo` : enrôlement TOTP, connexion avec code, file entrante, « Patient arrivé », prise en charge, consultation, contrôle, sortie, fiche enfant, conflits, statistiques, export CSV, refus d'accès du superviseur.

Gravité : **bloquant** (une fonction demandée ne marche pas), **gênant** (contournement côté web), **mineur**.

## État au 4 nov. 2026 (après correction côté backend)

| # | Sujet | État API | Tableau de bord web |
|---|---|---|---|
| 1 | Export CSV et `Accept: text/csv` | ✅ Corrigé | ✅ Contournement retiré : le client demande `Accept: text/csv` (`web/src/api/http.js`, `blob()`). |
| 2 | Suppression complémentaire | ✅ Corrigé (serveur, écran et CSV) | ✅ Suppression complémentaire et règle du taux retirées du client : l'écran affiche exactement ce que le serveur masque, comme le CSV. Seul filet de sécurité gardé : un effectif de 1 à 4 qui arriverait non masqué reste caché (`web/src/utils/privacy.js`). |
| 3 | Double authentification non imposée par défaut | 🟡 Documenté : `TOTP_OBLIGATOIRE=True` en production. Codes de secours : **ouvert** | 🟡 Gardé : le tableau de bord impose toujours l'enrôlement, quel que soit le réglage du serveur. |
| 4 | Nom de l'agent communautaire | ✅ Corrigé | ✅ Nom et téléphone de l'agent (lien d'appel) sur la fiche de référencement ; expéditeur sur chaque conflit (`AgentContact.vue`). |
| 5 | Date de l'étape « En suivi » | ✅ Corrigé | ✅ Chaque étape franchie affiche sa date ; une étape sautée par une sortie directe est marquée « non franchie » (`StatusStepper.vue`). |
| 6 | Courbes de référence OMS | ✅ Corrigé | ✅ Courbes −3, −2, médiane, +2, +3 z sur poids/âge, taille/âge et poids/longueur ou poids/taille (nouveau graphique). Sans table chargée (`404`) : mesures seules, avec un message. |
| 7 | Liens de pagination absolus | ✅ Réglage `USE_X_FORWARDED_HOST` (déploiement) | Gardé : le client suit `?page=n`, ce qui marche avec ou sans ce réglage. |
| 8 | CORS | ✅ Réglage `CORS_ALLOWED_ORIGINS` (déploiement) | Rien à faire : proxy Vite en développement, même domaine recommandé en production. |
| 9 | Messages d'erreur seulement en français | ❌ **Ouvert** (reporté) | Gardé : erreurs connues traduites côté web par leur `code`. |

Le guide de déploiement est `Backend_serveur/docs/deployment.md`, avec l'exemple `Backend_serveur/.env.production.example`.

Vérifié le 4 nov. 2026 sur le serveur réel (PostgreSQL 16, `charger_demo`, tables OMS officielles importées avec `importer_tables_oms`) : export CSV avec `Accept: text/csv` (`200`, `text/csv`), contact de l'agent, `date_suivi` à `null` après une sortie directe, 15 courbes OMS sur la fiche enfant.

Depuis, le code web est passé de TypeScript à JavaScript (types en JSDoc) : les chemins `.ts` cités plus bas dans les constats d'origine sont devenus `.js`.

---

## 1. `GET /api/stats/export/` répond `406` à `Accept: text/csv` — gênant

**Constat.** Un client qui demande poliment du CSV (`Accept: text/csv`) reçoit `406 Not Acceptable`. La vue écrit un `HttpResponse` CSV, mais la négociation de contenu de DRF s'exécute avant, avec les seuls renderers JSON.

**Contournement web.** Le client envoie `Accept: */*` pour cet appel (`web/src/api/http.ts`, `blob()`).

**Proposé.** Déclarer un renderer CSV sur la vue (`renderer_classes = [CSVRenderer]` ou un renderer texte minimal), ou désactiver la négociation pour cette action. Documenter l'en-tête attendu dans `endpoint.md` et `openapi.yaml` (aujourd'hui : `type: string`, sans `text/csv`).

**✅ Corrigé.** La vue a un renderer `text/csv` et choisit toujours le CSV : `Accept: text/csv`, `*/*` et `application/json` renvoient tous le fichier (`200`, `text/csv; charset=utf-8`). `openapi.yaml` décrit la réponse en `text/csv`.

## 2. Pas de suppression complémentaire dans les statistiques — gênant (anonymat)

**Constat.** Limite connue (D11). Avec `grouper_par=region` ou `mois`, une valeur masquée peut se retrouver par soustraction : total − autres groupes. Exemple : total MAS = 9 (visible), région A = 6 (visible), région B = `null` → B = 3.

**Contournement web.** L'écran applique une suppression complémentaire : dans une colonne dont le total est visible et où un seul groupe est masqué, il masque aussi la plus petite autre valeur (`web/src/utils/privacy.ts`). Il masque aussi un taux d'arrivée dont le complément (référencements non arrivés) est de 1 à 4.

**Reste ouvert.** L'export CSV vient du serveur, parce qu'il est **journalisé** (`export_csv`), ce qu'un export côté navigateur ne serait pas. Il contient donc les valeurs que l'écran masque en plus. Il faut appliquer la même suppression complémentaire dans `statistiques/services.py`, pour l'écran comme pour le CSV.

**✅ Corrigé côté serveur** (`statistiques/services.py`, D11). Pour chaque effectif, si un seul groupe est masqué alors que le total est visible, la plus petite autre valeur est masquée aussi (s'il n'y a pas d'autre groupe, le total est masqué). Les arrivées et le taux d'arrivée sont masqués quand 1 à 4 référencements ne sont pas arrivés. L'écran (`/api/stats/`) et le CSV masquent maintenant exactement les mêmes valeurs ; le web peut garder sa règle sans effet supplémentaire, ou la retirer.

## 3. La double authentification n'est pas imposée par défaut — gênant (sécurité)

**Constat.** La spec §2 exige la double authentification pour les comptes web. Avec `TOTP_OBLIGATOIRE=False` (valeur par défaut), un `agent_csb`, `superviseur` ou `admin` sans 2FA reçoit des tokens complets avec son seul PIN.

**Choix côté web.** Après la connexion, le tableau de bord lit `GET /api/auth/2fa/`. Si `requise_pour_ce_profil` est vrai et `active` faux, il impose l'enrôlement (`setup` puis `activate`) avant d'ouvrir le moindre écran. Il ne restaure pas non plus une session rechargée sans 2FA. Ce contrôle côté client ne protège pas l'API, qui reste ouverte à quiconque a le PIN.

**Proposé.** `TOTP_OBLIGATOIRE=True` en production, comme le recommande `BACKEND_STATUS.md` §5. Prévoir des codes de secours : aujourd'hui, un téléphone perdu demande l'intervention d'un admin (`reset-2fa`).

**🟡 Réglage gardé, documenté.** `TOTP_OBLIGATOIRE=True` figure dans `Backend_serveur/.env.production.example` et `Backend_serveur/docs/deployment.md`. Avec ce réglage, c'est l'API elle-même qui refuse un compte web sans 2FA, pas seulement le tableau de bord. **Ouvert :** codes de secours (reportés).

## 4. Nom de l'agent communautaire absent du référencement — mineur

**Constat.** Le référencement ne donne que `asc_id`, et `agent_csb` ne peut pas lire `/api/profiles/`. L'infirmier ne sait pas qui appeler pour un patient non arrivé.

**Contournement web.** « Agent n° 68fc8307 » (8 premiers caractères de l'identifiant).

**Proposé.** Un champ imbriqué en lecture seule `asc: { nom, prenom, phone }` dans `ReferencementSerializer`. Même besoin pour `user_id` dans `/api/conflicts/` (qui a envoyé la version du téléphone).

**✅ Corrigé.** Les référencements ont `asc: { nom, prenom, phone }` (aussi dans `/incoming/` et `/sync/pull/`) et les conflits `expediteur: { nom, prenom, phone }`. Visibles seulement par le personnel (`asc`, `agent_csb`, `admin`) ; `null` pour une bénéficiaire. Le superviseur n'a pas accès à ces endpoints.

## 5. Pas de date pour l'étape « En suivi » — mineur

**Constat.** Le serveur remplit `date_reception`, `date_prise_en_charge` et `date_sortie`, mais aucune date de passage en `en_suivi`. Après une sortie directe depuis `pris_en_charge` (autorisée, D7), on ne peut pas savoir si le dossier est passé par le suivi.

**Choix côté web.** Pour un dossier sorti, toutes les étapes sont affichées comme franchies.

**Proposé.** Ajouter `date_suivi`, ou exposer l'historique des statuts (il existe dans `journal_audit`).

**✅ Corrigé.** Nouveau champ `date_suivi`, rempli par le serveur au passage en `en_suivi`. Pour les lignes existantes, la migration l'a retrouvé dans le journal d'audit. Un dossier sorti avec `date_suivi` à `null` n'est pas passé par le suivi.

## 6. Courbes de référence OMS non exposées — mineur

**Constat.** La table `reference_oms` (LMS) est utilisée pour calculer les z-scores, mais aucun endpoint ne la sert. Le web trace donc les mesures de l'enfant et les seuils MAS / MAM (z = −3 / −2, PB 115 / 125 mm), sans les courbes −3, −2, 0, +2 z.

**Proposé.** `GET /api/who-reference/?indicateur=wfa&sexe=F`. Il servirait aussi au téléphone.

**✅ Corrigé.** `GET /api/who-reference/?indicateur=wfl&sexe=M&cle_min=45&cle_max=110&pas=1` renvoie, pour chaque clé, les valeurs LMS officielles et les courbes `-3`, `-2`, `0`, `2`, `3` z calculées avec la formule OMS. Seules les tables OMS chargées (`importer_tables_oms`) sont servies : `404` si la table n'est pas chargée, jamais de valeurs inventées. `pas` échantillonne (par exemple `30` jours pour `wfa`/`lhfa`).

## 7. Liens de pagination absolus — mineur

**Constat.** `next` et `previous` contiennent l'hôte vu par Django (`http://127.0.0.1:8000/...`). Derrière un proxy ou un autre domaine, ces liens ne sont pas utilisables tels quels.

**Contournement web.** Le client suit le numéro de page (`?page=n`) au lieu du lien (`HttpClient.getAll`).

**Proposé.** `USE_X_FORWARDED_HOST = True` derrière le proxy de production, ou des liens relatifs.

**✅ Réglage ajouté.** Variable d'environnement `USE_X_FORWARDED_HOST=True` derrière le proxy (qui doit transmettre `X-Forwarded-Host`). Voir `deployment.md`. Le contournement du web (`?page=n`) reste valable.

## 8. CORS non configuré — mineur (déploiement)

**Constat.** Aucun `django-cors-headers`. En développement, le web passe par le proxy Vite (`/api` → `VITE_API_PROXY_TARGET`).

**Proposé.** Servir le web et l'API sur le même domaine en production (le plus simple), ou ajouter une liste d'origines autorisées.

**✅ Réglage ajouté.** `django-cors-headers` avec `CORS_ALLOWED_ORIGINS` (vide par défaut = aucun accès d'une autre origine). En-têtes autorisés : `Authorization`, `Content-Type`, `X-Device-Id`, `Content-Encoding` ; exposés : `Content-Disposition`, `ETag`. Le même domaine reste recommandé (`deployment.md`).

## 9. Messages d'erreur seulement en français — mineur

**Constat.** `LANGUAGE_CODE = 'fr'`, sans `LocaleMiddleware`. Les messages (`detail`, erreurs de champ) sont en français quel que soit `Accept-Language`, que le web envoie (`mg` ou `fr`).

**Contournement web.** Les erreurs connues sont traduites côté web à partir de leur `code` (`identifiants_incorrects`, `compte_bloque`, `totp_invalide`…) ou du statut HTTP. Les erreurs de champ (`400`) n'ont pas de code stable : elles s'affichent en français, même en malagasy.

**Proposé.** Un `code` par erreur de validation, ou des messages traduits en malagasy côté serveur.

**❌ Ouvert** (reporté). Les traductions en malagasy devront être relues par des locuteurs natifs.

---

## Écarts de documentation

| Sujet | Constat | État |
|---|---|---|
| `openapi.yaml`, `/api/stats/export/` | Réponse décrite comme `application/json` `type: string` ; c'est du `text/csv` (voir §1). | ✅ Corrigé : `text/csv` |
| `openapi.yaml`, `Conflit.donnees_telephone` / `donnees_serveur` | Sans type (`{}`) ; ce sont des objets. **Correction :** pour une suppression, `donnees_telephone` vaut `{}` (objet vide), pas `null` (vérifié dans `synchro/sync.py` et par un test). | ✅ Corrigé : `type: object` |
| `endpoint.md`, `/api/stats/` | L'exemple de réponse est juste, mais `groupes[]` (`cle`, `libelle`, `indicateurs`, `masques`) n'est décrit que dans `openapi.yaml`. | ✅ Décrit dans `endpoint.md` |
| `openapi.yaml`, `PointOms` (`/api/who-reference/`) | `cle`, `l`, `m`, `s` sont décrits en chaînes décimales (`type: string, format: decimal`, comme dans l'exemple de `endpoint.md` : `"cle": "75.0"`), mais le serveur renvoie des **nombres** (`"cle": 300.0, "l": -0.1674`). Le web accepte les deux (`Number(cle)`). | ❌ **Ouvert** (mineur) : aligner le schéma ou la réponse. |

## Ce que le tableau de bord utilise

| Écran | Endpoints |
|---|---|
| Connexion | `POST /api/auth/login/` (+ `code_totp`), `GET /api/auth/2fa/`, `POST /api/auth/2fa/setup/`, `POST /api/auth/2fa/activate/`, `POST /api/auth/refresh/`, `POST /api/auth/logout/`, `GET /api/auth/me/` |
| File | `GET /api/referrals/incoming/`, `GET /api/referrals/?status=`, `POST /api/referrals/{id}/status/` |
| Recherche | `GET /api/referrals/?code=` |
| Référencement | `GET /api/referrals/{id}/` (dont `asc` et `date_suivi`), `GET /api/measurements/{id}/`, `GET /api/facilities/`, `POST /api/referrals/{id}/status/` (dont `sortie` + `issue_sortie`) |
| Fiche enfant | `GET /api/children/{id}/`, `GET /api/children/{id}/measurements/`, `GET /api/referrals/?enfant=`, `GET /api/who-reference/` (`wfa`, `lhfa`, `wfl` ou `wfh`) |
| Soins | `GET/POST /api/consultations/?enfant=`, `GET/POST /api/appointments/?enfant=`, `PATCH /api/appointments/{id}/` (`honore`) |
| Conflits | `GET /api/conflicts/?statut=a_verifier` (dont `expediteur`), `POST /api/conflicts/{id}/resolve/` |
| Statistiques | `GET /api/regions/`, `GET /api/stats/?grouper_par=region|mois`, `GET /api/stats/export/` (`Accept: text/csv`) |
