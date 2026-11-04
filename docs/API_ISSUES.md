# API — problèmes relevés par le tableau de bord web

Ce document liste ce que le tableau de bord web (`web/`) a constaté en utilisant l'API décrite dans `docs/openapi.yaml`, `docs/BACKEND_STATUS.md` et `Backend_serveur/docs/endpoint.md` (branche `Backend_Serveur`, 4 nov. 2026).

Le backend n'a **pas** été modifié. Tout a été vérifié de deux façons :

- tests unitaires du client ;
- parcours de bout en bout dans un navigateur, sur le vrai serveur Django + PostgreSQL 16 avec `python manage.py charger_demo` : enrôlement TOTP, connexion avec code, file entrante, « Patient arrivé », prise en charge, consultation, contrôle, sortie, fiche enfant, conflits, statistiques, export CSV, refus d'accès du superviseur.

Gravité : **bloquant** (une fonction demandée ne marche pas), **gênant** (contournement côté web), **mineur**.

---

## 1. `GET /api/stats/export/` répond `406` à `Accept: text/csv` — gênant

**Constat.** Un client qui demande poliment du CSV (`Accept: text/csv`) reçoit `406 Not Acceptable`. La vue écrit un `HttpResponse` CSV, mais la négociation de contenu de DRF s'exécute avant, avec les seuls renderers JSON.

**Contournement web.** Le client envoie `Accept: */*` pour cet appel (`web/src/api/http.ts`, `blob()`).

**Proposé.** Déclarer un renderer CSV sur la vue (`renderer_classes = [CSVRenderer]` ou un renderer texte minimal), ou désactiver la négociation pour cette action. Documenter l'en-tête attendu dans `endpoint.md` et `openapi.yaml` (aujourd'hui : `type: string`, sans `text/csv`).

## 2. Pas de suppression complémentaire dans les statistiques — gênant (anonymat)

**Constat.** Limite connue (D11). Avec `grouper_par=region` ou `mois`, une valeur masquée peut se retrouver par soustraction : total − autres groupes. Exemple : total MAS = 9 (visible), région A = 6 (visible), région B = `null` → B = 3.

**Contournement web.** L'écran applique une suppression complémentaire : dans une colonne dont le total est visible et où un seul groupe est masqué, il masque aussi la plus petite autre valeur (`web/src/utils/privacy.ts`). Il masque aussi un taux d'arrivée dont le complément (référencements non arrivés) est de 1 à 4.

**Reste ouvert.** L'export CSV vient du serveur, parce qu'il est **journalisé** (`export_csv`), ce qu'un export côté navigateur ne serait pas. Il contient donc les valeurs que l'écran masque en plus. Il faut appliquer la même suppression complémentaire dans `statistiques/services.py`, pour l'écran comme pour le CSV.

## 3. La double authentification n'est pas imposée par défaut — gênant (sécurité)

**Constat.** La spec §2 exige la double authentification pour les comptes web. Avec `TOTP_OBLIGATOIRE=False` (valeur par défaut), un `agent_csb`, `superviseur` ou `admin` sans 2FA reçoit des tokens complets avec son seul PIN.

**Choix côté web.** Après la connexion, le tableau de bord lit `GET /api/auth/2fa/`. Si `requise_pour_ce_profil` est vrai et `active` faux, il impose l'enrôlement (`setup` puis `activate`) avant d'ouvrir le moindre écran. Il ne restaure pas non plus une session rechargée sans 2FA. Ce contrôle côté client ne protège pas l'API, qui reste ouverte à quiconque a le PIN.

**Proposé.** `TOTP_OBLIGATOIRE=True` en production, comme le recommande `BACKEND_STATUS.md` §5. Prévoir des codes de secours : aujourd'hui, un téléphone perdu demande l'intervention d'un admin (`reset-2fa`).

## 4. Nom de l'agent communautaire absent du référencement — mineur

**Constat.** Le référencement ne donne que `asc_id`, et `agent_csb` ne peut pas lire `/api/profiles/`. L'infirmier ne sait pas qui appeler pour un patient non arrivé.

