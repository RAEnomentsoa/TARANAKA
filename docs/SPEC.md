    # TARANAKA by SmartSaha — Spécification MVP (prompt v2)

> **À l'attention de l'équipe de développement (humaine ou IA).**
> Tu es une équipe produit senior (PM, designer UX, développeurs mobile et backend, QA) habituée aux applications grand public à très forte audience. Construis le MVP décrit ci-dessous. En cas d'ambiguïté, applique les principes de la section 1 et signale la décision prise. **Aucune règle clinique ne doit être codée en dur** : elles vivent dans un fichier de configuration versionné, validé par les autorités sanitaires (section 11).

---

## 0. En une phrase

Application mobile Android **hors ligne d'abord**, bilingue **malagasy / français**, qui accompagne la santé de la femme (cycle, grossesse, post-partum) et de l'enfant (croissance, alimentation, vaccins), et qui permet aux agents communautaires de **dépister la malnutrition aiguë et de référer** les enfants vers le bon centre, avec un tableau de bord web pour les CSB et les superviseurs.

## 1. Principes produit (non négociables)

1. **Hors ligne d'abord.** Tout fonctionne sans réseau. Le réseau ne sert qu'à synchroniser.
2. **3 taps maximum** pour l'action la plus fréquente de chaque module (ex. « mes règles ont commencé aujourd'hui »).
3. **Lisible sans savoir bien lire.** Pictogrammes, chiffres, couleurs, et **audio en malagasy** sur chaque écran clé (bouton haut-parleur).
4. **Conçu pour les téléphones d'entrée de gamme.** Android 8+, 1 Go de RAM, écran 5", APK < 30 Mo, démarrage à froid < 3 s.
5. **Confidentialité par défaut.** Les données intimes restent sur le téléphone sauf choix explicite de l'utilisatrice.
6. **Orienter, jamais diagnostiquer.** L'application signale, alerte et oriente. Diagnostics, traitements et sorties restent sous la responsabilité de professionnels habilités. Ce message est visible dans chaque alerte.
7. **Téléphone partagé = cas normal.** Plusieurs profils par appareil, chacun protégé par son propre code PIN.

## 2. Utilisateurs et modes

L'application a **deux modes** séparés dès l'accueil. C'est la correction la plus importante par rapport à la v1 : une mère et un agent de santé n'ont ni les mêmes droits ni les mêmes écrans.

| Persona | Mode | Accès | Besoin principal |
|---|---|---|---|
| Adolescente / femme (rurale, faible littératie possible) | **Personnel** | Compte bénéficiaire créé depuis le téléphone (D16) + PIN local | Suivre son cycle ou sa grossesse discrètement |
| Parent / tuteur d'un enfant de 0 à 24 mois | **Personnel** | Compte bénéficiaire créé depuis le téléphone (D16) + PIN local | Suivre croissance, repas, vaccins |
| Agent communautaire (AC) | **Agent** | Compte nominatif créé par un superviseur + PIN | Dépister, référer, relancer les rendez-vous manqués |
| Infirmier / médecin CSB, CRENAS, CRENI | **Web** | Compte nominatif, double authentification | Recevoir les référencements et mettre à jour les dossiers |
| Superviseur (district, région, programme) | **Web** | Compte nominatif | Voir des statistiques agrégées et anonymisées |

> **Modifié par D16 (`docs/DECISIONS.md`, `docs/PLAN_BENEFICIAIRE_CONNECTEE.md`).** La bénéficiaire a désormais un compte serveur, créé depuis son téléphone sans validation admin (identifiant et code générés). Le téléphone reste hors ligne d'abord : le profil marche tout de suite, le compte est créé à la première connexion. L'ASC choisit une bénéficiaire qui utilise déjà l'application (liste de sa zone ou code qu'elle montre) au lieu de créer un enfant isolé ; il peut inscrire une femme sans téléphone, avec son consentement.

Rôles et permissions gérés côté serveur (RBAC). Chaque action clinique est tracée dans un journal d'audit (qui, quoi, quand, sur quel appareil).

## 3. Accueil et prise en main

**Premier lancement (< 60 secondes) :**
1. Choix de la langue (malagasy / français), modifiable à tout moment.
2. Écran de consentement en langage simple, avec audio : quelles données, où elles restent, comment les effacer.
3. Création d'un profil (prénom ou surnom) et d'un code PIN à 4 chiffres. Question de récupération facultative.
4. Choix du mode : « Pour moi et ma famille » ou « Je suis agent de santé ».

