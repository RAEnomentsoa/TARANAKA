# TARANAKA — application mobile (Android, Flutter)

Application Android **hors ligne d'abord**, malagasy / français, décrite dans
`docs/SPEC.md` : mode personnel (Mon cycle, Ma grossesse, Mon enfant) et mode
agent (dépistage de la malnutrition, référencements, synchronisation avec le
backend Django de `Backend_serveur/`).

> **Configuration clinique d'exemple — À VALIDER.** Les seuils, calendriers,
> signes de danger et conseils viennent de
> `assets/config/clinical_config_v1.json`, copie exacte de
> `Backend_serveur/config_clinique/exemples/config_clinique_exemple.json`.
> Aucune valeur n'a été validée par écrit (spec §11). L'application l'affiche
> sur chaque accueil. Ne pas utiliser pour soigner.

## État

| Partie | État | Tests |
|---|---|---|
| 1. Socle hors ligne : SQLite chiffrée (SQLCipher), profils à PIN, FR/MG, configuration | ✅ | chiffrement réel (libsqlcipher), registre des profils, délai PIN, configuration, parité FR/MG, parcours de premier lancement |
| 2. Mode agent : dépistage, référencement hors ligne, outbox avec le vrai backend | ✅ (z-scores : voir « Tables OMS ») | règles = cas du serveur, outbox contre un faux serveur, **intégration contre le vrai backend** |
| 3. Mon enfant | ✅ (courbes OMS : voir « Tables OMS ») | indicateurs alimentaires, vaccins, scénario 4, alerte |
| 4. Ma grossesse, alertes rouges | ✅ | dates, CPN, scénario 3 en mode avion, post-partum |
| 5. Mon cycle | ✅ | prévisions, confiance, signaux, scénario 2 |
| APK de release | ❌ **non construit ici** | voir « APK » |

`flutter analyze` : aucun problème. `flutter test` : **157 tests réussis**
(+ 1 test d'intégration lancé contre le backend, + scripts de captures).

### Ce qui manque ou reste à faire

- **APK non construit dans cet environnement** : l'hôte du SDK Android
  (`dl.google.com`) est bloqué par la politique réseau. Tout le reste
  (Flutter, pub.dev, Maven) était accessible. Voir « APK ».
- **Tables OMS absentes du dépôt** : aucun z-score ni courbe OMS n'est calculé
  sur le téléphone (rien n'est inventé). Fichiers à ajouter : voir « Tables OMS ».
- **Textes malagasy** : l'interface est traduite à 100 % (`lib/l10n/app_mg.arb`)
  mais **doit être relue par des locuteurs natifs**. Les textes cliniques de la
  configuration ont `"mg": null` (à écrire et faire valider) : l'application
  affiche alors le français.
- **Audio malagasy** (spec §1) : aucun fichier audio n'existe ; pas de bouton.
- **Rappels** : affichés dans l'application (accueil : prochaine CPN dans les
  7 jours, vaccins en retard), sans notification système.
- **Synchronisation facultative du mode personnel** (spec §9) : non activée.
  Les données personnelles restent sur le téléphone ; le cycle n'est jamais
  mis en file d'envoi. Pour « Mon enfant », l'API ne le permet pas
  (`docs/API_ISSUES.md` M1). Grossesse et cycle sont ouverts en écriture à une
  bénéficiaire côté API : à brancher sur le même moteur d'outbox.
- Non faits : mode discret (icône et nom neutres), photo du carnet de santé,
  fiche de référencement en PDF (la fiche plein écran se copie en texte),
  contenus hebdomadaires de grossesse et contenus sur le cycle (bibliothèque
  validée à fournir), statistiques d'usage, test sur 3 téléphones réels.

## Prérequis

- Flutter **3.47.9** (Dart 3.13.7), comme utilisé ici.
- Pour construire l'APK : SDK Android (plateforme récente + build-tools) et le
  NDK indiqué par Flutter (`flutter doctor`), JDK 17+.
- Pour lancer les tests sur l'hôte : **SQLCipher** (les tests vérifient le vrai
  chiffrement) :

```bash
sudo apt install libsqlcipher-dev
```

## Démarrer

```bash
cd mobile
flutter pub get
flutter test
```

Lancer sur un émulateur ou un téléphone (build debug) avec le backend de
démonstration (voir `docs/DEMO.md` pour le charger) :