**Contournement web.** « Agent n° 68fc8307 » (8 premiers caractères de l'identifiant).

**Proposé.** Un champ imbriqué en lecture seule `asc: { nom, prenom, phone }` dans `ReferencementSerializer`. Même besoin pour `user_id` dans `/api/conflicts/` (qui a envoyé la version du téléphone).

## 5. Pas de date pour l'étape « En suivi » — mineur

**Constat.** Le serveur remplit `date_reception`, `date_prise_en_charge` et `date_sortie`, mais aucune date de passage en `en_suivi`. Après une sortie directe depuis `pris_en_charge` (autorisée, D7), on ne peut pas savoir si le dossier est passé par le suivi.

**Choix côté web.** Pour un dossier sorti, toutes les étapes sont affichées comme franchies.

**Proposé.** Ajouter `date_suivi`, ou exposer l'historique des statuts (il existe dans `journal_audit`).

## 6. Courbes de référence OMS non exposées — mineur

**Constat.** La table `reference_oms` (LMS) est utilisée pour calculer les z-scores, mais aucun endpoint ne la sert. Le web trace donc les mesures de l'enfant et les seuils MAS / MAM (z = −3 / −2, PB 115 / 125 mm), sans les courbes −3, −2, 0, +2 z.

**Proposé.** `GET /api/who-reference/?indicateur=wfa&sexe=F`. Il servirait aussi au téléphone.

## 7. Liens de pagination absolus — mineur

**Constat.** `next` et `previous` contiennent l'hôte vu par Django (`http://127.0.0.1:8000/...`). Derrière un proxy ou un autre domaine, ces liens ne sont pas utilisables tels quels.

**Contournement web.** Le client suit le numéro de page (`?page=n`) au lieu du lien (`HttpClient.getAll`).

**Proposé.** `USE_X_FORWARDED_HOST = True` derrière le proxy de production, ou des liens relatifs.

## 8. CORS non configuré — mineur (déploiement)

**Constat.** Aucun `django-cors-headers`. En développement, le web passe par le proxy Vite (`/api` → `VITE_API_PROXY_TARGET`).

**Proposé.** Servir le web et l'API sur le même domaine en production (le plus simple), ou ajouter une liste d'origines autorisées.

## 9. Messages d'erreur seulement en français — mineur

**Constat.** `LANGUAGE_CODE = 'fr'`, sans `LocaleMiddleware`. Les messages (`detail`, erreurs de champ) sont en français quel que soit `Accept-Language`, que le web envoie (`mg` ou `fr`).

**Contournement web.** Les erreurs connues sont traduites côté web à partir de leur `code` (`identifiants_incorrects`, `compte_bloque`, `totp_invalide`…) ou du statut HTTP. Les erreurs de champ (`400`) n'ont pas de code stable : elles s'affichent en français, même en malagasy.

**Proposé.** Un `code` par erreur de validation, ou des messages traduits en malagasy côté serveur.

---

## Écarts de documentation

| Sujet | Constat |
|---|---|
| `openapi.yaml`, `/api/stats/export/` | Réponse décrite comme `application/json` `type: string` ; c'est du `text/csv` (voir §1). |
| `openapi.yaml`, `Conflit.donnees_telephone` / `donnees_serveur` | Sans type (`{}`) ; ce sont des objets, et `donnees_telephone` vaut `null` pour une suppression. |
| `endpoint.md`, `/api/stats/` | L'exemple de réponse est juste, mais `groupes[]` (`cle`, `libelle`, `indicateurs`, `masques`) n'est décrit que dans `openapi.yaml`. |

## Ce que le tableau de bord utilise

| Écran | Endpoints |
|---|---|
| Connexion | `POST /api/auth/login/` (+ `code_totp`), `GET /api/auth/2fa/`, `POST /api/auth/2fa/setup/`, `POST /api/auth/2fa/activate/`, `POST /api/auth/refresh/`, `POST /api/auth/logout/`, `GET /api/auth/me/` |
| File | `GET /api/referrals/incoming/`, `GET /api/referrals/?status=`, `POST /api/referrals/{id}/status/` |
| Recherche | `GET /api/referrals/?code=` |
| Référencement | `GET /api/referrals/{id}/`, `GET /api/measurements/{id}/`, `GET /api/facilities/`, `POST /api/referrals/{id}/status/` (dont `sortie` + `issue_sortie`) |
| Fiche enfant | `GET /api/children/{id}/`, `GET /api/children/{id}/measurements/`, `GET /api/referrals/?enfant=` |
| Soins | `GET/POST /api/consultations/?enfant=`, `GET/POST /api/appointments/?enfant=`, `PATCH /api/appointments/{id}/` (`honore`) |
| Conflits | `GET /api/conflicts/?statut=a_verifier`, `POST /api/conflicts/{id}/resolve/` |
| Statistiques | `GET /api/regions/`, `GET /api/stats/?grouper_par=region|mois`, `GET /api/stats/export/` |