**Écran d'accueil du mode personnel :** trois grandes tuiles illustrées : **Mon cycle**, **Ma grossesse**, **Mon enfant**. Une quatrième tuile **Malnutrition & prise en charge** ouvre la connexion agent (elle n'est pas accessible sans identifiants professionnels).

**Écran d'accueil du mode agent :** **Dépister un enfant**, **Mes référencements**, **Rendez-vous à relancer**, **Synchronisation**.

**Mode discret (option) :** icône et nom d'application neutres, notifications sans mot sensible (« Rappel » au lieu de « Tes règles arrivent »). Important pour les adolescentes.

## 4. Module Mon cycle

**Saisie :** début et fin des règles (un tap sur « aujourd'hui »), intensité (3 niveaux en pictogrammes), douleur (0 à 3), humeur (5 émojis), symptômes facultatifs.

**Calculs :**
- Durée du cycle, durée des règles, moyenne et régularité sur les 6 derniers cycles.
- Prédiction des prochaines règles, de l'ovulation (≈ 14 jours avant les règles suivantes) et de la fenêtre fertile (≈ 5 jours avant l'ovulation + jour de l'ovulation).
- Les prédictions affichent un niveau de confiance : **« estimation »** avant 3 cycles enregistrés, **« fiable »** ensuite si le cycle est régulier.

**Signaux d'attention (conseil de consulter, pas de diagnostic) :** cycle de moins de 21 jours ou de plus de 35 jours de façon répétée, règles de plus de 7 jours, saignements très abondants, absence de règles depuis plus de 90 jours, retard de règles (avec suggestion d'un test de grossesse et lien vers **Ma grossesse**).

**Contenus :** hygiène menstruelle (y compris protections réutilisables), puberté, santé reproductive, adaptés à l'âge.

**Avertissement permanent :** « Les prévisions sont indicatives. Elles ne sont pas une méthode de contraception fiable. »

**Données :** stockées uniquement sur le téléphone par défaut. Jamais synchronisées sans activation explicite.

## 5. Module Ma grossesse et post-partum

**Saisie initiale :** date des dernières règles (DDR) **ou** terme confirmé par un professionnel (échographie / consultation). Le terme confirmé est prioritaire sur la DDR.

**Calculs :**
- Âge gestationnel en semaines d'aménorrhée (SA) + jours.
- Date probable d'accouchement = DDR + 280 jours (règle de Naegele), corrigée si un terme confirmé est saisi.
- Trimestre et repère de la semaine (développement du bébé, conseils).

**Calendrier :**
- Consultations prénatales (CPN) et postnatales générées selon le **calendrier national paramétrable** (référence OMS 2016 : 8 contacts prénatals ; OMS 2022 : au moins 4 contacts postnatals dans les 6 semaines). Le nombre et les dates exactes viennent de la configuration validée.
- Rappels locaux (fonctionnent sans réseau).
- Case « J'y suis allée » pour chaque consultation.

**Suivi :** poids, symptômes, mouvements du bébé (journal disponible à partir de 28 SA, avec explication sur leur apparition vers 16 à 22 SA), date d'accouchement réelle, mode d'allaitement.

**Contenus :** nutrition (y compris diversité alimentaire de la femme, 10 groupes MDD-W, facultatif), prévention (paludisme, anémie, fer et acide folique selon prescription), préparation à l'accouchement, plan pour se rendre au centre de santé, allaitement, récupération après l'accouchement, planification familiale.

**ALERTE ROUGE (immédiate, hors ligne, plein écran) :** déclenchée par un seul tap sur l'un de ces signes :
- Pendant la grossesse : saignement vaginal, convulsions, maux de tête violents ou vision trouble, fièvre élevée, difficulté à respirer, douleur abdominale intense, perte des eaux, le bébé bouge moins ou plus du tout, gonflement soudain du visage ou des mains.
- Après l'accouchement : saignement abondant, fièvre, convulsions, difficulté à respirer, douleur intense, pertes malodorantes, tristesse profonde ou pensées inquiétantes.

L'écran d'alerte affiche : « Allez immédiatement au centre de santé le plus proche », le CSB de référence enregistré, un bouton d'appel (numéro d'urgence ou de l'AC configuré), et la mention « Cette alerte ne remplace pas un diagnostic ». La liste des signes est paramétrable et validée.

## 6. Module Mon enfant (0 à 24 mois)