```bash
flutter run --dart-define=TARANAKA_API=http://10.0.2.2:8000
```

`10.0.2.2` est l'ordinateur vu depuis l'émulateur Android. Sur un vrai
téléphone, utilisez l'adresse de l'ordinateur sur le même Wi-Fi
(`http://192.168.x.y:8000`, serveur lancé avec `runserver 0.0.0.0:8000`).
**Seuls les builds debug acceptent `http://`** ; un build release n'accepte
que HTTPS. L'adresse peut aussi être changée sur l'écran de connexion agent
(« Adresse du serveur »).

## Comptes de démonstration

Données fictives chargées par `python manage.py charger_demo` (`docs/DEMO.md`).

| Sur le téléphone | Identifiant | Code du compte | Pour |
|---|---|---|---|
| Profil « agent de santé » | `ac.rasoa` | `1234` | Scénarios 5, 7, 8 (Analamanga, enfant **Soa**) |
| Profil « agent de santé » | `ac.hery` | `1235` | Autre agent |
| Profil « agent de santé » | `ac.antsirabe` | `1236` | Autre région |

- **Mode personnel** : pas de compte. On crée un profil (prénom + code à
  4 chiffres) au premier lancement.
- **Mode agent** : on crée un profil « Je suis agent de santé » avec son propre
  code local à 4 chiffres, puis on se connecte **une fois en ligne** avec
  l'identifiant et le code du compte ci-dessus. Ensuite tout marche hors ligne.
- Côté web (`web/`), `inf.crenas` / `3333` voit le référencement et clique
  « Patient arrivé » (scénario 8).

### Rejouer les scénarios de la spec (§13)

1. Premier lancement : Malagasy → consentement → prénom + code → « Ho ahy sy
   ny fianakaviako » → accueil, sans réseau.
2. Mon cycle : saisir 4 débuts de règles espacés de 28–29 jours (« Une autre
   date ») → « Fiable », prochaines règles, fenêtre fertile, avertissement.
3. Ma grossesse : DDR = aujourd'hui − 84 jours → « 12 SA + 0 j », DPA,
   prochaine CPN ; un tap sur « Saignement vaginal » ouvre l'alerte (mode avion).
4. Mon enfant : enfant de 9 mois, « Repas du jour », toucher vary, anana, lait
   maternel → 3/8 « Insuffisante » et le conseil « Ajoutez un œuf… ».
5. Agent `ac.rasoa`, mode avion : Dépister → **Soa** → poids 8,6, taille 77,5,
   PB 112 → MAS, CRENAS, urgence orange → fiche avec code, « Non transmise ».
6. Tout ce qui précède en mode avion ; les données restent après redémarrage.
7. Réseau revenu : « Synchroniser maintenant » → « Transmise au serveur ».
8. Web : `inf.crenas` clique « Patient arrivé » → après synchronisation, la
   fiche affiche « Reçu par le centre ».

## Installer l'APK

### Construire

Sur une machine avec le SDK Android :

```bash
cd mobile
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
```

`--obfuscate --split-debug-info` retire les noms des symboles Dart du code
compilé (−570 Ko par APK). Gardez le dossier `build/symbols` de chaque version
publiée : il sert à relire une trace d'erreur avec
`flutter symbolize -i <trace> -d build/symbols/app.android-arm64.symbols`.

Les fichiers sont dans `build/app/outputs/flutter-apk/` :

- `app-arm64-v8a-release.apk` : la plupart des téléphones récents ;
- `app-armeabi-v7a-release.apk` : beaucoup de téléphones d'entrée de gamme
  sous Android 8 sont en 32 bits ;
- `app-x86_64-release.apk` : émulateurs.

Sans `android/key.properties`, l'APK est signé avec la clé de debug (démo
seulement). Pour une vraie signature, créez une clé puis
`android/key.properties` (jamais commité) :

```properties
storeFile=/chemin/vers/taranaka.jks
storePassword=...
keyAlias=taranaka
keyPassword=...
```

### Installer sur un téléphone

Avec un câble USB (débogage USB activé) :

