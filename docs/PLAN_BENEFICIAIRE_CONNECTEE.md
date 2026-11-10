# Bénéficiaire connectée : liste des tâches

> Choix validé avec l'équipe mobile. Il remplace « sans compte » (SPEC v2 §2).
> **Backend fait** (décision D16 dans `docs/DECISIONS.md`). Mobile et web : à faire.
> Cycle : **option (a) retenue** — le cycle reste privé, avec une option pour le partager.

## Décisions prises

1. **Toutes les données de la bénéficiaire sont synchronisées** avec le serveur : cycle, grossesse, enfants, repas, vaccins…
2. **Elle a un compte `beneficiaire` sur le serveur**, créé depuis son téléphone.
3. **L'ASC n'invente plus de bébé « isolé ».** Il choisit une bénéficiaire qui utilise déjà l'application, puis l'un de ses enfants, ou il ajoute un enfant rattaché à cette mère.
4. **Le personnel de santé (ASC, agent CSB) voit toutes les données de la bénéficiaire** quand il ouvre son dossier et synchronise, dans sa zone (région pour l'ASC, centre pour le CSB).
5. **Le superviseur reste en statistiques anonymes**, sans changement.

## Points à valider avant de coder

Ce sont des points juridiques et de confiance, à faire confirmer par le responsable.

- [ ] **Consentement explicite** (loi 2014-038) : l'écran de consentement doit dire clairement que *tout* est envoyé au serveur et que le personnel de santé de sa zone peut le voir. C'est une case à cocher, pas seulement un bouton « Continuer ».
- [x] **Cycle menstruel** — option (a) choisie : SPEC v2 §9 et le cahier (§2, §4.2.B) disent « jamais par défaut », surtout pour les **adolescentes**. Choisir entre deux options :
  - **(a)** le cycle reste privé, avec une option pour le partager ;
  - **(b)** le cycle est envoyé mais **invisible pour l'ASC**, et visible seulement par le CSB.

  Recommandation : **(a)** ou **(b)**, pas « tout visible par tous ».
- [x] **Hors ligne d'abord** : un profil créé sans réseau fonctionne tout de suite. Le compte serveur est créé à la première connexion. (Côté serveur : l'inscription est un simple appel public, faisable à tout moment.)
- [x] **Mettre à jour `docs/SPEC.md` et `docs/DECISIONS.md`** : ce choix remplace « sans compte » (SPEC v2 §2). (D16, et SPEC §2 et §9 annotés.)

## 1. Backend (Django)

### Comptes

- [x] Créer un endpoint public **`POST /api/auth/register-beneficiary/`**. Il reçoit le prénom ou surnom, la région (obligatoire), le téléphone (facultatif), un PIN et l'identifiant de l'appareil. Il crée le compte `beneficiaire` **sans validation admin**, contrairement aux demandes d'accès du personnel. Il faut une limite d'appels (throttle) et un journal d'audit.
- [x] Générer un **identifiant lisible** (ex. `voahangy.4821`) que la bénéficiaire peut montrer à l'ASC. Utiliser aussi un **code court ou un QR** pour la retrouver facilement.
- [x] Prévoir la connexion depuis un 2e téléphone et le PIN oublié : réinitialisation par l'ASC ou le CSB, comme pour un ASC avec son superviseur.

### Données

- [x] **Corriger M1** : une bénéficiaire peut créer et modifier ses enfants, mesures et journaux alimentaires (voir `docs/API_ISSUES.md`, M1).
- [x] **Créer les tables qui n'existent que sur le téléphone** (modèle `SyncModel`, avec serializer, sync push/pull et migrations) :
  - `vaccin_fait`
  - `suivi_grossesse` (CPN)
  - `contact_soin`
  - `mouvement_bebe` et `mouvement_evenement`
  - `alimentation_femme`
  - `tetee`
- [x] Vérifier que les champs de `cycle`, `grossesse`, `danger_grossesse`, `enfant`, `mesure` et `journal_alimentaire` correspondent exactement aux colonnes du téléphone, comme on l'a fait pour la config PEV.
- [x] **Push et pull pour la bénéficiaire** : elle reçoit uniquement *ses* données, et ce que le CSB met à jour (rendez-vous, statut des référencements).

### Accès du personnel