**Fiche enfant :** prénom, sexe, **date de naissance** (l'âge est toujours calculé, jamais saisi), poids de naissance. Plusieurs enfants par profil.

**Croissance :**
- Saisie poids (kg, 1 décimale), longueur couchée avant 24 mois, taille debout ensuite.
- Courbes et z-scores selon les **standards de croissance OMS 2006** (poids/âge, taille/âge, poids/taille), tables embarquées pour fonctionner hors ligne.
- Contrôle de plausibilité : valeur hors limites ou z-score inférieur à -5 ou supérieur à +5 → message « Vérifiez la mesure » avant enregistrement.
- Affichage simple pour le parent : « Sur la bonne voie » / « À surveiller » / « Consultez un agent de santé », avec la courbe.

**Alimentation (selon l'âge) :**
- **0 à 5 mois :** suivi de l'allaitement exclusif (oui/non par jour, nombre de tétées facultatif). Pas de journal alimentaire.
- **6 à 23 mois :** journal des repas par pictogrammes (aliments malgaches courants : vary, voatavo, ravitoto, anana, trondro, atody, voanjo, etc.), classés automatiquement dans les **8 groupes OMS/UNICEF** :
  1. Lait maternel
  2. Céréales, racines, tubercules
  3. Légumineuses, noix, graines
  4. Produits laitiers
  5. Viandes, poissons, volailles, abats
  6. Œufs
  7. Fruits et légumes riches en vitamine A
  8. Autres fruits et légumes
- Indicateurs calculés : **diversité alimentaire minimale** (au moins 5 groupes sur 8), **fréquence minimale des repas** selon l'âge et l'allaitement, **alimentation minimale acceptable**.
- Si un indicateur n'est pas atteint : suggestion concrète avec des aliments locaux et de saison (ex. « Ajoutez un œuf ou du poisson séché écrasé au vary sosoa »), issue d'une bibliothèque de conseils validée.

> Correction v1 : le texte initial mélangeait « 10 groupes » et « 8 groupes ». Pour l'enfant de 6 à 23 mois, la référence est 8 groupes. Les 10 groupes (MDD-W) concernent la femme et sont proposés dans le module grossesse.

**Vaccins et consultations :** calendrier du **Programme élargi de vaccination (PEV) national**, chargé depuis la configuration (jamais codé en dur), avec rappels, statut « fait / en retard » et photo facultative du carnet de santé.

**Signes de danger de l'enfant (alerte rouge, critères PCIME) :** ne peut pas boire ou téter, vomit tout, convulsions, très endormi ou inconscient, gonflement des deux pieds. Même écran d'orientation que pour la grossesse.

## 7. Module Malnutrition et prise en charge (mode agent uniquement)

**Tranche d'âge : 0 à 59 mois** (la prise en charge nationale de la malnutrition aiguë couvre les moins de 5 ans, pas seulement les 0 à 24 mois).

**Saisie :** identité de l'enfant (ou recherche d'un enfant existant), poids, taille ou longueur, **périmètre brachial (PB) à partir de 6 mois**, œdèmes bilatéraux (aucun / + / ++ / +++), signes de danger PCIME, appétit (si testé), complications médicales.

**Classification (seuils OMS 2023, à confirmer avec le protocole PCIMA national) :**

| Résultat | Critères (6 à 59 mois) |
|---|---|
| **MAS** (malnutrition aiguë sévère) | Œdèmes bilatéraux **et/ou** P/T < -3 z-score **et/ou** PB < 115 mm |
| **MAM** (malnutrition aiguë modérée) | P/T entre -3 et < -2 z-score **et/ou** PB de 115 à < 125 mm, **sans** œdème |
| Normal | Aucun des critères ci-dessus |

- **Moins de 6 mois :** pas de PB comme critère principal. Signaler « nourrisson à risque » selon les critères OMS 2023 (poids/âge, croissance qui stagne, difficultés d'allaitement, signes de danger) et orienter systématiquement vers un professionnel.

**Orientation automatique (règles paramétrables) :**
- MAS **avec** complication, signe de danger ou perte d'appétit → **CRENI** — urgence rouge.
- MAS **sans** complication → **CRENAS** — urgence orange.
- MAM → **CRENAM** / prise en charge communautaire selon le protocole — urgence jaune.
- Normal → conseils et prochain dépistage programmé.

> Correction v1 : le CRENAM manquait. Sans lui, les enfants en MAM n'ont pas de destination de référencement.

**Fiche de référencement :**
- **Code unique généré hors ligne** (court, lisible et dictable au téléphone, ex. `TRK-7F3K-92`), sans risque de doublon entre appareils (identifiant de l'appareil + compteur, ou ULID).
- Contenu : identité, mesures, classification, signes, urgence, centre de destination, AC référent, date et heure.
- Affichage plein écran à montrer à l'infirmier, et version imprimable ou partageable en PDF.
- Statut affiché tant qu'elle n'est pas confirmée : **« Non transmise — à montrer au centre »**.

**Cycle de vie du dossier :**
`Référé → Reçu → Pris en charge → En suivi → Sortie`
Issues de sortie (à valider avec le protocole) : guéri, transféré, non-répondant, abandon / perdu de vue, décédé. Seul un professionnel habilité peut enregistrer une sortie.

**Suivi :** mesures successives avec courbe d'évolution, prochains rendez-vous, liste des **rendez-vous manqués** et des **référencements non arrivés après 48 h** (paramétrable) pour relance par l'AC.

## 8. Hors ligne, stockage et sécurité

- Base locale **SQLite chiffrée (SQLCipher)**. Clé protégée par le Keystore Android et dérivée du PIN.
- Tous les modules, calculs, courbes OMS, calendriers, contenus audio et alertes fonctionnent sans réseau après le premier chargement.
- **Verrouillage** automatique après 2 minutes d'inactivité. 5 PIN erronés → délai progressif.
- **PIN oublié :** mode personnel → question de récupération (sinon, réinitialisation avec perte des données locales non synchronisées, clairement expliquée). Mode agent → réinitialisation par le superviseur ; les données synchronisées sont restaurées.
- Bouton **« Effacer toutes mes données »** dans les paramètres.
- Captures d'écran bloquées sur les écrans sensibles.
- Conformité à la **loi malgache n° 2014-038** sur la protection des données personnelles (autorité : CMIL) : consentement explicite, minimisation, droit d'accès et d'effacement, hébergement et transferts documentés.

## 9. Synchronisation

- Modèle **outbox** : chaque création ou modification est écrite localement puis placée dans une file d'envoi.
- **Identifiant unique (UUID) généré sur le téléphone** + clé d'idempotence → aucun doublon même si l'envoi est répété.
- Envoi automatique dès le retour du réseau (et sur bouton « Synchroniser maintenant »), en HTTPS/TLS 1.2+, par petits lots compressés, avec reprise après coupure. Option « Wi-Fi uniquement ».
- **Ce qui est synchronisé :** données du mode agent (dépistages, référencements, suivis). ~~Données du mode personnel uniquement si l'utilisatrice l'active~~ **Depuis D16 : toutes les données du mode personnel** (grossesse, CPN, suivi, mouvements, signes de danger, alimentation, enfants, pesées, repas, vaccins, tétées), avec le consentement donné à la création du compte. **Le cycle menstruel reste privé** : il n'est envoyé que si elle active le partage du cycle, et le désactiver l'efface du serveur (option a). Le personnel de santé (ASC, agent de CSB) voit le dossier complet des femmes qu'il suit.
- Statut visible sur chaque enregistrement : **Enregistré** (gris) → **À synchroniser** (orange) → **Synchronisé** (vert) → **Conflit** (rouge).
- **Conflits sur des données cliniques :** jamais d'écrasement automatique. Les deux versions sont conservées et envoyées dans une file « à vérifier » sur le tableau de bord web.
- Un référencement reste marqué **« Non transmis »** jusqu'à l'accusé de réception du serveur, puis **« Reçu par le centre »** quand l'infirmier confirme.
- Les mises à jour de configuration (seuils, calendriers, contenus) sont téléchargées pendant la synchronisation et versionnées.

## 10. Tableau de bord web (CSB, CRENAS, CRENI, supervision)

**Infirmier / médecin :**
- File des référencements entrants, triée par urgence (rouge, orange, jaune) puis par ancienneté.
- Fiche enfant : informations autorisées, historique des mesures et courbes.
- Actions : **Patient arrivé**, enregistrer la prise en charge, programmer un contrôle, mettre à jour le statut, enregistrer la sortie.
- Recherche par code de référencement.
- File des conflits de synchronisation à arbitrer.

**Agent communautaire (aussi dans l'app) :** référencements non aboutis, rendez-vous manqués, enfants à revoir.

**Superviseur :** statistiques **agrégées et sans identité** par période et zone : nombre de dépistages, cas MAM et MAS, taux de référencements arrivés, délai moyen entre référencement et arrivée, issues de sortie, rendez-vous manqués. Export CSV. Pas d'affichage de données individuelles pour les petits effectifs (moins de 5 cas).

**Interopérabilité (post-MVP, prévoir dans l'architecture) :** export vers **DHIS2** (système d'information sanitaire national) et API compatible FHIR.

## 11. Contenus et règles cliniques : gouvernance

Tout ce qui suit est stocké dans une **configuration versionnée**, modifiable sans republier l'application, et **validé par écrit** par le Ministère de la Santé publique / l'ONN / un comité médical avant mise en production :
- Seuils de malnutrition et règles d'orientation (PCIMA national).
- Calendrier vaccinal PEV.
- Calendrier CPN / postnatal.
- Listes des signes de danger.
- Bibliothèque de conseils nutritionnels et d'aliments locaux.
- Textes et audios en malagasy (relus par des locuteurs des principales régions).

Chaque écran de conseil affiche la source et la version du contenu.

## 12. Exigences non fonctionnelles

| Critère | Cible |
|---|---|
| Appareils | Android 8.0+, 1 Go de RAM |
| Taille de l'APK | < 30 Mo (audio téléchargé à part, par langue) |
| Démarrage à froid | < 3 s sur appareil d'entrée de gamme |
| Sessions sans plantage | ≥ 99,5 % |
| Batterie | Aucune tâche de fond hors synchronisation planifiée |
| Données mobiles | Synchronisation incrémentale ; < 100 Ko pour une journée d'activité d'un AC |
| Accessibilité | Zones tactiles ≥ 48 dp, contraste AA, texte agrandissable, lecteur d'écran |
| Langues | Malagasy et français à 100 %, aucun texte en dur |
| Tests | Unitaires sur tous les calculs (z-scores, dates, classifications) avec cas de référence OMS ; tests sur 3 vrais appareils d'entrée de gamme ; tests terrain avec 5 utilisatrices et 3 AC |
| Mesure d'usage | Statistiques anonymes, sans contenu de santé, désactivables |

**Stack recommandée (à justifier si changement) :** Flutter ou Kotlin natif ; SQLite + SQLCipher ; backend API REST + PostgreSQL ; hébergement avec sauvegardes chiffrées ; tableau de bord web responsive.

## 13. Scénarios de démonstration (critères d'acceptation)

1. **Accueil :** au premier lancement, en malagasy, une utilisatrice crée son profil et arrive sur l'accueil en moins de 60 secondes, sans réseau.
2. **Cycle :** après la saisie de 3 cycles, le calendrier affiche les prochaines règles et la fenêtre fertile avec la mention « fiable » ; l'avertissement contraception est visible.
3. **Grossesse :** avec une DDR à J-84, l'application affiche 12 SA + 0 j, la date probable d'accouchement et les prochaines CPN. Un tap sur « saignement » ouvre l'alerte rouge en moins d'une seconde, en mode avion.
4. **Enfant :** pour un enfant de 9 mois ayant mangé vary + anana + lait maternel, la diversité est 3/8 (« insuffisante ») et l'application propose d'ajouter un aliment d'origine animale local.
5. **Dépistage :** un AC saisit un enfant de 18 mois avec PB = 112 mm, sans œdème ni complication → **MAS, CRENAS, urgence orange** ; une fiche avec code unique est générée hors ligne et marquée « Non transmise ».
6. **Hors ligne :** l'ensemble des scénarios 1 à 5 fonctionne en mode avion ; les données survivent au redémarrage du téléphone.
7. **Synchronisation :** au retour du réseau, le référencement passe à « Synchronisé » ; un second envoi forcé ne crée aucun doublon sur le serveur ; une modification concurrente du même dossier crée un conflit visible sur le web.
8. **Tableau de bord :** l'infirmier du CRENAS voit le référencement en tête de liste, clique « Patient arrivé » ; l'AC voit le statut « Reçu par le centre » à sa prochaine synchronisation ; le superviseur voit le compteur MAS augmenter de 1 sans aucune donnée nominative.

## 14. Hors périmètre du MVP

Téléconsultation, messagerie, paiement, iOS, contraception active, diagnostic automatisé, prescription de traitements, intégration DHIS2 complète (préparée seulement), SMS/USSD (à étudier pour la v2).

## 15. Livrables attendus

1. APK Android signé + guide d'installation.
2. Tableau de bord web déployé + comptes de démonstration (AC, infirmier, superviseur).
3. Fichier de configuration clinique d'exemple, clairement marqué « À VALIDER ».
4. Code source documenté, schéma de base de données, documentation de l'API.
5. Rapport de tests (calculs, hors ligne, synchronisation, appareils réels).
6. Jeu de données de démonstration fictif couvrant les 8 scénarios.