```bash
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Sans ordinateur : copier l'APK sur le téléphone (Bluetooth, carte SD, partage
de fichiers), l'ouvrir et autoriser « Installer des applications inconnues »
pour l'application qui l'ouvre. Android 8.0 minimum.

## Taille de l'APK (cible < 30 Mo)

**Mesuré** le 07/11/2026 (Flutter 3.47.9, commande ci-dessus) :

| APK | Taille |
|---|---|
| `app-arm64-v8a-release.apk` | **10,6 Mo** |
| `app-armeabi-v7a-release.apk` | **9,7 Mo** |
| `app-x86_64-release.apk` (émulateurs) | 11,0 Mo |

Détail pour arm64 (taille dans l'APK, compressée) :

| Élément | Taille |
|---|---|
| Moteur Flutter (`libflutter.so`) | 5,5 Mo |
| SQLCipher (`libsqlcipher.so`, chiffrement de la base) | 2,3 Mo |
| Code Dart de l'application et du framework (`libapp.so`) | 2,2 Mo |
| `classes.dex`, ressources, assets, licences | ≈ 0,6 Mo |

- Les bibliothèques natives sont stockées compressées
  (`useLegacyPackaging = true` dans `android/app/build.gradle.kts`). Sans ce
  réglage, Android 8+ les garde non compressées : ≈ 26 Mo pour arm64.
- Sans `--split-per-abi`, l'APK « universel » embarque SQLCipher pour les trois
  architectures : 15,6 Mo pour arm64 seul, davantage avec toutes les
  architectures. Utiliser `--split-per-abi`.
- Pour voir le détail : `flutter build apk --release --target-platform android-arm64 --analyze-size`.

## Tests

```bash
flutter test                                   # 157 tests
TARANAKA_API=http://localhost:8000 flutter test test/integration   # vrai backend
TARANAKA_SCREENSHOTS=1 flutter test --update-goldens test/screenshots   # captures PNG
```

- Tests unitaires de **tous les calculs** : règles cliniques (les cas du
  serveur `nutrition/tests_classification.py` rejoués), z-scores OMS (formule
  LMS, méthode restreinte, arrondi identique au serveur, sur les lignes OMS
  publiées déjà dans le dépôt), âge et correction de taille, indicateurs
  alimentaires, vaccins, dates de grossesse, CPN, cycle.
- Tests d'interface des scénarios 1 à 5 et 7–8, des alertes, du verrouillage.
- Accessibilité : parcours personnel (FR et MG) et agent à **320 dp avec texte
  à 200 %**, sans débordement.
- Intégration (`test/integration/real_backend_test.dart`) contre le serveur
  Django réel avec `charger_demo` : connexion `ac.rasoa`, scénario 5 hors ligne
  puis synchronisé (le serveur reclasse MAS / CRENAS / orange), renvoi forcé
  sans doublon, conflit visible par `inf.crenas`, « Patient arrivé » reçu.

Non testé : vrais téléphones, TalkBack, build Android (voir ci-dessus).

## Architecture

Par fonctionnalité, avec `domain` (calculs purs, testés), `data` (SQLite,
API) et `presentation` (écrans) :

```
lib/
  app/             services, session (profils, verrouillage), MaterialApp
  core/
    alerts/        alerte rouge plein écran, signes de danger, contacts
    config/        configuration clinique versionnée, moteur de règles
    db/            SQLCipher, migrations
    growth/        formule LMS OMS, lecture des tables
    i18n/          FR/MG, repli des textes du framework
    security/      clés, PIN, profils
    sync/          outbox, client API, moteur de synchronisation, statuts
    theme/         jetons de design (bleu clair et blanc, une couleur d'accent)
    widgets/       composants partagés
  features/
    onboarding/ profiles/ home/ settings/
    agent/         dépistage, référencements, relances, synchronisation
    child/         Mon enfant
    pregnancy/     Ma grossesse
    cycle/         Mon cycle
  l10n/            app_fr.arb, app_mg.arb
assets/config/     configuration clinique d'exemple (À VALIDER)
assets/who/        tables OMS à ajouter
```

### Sécurité et données (spec §8)

- Une base SQLCipher par profil. Sa clé est aléatoire ; elle n'est stockée
  qu'enveloppée par une clé dérivée du **PIN** et d'un secret gardé dans le
  **Keystore Android**. Sans le téléphone, les 10 000 PIN ne peuvent pas être
  essayés hors ligne. Changer de PIN ne rechiffre pas la base.
- 5 PIN faux → 30 s, puis 1 min, 5 min, 15 min. Verrouillage après 2 minutes
  sans activité. Question de secours facultative (mode personnel) ; sinon
  réinitialisation avec perte des données, clairement annoncée. Agent : PIN
  réinitialisé par le superviseur, profil recréé, données synchronisées
  restaurées.
- Captures d'écran bloquées (`FLAG_SECURE`), pas de sauvegarde Android.
- « Effacer toutes mes données » supprime le profil et son fichier.

### Synchronisation (spec §9)

- Chaque écriture du mode agent et son opération d'outbox sont dans la même
  transaction (UUID et clé d'idempotence générés sur le téléphone).
- `POST /api/sync/push/` par lots de 100, gzip, dans l'ordre, une seule
  opération par ligne et par lot ; une modification non envoyée est fusionnée
  dans la précédente. `GET /api/sync/pull/` incrémental, par table, avec
  curseur ; suppressions appliquées ; une ligne avec des changements en attente
  ou un conflit ouvert n'est jamais écrasée. Mise à jour de la configuration
  pendant le pull.
- Statuts : **Enregistré** (gris) → **À synchroniser** (orange) →
  **Synchronisé** (vert) → **Conflit** (rouge), toujours avec icône et texte.
- Automatique au retour du réseau (option « Wi-Fi uniquement »), et bouton
  « Synchroniser maintenant ».

## Tables OMS

La formule est prête et testée ; les données ne sont pas dans le dépôt.
Ajouter dans `assets/who/` les fichiers officiels du paquet OMS « anthro »
(https://github.com/WorldHealthOrganization/anthro, `data-raw/growthstandards`),
les mêmes que `python manage.py importer_tables_oms` côté serveur :

- `weianthro.txt` (poids pour l'âge)
- `lenanthro.txt` (taille pour l'âge)
- `wflanthro.txt` (poids pour la longueur)
- `wfhanthro.txt` (poids pour la taille)

Ils sont chargés au démarrage : z-scores au dépistage, « Vérifiez la mesure »
au-delà de ±5 z, statut pour le parent et courbes −3/−2/0/+2/+3 apparaissent
alors. Le paquet est sous licence GPL-3 : la décision de les embarquer dans
l'APK revient au projet (`docs/DECISIONS.md` D6).

## Décisions prises côté mobile

| Sujet | Décision |
|---|---|
| Profils | Une base chiffrée par profil ; nom du profil visible avant déverrouillage, aucune donnée de santé. |
| Mode agent / personnel | Profils séparés : la tuile « Malnutrition » du mode personnel propose de créer un profil agent, pour ne jamais mélanger les données d'une mère et les dossiers d'un agent. |
| Code de référencement | `TRK-XXXX-XXXX-C` : 6 caractères aléatoires par installation + compteur + clé de contrôle (base 32 sans I, L, O, U). Si le serveur refuse un code déjà pris, nouveau préfixe et nouveau code ; l'ancien reste affiché. |
| Classification | Mêmes règles et même ordre que le serveur ; le serveur reclasse à la réception et sa valeur remplace celle du téléphone. `priorite` : rouge = urgente, orange = haute, jaune = normale (D5). `alerte` : MAS = rouge, MAM / nourrisson à risque = orange, sinon vert. |
| « Vérifiez la mesure » | z-score hors de ±5 (configuration) ou valeur hors de bornes de saisie (poids 0,5–50 kg, taille 35–140 cm, PB 50–300 mm) : ce sont des garde-fous de saisie, pas des seuils cliniques. |
| Statut de croissance du parent | Le z-score le plus bas décide (`croissance.affichage_parent`). |
| Grossesse | Trimestres 0 / 14 / 28 SA (définition usuelle, surchargeable par `grossesse.trimestres_debut_sa`). |
| Cycle | « Cycles enregistrés » = débuts de règles notés ; « fiable » à partir de 3 et si chaque cycle récent est entre 21 et 35 jours (limites de la configuration) ; « de façon répétée » = au moins 2 fois ; retard = date prévue dépassée ; saignements très abondants = flux « Abondant » sur les dernières règles. |
| Malagasy | Textes cliniques de la configuration en français tant que `"mg"` est vide. |
| Thème | Clair seulement (le skill n'autorise le sombre que testé). |
