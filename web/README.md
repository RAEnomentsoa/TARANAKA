# TARANAKA — tableau de bord web

Tableau de bord des CSB, CRENAS, CRENI et des superviseurs (section 10 de `docs/SPEC.md`).
Vue 3, TypeScript, Vite, Pinia, Vue Router, vue-i18n (malagasy et français).

## Démarrer

```bash
cd web
npm install
cp .env.example .env.local   # à adapter
npm run dev                   # http://localhost:5173, /api est relayé vers le backend Django
```

Le backend doit tourner sur `VITE_API_PROXY_TARGET` (par défaut `http://127.0.0.1:8000`).

| Commande | Rôle |
|---|---|
| `npm run dev` | Serveur de développement |
| `npm test` | Tests unitaires et de composants (Vitest + Vue Test Utils) |
| `npm run lint` | ESLint, dont la règle qui interdit tout texte en dur dans les templates |
| `npm run typecheck` | Vérification TypeScript (`vue-tsc`) |
| `npm run build` | Vérification des types puis build de production dans `dist/` |

### Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `VITE_API_BASE_URL` | vide | URL de l'API. Vide = même domaine (`/api`). |
| `VITE_API_PROXY_TARGET` | `http://127.0.0.1:8000` | Cible du proxy de développement. |
| `VITE_IDLE_TIMEOUT_MINUTES` | `15` | Déconnexion automatique après inactivité. |
| `VITE_ALLOW_LOGIN_WITHOUT_TOTP` | `false` | **Développement uniquement** : accepte une connexion sans second facteur, tant que le backend n'a pas le TOTP. |

## Écrans et rôles

| Profil (`profile.code`) | Écrans |
|---|---|
| `agent_csb` (infirmier / médecin) | File des référencements, fiche de référencement, fiche enfant, recherche par code, conflits de synchronisation |
| `superviseur` (proposé, voir `docs/API_ISSUES.md`) | Statistiques agrégées et export CSV |
| `admin` | Tous les écrans |
| `asc`, `beneficiaire` | Aucun : connexion refusée, ils utilisent l'application mobile |

- **File** : triée par urgence (rouge, orange, jaune) puis du plus ancien au plus récent ; « Patient arrivé » en un clic (avec confirmation).
- **Fiche de référencement** : étapes du dossier, une seule action suivante (le backend impose l'ordre des statuts), consultations, contrôles, sortie avec issue.
- **Fiche enfant** : âge calculé, historique des mesures, courbes (poids/âge, taille/âge, P/T en z-score, PB avec seuils MAS/MAM), table de données pour chaque courbe.
- **Conflits** : les deux versions côte à côte, choix champ par champ, jamais d'écrasement automatique.
- **Statistiques** : par période et zone, sans aucune donnée nominative ; tout chiffre portant sur moins de 5 cas (ou déductible par soustraction) est remplacé par « < 5 », à l'écran comme dans le CSV.

## Organisation du code

```
src/
  api/          couche HTTP (client, erreurs, un module par ressource, types)
  stores/       Pinia : auth (connexion en 2 étapes), référencements, référentiel, notifications
  router/       routes et gardes par permission
  utils/        logique pure testée : rôles, tri, anonymat, CSV, dates, conflits, échelles
  composables/  useAsync, useFormatters, useIdleLogout, useNow, useAnnouncer
  components/   ui/ (boutons, champs, dialogues, badges…), charts/, referrals/, children/, stats/, auth/, layout/
  views/        une vue par écran (auth/, staff/, supervisor/)
  i18n/         fr.json et mg.json (mêmes clés, vérifié par les tests)
  styles/       jetons de design et styles de base
tests/          tests unitaires et de composants
```

Les endpoints que le backend n'a pas encore sont marqués `proposed` dans `src/api/` et décrits dans `docs/API_ISSUES.md`. Tant qu'ils n'existent pas, l'écran concerné indique que la fonction n'est pas encore disponible sur le serveur.

## Accessibilité

- Zones cliquables ≥ 48 px, contrastes AA (ratios notés dans `src/styles/tokens.css`), tailles en `rem` : le texte s'agrandit avec le navigateur.
- Lien d'évitement, titre de page focalisé et annoncé à chaque navigation, `lang` du document mis à jour avec la langue.
- Urgence jamais signalée par la couleur seule (forme + mot) ; « < 5 » expliqué aux lecteurs d'écran.
- Dialogues natifs `<dialog>` (piège du focus, Échap, retour du focus), onglets ARIA au clavier, erreurs de formulaire reliées aux champs.
- Graphiques : résumé texte, points focalisables avec infobulle, tableau des valeurs à la demande.
- `prefers-reduced-motion` et `forced-colors` respectés ; mise en page responsive jusqu'à 320 px.

## Traductions

Aucun texte affiché n'est écrit en dur : la règle ESLint `vue/no-bare-strings-in-template` le vérifie, et les tests vérifient que `fr.json` et `mg.json` ont les mêmes clés, les mêmes variables et les mêmes formes de pluriel. **Les textes malagasy doivent être relus par des locuteurs des principales régions avant la mise en production** (section 11 de la spec).