- [x] **`GET /api/beneficiaries/`** (ASC, agent CSB) : liste des bénéficiaires de sa zone. Recherche par nom, téléphone ou code, avec un minimum d'informations dans la liste.
- [x] **`GET /api/beneficiaries/{id}/`** : dossier complet (grossesse, enfants, mesures, vaccins…), en appliquant la règle choisie pour le cycle.
- [x] **Pull de l'ASC** : il reçoit les données des bénéficiaires **qu'il suit** (celles qu'il a ouvertes ou rattachées), pas toute la région. Cela limite le volume et l'exposition.
- [x] Mettre à jour les **permissions** (matrice `comptes/tests_permissions.py`), le **journal d'audit** (« X a consulté le dossier de Y ») et **`my-data`** (export et effacement de toutes les nouvelles tables).
- [x] **Référencement grossesse** : l'ASC peut référer une **femme enceinte** (`origine: grossesse`). Le backend le permet déjà.
- [x] Régénérer `docs/openapi.yaml` et mettre à jour `Backend_serveur/docs/endpoint.md`.

### Fait en plus

- [x] `POST /api/beneficiaries/lookup/` (ouvrir le dossier avec le code, toute région) et `POST /api/beneficiaries/{id}/unfollow/`.
- [x] `PATCH /api/auth/me/` `{"partage_cycle": true|false}` ; l'arrêt efface son cycle du serveur.
- [x] Un ASC inscrit une femme sans téléphone avec `POST /api/profiles/` (identifiant et code générés) et la suit.
- [x] Les pesées faites par la mère (sans ASC) ne comptent pas comme dépistages dans les statistiques.
- [x] Codes de démo : `mere.voahangy` `VHG444`, `mere.lalao` `RZM445`, `mere.fara` `FAR446`.

### Ce que le mobile doit savoir (écarts trouvés en alignant les tables)

- **Ajouter une colonne `id` (UUID)** aux tables locales qui n'en ont pas : `vaccin_fait`, `contact_soin`, `mouvement_bebe`, `alimentation_femme`, `cycle_jour`. Le serveur garde la règle « une ligne par jour / par dose » ; l'`id` sert à la synchro.
- **Ajouter `version`, `sync_status` et `updated_at`** aux tables qui n'en ont pas (`suivi_grossesse`, `mouvement_evenement`, `tetee`, `vaccin_fait`…), comme pour `enfant`.
- **Journal alimentaire** : envoyer aussi les groupes `g1_lait_maternel` … `g8_autres_fruits_legumes` (le téléphone connaît le groupe de chaque aliment), en plus de `aliments`, `repas`, `laits`, `tetees`, `autres_recus`.
- **Signe de danger** : envoyer `code` (code de la config) et `periode` ; le serveur retrouve le type.
- **Cycle et suivi du jour** : ne pas les envoyer tant que `partage_cycle` est faux (le serveur répond `refuse`). Proposer l'option dans Paramètres.
- **Inscription** : la réponse donne `identifiant` et `code_beneficiaire` à garder et afficher (« Mon code »).
- **ASC** : avant d'enregistrer pour une femme, ouvrir son dossier (`/api/beneficiaries/{id}/` ou `lookup/`) pour la suivre ; sinon ses données ne descendent pas au pull.

## 2. Mobile (Flutter)

### Mode personnel

- [ ] Nouveau **consentement** (case à cocher, texte et audio malagasy/français). Mettre à jour la politique de confidentialité, car « rien n'est envoyé » devient faux.
- [ ] À la création du profil, choisir la **région**, puis créer le compte serveur dès qu'il y a du réseau. En attendant, le profil fonctionne hors ligne.
- [ ] **Profils déjà existants** : au premier lancement de la nouvelle version, demander le consentement, puis envoyer tout l'historique local.
- [ ] Ajouter l'**outbox** à tous les modules personnels (cycle selon la décision prise, grossesse, CPN, mouvements, danger, repas, tétées, enfants, mesures, vaccins).
- [ ] Ajouter le **statut de synchro** visible (gris, orange, vert, rouge) et l'écran « Synchronisation » au mode personnel.
- [ ] Ajouter un écran **« Mon code »** (identifiant et QR) à montrer à l'agent.
- [ ] **« Effacer toutes mes données »** : demander « sur ce téléphone seulement » ou « aussi sur le serveur » (`/api/auth/my-data/erase/`).

### Mode agent (ASC)

- [ ] **« Dépister un enfant »** commence par **choisir la bénéficiaire**, avec trois moyens :
  - scanner son QR ou taper son code ;
  - chercher dans la liste des bénéficiaires de sa zone ;
  - si elle n'a pas de téléphone, l'**inscrire avec son consentement** (cahier §3.2.A). Elle reçoit un code de connexion.
- [ ] Ensuite, choisir **un de ses enfants**, ou **ajouter un enfant rattaché à elle** (`mere_id` obligatoire). Il n'y a plus d'enfant sans mère.
- [ ] **Dossier de la bénéficiaire** dans l'app : grossesse, enfants, courbes, vaccins, avec ses données reçues lors de la synchro.
- [ ] L'ASC peut **référer une femme enceinte** (signes de danger) et pas seulement un enfant.
- [ ] Ajouter `mere_id` et `grossesse_id` dans ce qui est envoyé.

## 3. Web (Vue)

- [ ] **Fiche bénéficiaire** : identité, grossesse en cours (âge gestationnel, DPA, CPN, signes de danger), enfants avec liens vers leur fiche.
- [ ] **Fiche enfant** : afficher la mère, les vaccins et les repas.
- [ ] **Référencements grossesse** dans la file, avec lien vers la fiche bénéficiaire.
- [ ] **Recherche** par code bénéficiaire, nom ou téléphone (agent CSB).
- [ ] **Statistiques superviseur** (anonymes, règle « < 5 ») : nombre de bénéficiaires actives, grossesses suivies, signes de danger signalés, référencements grossesse et taux d'arrivée, couverture vaccinale.
- [ ] Traductions FR/MG/EN.

## 4. Tests et livraison

- [ ] Tests backend : inscription, M1, nouvelles tables, permissions (une bénéficiaire ne voit que ses données, et l'ASC ou le CSB seulement sa zone), effacement.
- [ ] Tests mobile : synchro du mode personnel hors ligne puis en ligne, migration des anciens profils, choix de la bénéficiaire par l'ASC.
- [ ] **Scénario de bout en bout** :
  1. Une mère crée son profil, renseigne sa grossesse et son enfant, puis synchronise.
  2. L'ASC scanne son code, dépiste l'enfant et le réfère.
  3. Le CSB voit la mère et l'enfant sur le web et clique « Patient arrivé ».
  4. La mère et l'ASC voient le statut mis à jour.
- [ ] Mettre à jour les données de démo (`charger_demo`) et `docs/DEMO.md`.

## Ordre conseillé

1. **Valider** les points juridiques, surtout le cycle et les adolescentes.
2. **Backend** : inscription, M1, nouvelles tables, accès du personnel. Le mobile en dépend.
3. **Mobile** : synchro du mode personnel, puis choix de la bénéficiaire par l'ASC.
4. **Web** : fiches et statistiques, une fois que de vraies données arrivent.
