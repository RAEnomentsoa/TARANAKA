# TARANAKA – Central server database (PostgreSQL) – v3

Version 3, 4 Nov 2026: MVP backend finished (see "What changed for the MVP backend" below, and `docs/DECISIONS.md` at the root of the repository). Version 2 (3 Nov 2026) followed the Django plan from Claude Code, with the decisions applied.

## What changed since v1

**Names**
1. All table names are lowercase. The table `User` is now called **`utilisateur`**, because `user` is a reserved word in PostgreSQL.
2. Link columns use the Django style `<name>_id`. For example `id_mere` → `mere_id`, `id_region` → `region_id`, `id_grossesse` → `grossesse_id`, `id_mesure` → `mesure_id`, `Agent_medical_id` → `agent_medical_id`.
3. Columns were cleaned up: `DDR` → `ddr`, `DpA` → `dpa`, `Desc` → `description`, `code_Unique` → `code_unique`, `dateCreation` → `date_creation`, `Mesure_Type` → `mesure_type`, `Table_nom` → `table_nom`. In the Python code, L, M and S are called `valeur_l`, `valeur_m` and `valeur_s`, but the columns in the database stay `l`, `m` and `s`.

**Structure**
4. `consentement` moved from `profile` to `utilisateur`, because consent belongs to one person, not to a type of profile.
5. `utilisateur` gets the fields Django needs: `is_active`, `is_staff`, `is_superuser`, `last_login` (plus groups and permissions in separate Django tables). The PIN is hashed with Django's password system and stored in `pin_hash`.
6. `profile_id` and `region_id` on `utilisateur` can be empty, so an admin account can exist without them.
7. `phone` can be empty and is **not unique**, because people share phones. Login uses a new unique column, `identifiant`. *(This is my change to Claude Code's point 3.)*
8. The 8 synced tables also get `created_at`.
9. `reference_oms` gets an automatic `id`. `indicateur + sexe + cle` stays unique.

**Rules**
10. `waz`, `haz` and `whz` can be empty, because they can't always be calculated (for example under 45 cm).
11. Measurement limits are wider so the server never refuses a real child: weight 0.3–40 kg, length/height 25–130 cm, MUAC 70–250 mm. Values that are possible but unusual get `flag_aberrant` instead. *(This is my change to Claude Code's point 8.)*
12. `historique_version`: `table_nom + ligne_id + version + device_id` must be unique together, so two conflicting copies are both kept.
13. `journal_alimentaire`: only one row per child per day, counting only rows that aren't deleted.
14. `journal_audit`: `table_nom` and `ligne_id` can be empty, for example for a login.
15. `referencement`: `enfant_id` and `grossesse_id` are protected. A child or pregnancy that has a referral can't be deleted.
16. A soft delete also increases `version` and updates `updated_at`, so the deletion reaches the other phones.
17. `cycle`: `duree_cycle`, `duree_regle` and `estimation_prochain` can be empty while a cycle is still going on. `journal_audit.user_id` can be empty, so failed logins can be recorded.

## What changed for the login (3 Nov 2026)

18. `utilisateur.role` is **removed**. `utilisateur.profile_id` now decides what a user can do. It is required and protected: a profile that has users can't be deleted.
19. `profile.type` is **replaced** by `code` (unique, used by the code) and `libelle` (name shown on screen). This replaces point 4's table layout; `femme` and `mere` become one profile, `beneficiaire`.
20. A data migration creates the 4 profiles: `beneficiaire`, `asc`, `agent_csb`, `admin`. A profile whose code the API doesn't know gets no access. Adding a row is not enough: its code must also be added to the API.
21. `utilisateur` gets `tentatives_echouees` and `bloque_jusqu_a`. Blocking is progressive: 15 minutes after 5 wrong PINs in a row, 1 hour after 10, and until an admin unblocks the account after 15. Only a correct PIN resets the counter.
22. Point 6 changes: `profile_id` can no longer be empty. `region_id` still can.
23. `journal_audit.action` also records `login_succes`, `login_echec`, `login_bloque`, `login_refuse`, `changer_pin_succes`, `changer_pin_echec`, `changer_pin_bloque` and `compte_debloque`.
24. Two Django tables are added for logging out and token rotation: `token_blacklist_outstandingtoken` and `token_blacklist_blacklistedtoken`.

## What changed for the main API (4 Nov 2026)

25. `utilisateur` gets `csb_id`, a link to `csb` that can be empty and is protected: a CSB that has agents can't be deleted. It is required when the profile is `agent_csb`. The API and the admin check this, because the database can't: the profile code is in another table.
26. No other table changes. An ASC's access to beneficiaires and pregnancies comes from `region_id`, and server-generated referral codes use the first 4 characters of the ASC id: `R-<4 chars>-<MMDD>-<n>`. The example in table 13 follows this format.
27. `journal_audit.action` also records `status_change`.
28. A soft delete now also saves `device_id`.

## What changed for the MVP backend (4 Nov 2026)

29. `profile` gets a 5th code, `superviseur` (data migration `comptes/0005`). A supervisor's zone is `utilisateur.region_id` (empty = national). Supervisors never read health records.
30. `csb` gets `type_centre` (`csb`, `crenam`, `crenas`, `creni`, default `csb`). CRENAS, CRENI and CRENAM are rows of this table.
31. `enfant.statut_prise_en_charge` also accepts `transfere`, `non_repondant` and `decede` (exit outcomes).
32. `mesure` gets the screening inputs `signes_danger` (JSON list of codes), `complications_medicales`, `appetit` (`non_teste`, `bon`, `mauvais`) and `difficultes_allaitement`, and the server-computed `classification` (`mas`, `mam`, `normal`, `nourrisson_a_risque`), `orientation_centre`, `urgence` (`rouge`, `orange`, `jaune`), `date_prochain_controle` and `config_version`. `waz`, `haz` and `whz` are computed by the server when the WHO tables are loaded in `reference_oms`.
33. `referencement.status` follows the spec: `envoye` (Référé) → `recu` → `pris_en_charge` → `en_suivi` → `sortie`. Migration: `vu` → `recu`, `clos` → `sortie`. New columns `date_referencement` (sent by the phone), `date_reception`, `date_prise_en_charge`, `date_sortie` and `issue_sortie` (`gueri`, `transfere`, `non_repondant`, `abandon`, `decede`). A check makes sure a `sortie` has a `date_sortie`, and that `issue_sortie` is empty before.
34. New synced table `rendez_vous` (18). There are now **9 synced tables**.
35. New server tables `configuration_clinique` (19), `operation_sync` (20) and `conflit_sync` (21).
36. `historique_version` is now written: both versions of each sync conflict, with `conflit = true`.
37. `journal_audit` is append-only (the code refuses to change or delete a line). New actions: `reinitialiser_pin`, `conflit_sync`, `conflit_resolu`, `config_creee`, `config_modifiee`, `config_publiee`, `config_retiree`, `export_csv`. Login lines also store `device_id` in `details`.

## What changed for 2FA, data protection and the dashboard's API fixes (4 Nov 2026)

38. `utilisateur` gets `totp_secret` (TEXT, can be empty), `totp_active` (BOOLEAN), `totp_dernier_pas` (INTEGER, can be empty: last TOTP step used, against replay) and `efface_le` (TIMESTAMP, can be empty: data erased under loi 2014-038, account anonymised).
39. `referencement` gets `date_suivi` (TIMESTAMP, can be empty), set by the server when the status becomes `en_suivi`. The migration filled it for existing rows from the `status_change` lines of `journal_audit`.
40. `journal_audit.action` also records `login_totp_requis`, `totp_preparation`, `totp_active`, `totp_desactive`, `totp_desactivation_echec`, `totp_reinitialise`, `acces_donnees`, `effacement_donnees` and `effacement_echec`.

---

## Types used

- `UUID`: long unique id, created on the phone
- `INTEGER`: whole number
- `DECIMAL`: number with decimals
- `TEXT`: text
- `DATE`: a day
- `TIMESTAMP`: a day and a time
- `BOOLEAN`: yes or no
- `JSON`: a full record stored as one block
- `ENUM (…)`: only the listed values are allowed

**PK** means the table's own id. **FK** means a link to another table.

## Sync columns

These go on the 9 synced tables: cycle, grossesse, danger_grossesse, enfant, mesure, journal_alimentaire, referencement, consultation_nutritionnelle, rendez_vous. In these tables, `id` is a UUID.

| Column | Type | What it's for |
|---|---|---|
| version | INTEGER, starts at 1 | Goes up at each change. It lets the server detect conflicts. |
| created_at | TIMESTAMP | When the row was created |
| updated_at | TIMESTAMP | Last change. Used for "send me everything changed since…" |
| device_id | TEXT | Which phone made the change |
| deleted_at | TIMESTAMP, can be empty | Filled when the row is deleted (soft delete) |

---

## 1. province (lookup)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK | Province id |
| nom | TEXT | Name |

## 2. region (lookup)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK | Region id |
| nom | TEXT | Name |
| province_id | INTEGER, FK → province | Which province |

## 3. profile (lookup)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK | Profile id |
| code | TEXT, unique | Used by the code: beneficiaire, asc, agent_csb, superviseur, admin |
| libelle | TEXT | **NEW**: name shown on screen |

## 4. utilisateur (was User)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | User id |
| identifiant | TEXT, unique | **NEW**: login name (the phone number, or a code given by the ASC) |
| nom | TEXT | Last name |
| prenom | TEXT | First name |
| email | TEXT, can be empty | Email |
| phone | TEXT, can be empty, not unique | Phone number (can be shared) |
| pin_hash | TEXT | Hashed PIN |
| consentement | BOOLEAN | **MOVED** from profile |
| date_creation | TIMESTAMP | Account creation |
| updated_at | TIMESTAMP | Last change |
| profile_id | INTEGER, FK → profile (protected) | Profile: decides what the user can do |
| region_id | INTEGER, FK → region, can be empty | Region |
| csb_id | INTEGER, FK → csb, can be empty (protected) | **NEW**: the CSB of an agent_csb |
| is_active, is_staff, is_superuser | BOOLEAN | **NEW**: needed by Django |
| last_login | TIMESTAMP, can be empty | **NEW**: needed by Django |
| tentatives_echouees | INTEGER, default 0 | **NEW**: wrong PINs in a row |
| bloque_jusqu_a | TIMESTAMP, can be empty | **NEW**: end of the current block |
| totp_secret | TEXT, can be empty | **NEW**: TOTP secret (web accounts) |
| totp_active | BOOLEAN | **NEW**: two-factor login on |
| totp_dernier_pas | INTEGER, can be empty | **NEW**: last TOTP step used (no replay) |
| efface_le | TIMESTAMP, can be empty | **NEW**: personal data erased, account anonymised |

## 5. cycle (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Cycle id |
| user_id | UUID, FK → utilisateur | Whose cycle |
| date_debut | DATE | First day of the period |
| date_fin | DATE, can be empty | Last day |
| intensite | ENUM (faible, moyenne, forte) | Flow |
| symptome | TEXT | Symptoms |
| duree_cycle | INTEGER, can be empty | Cycle length in days (empty until the cycle ends) |
| duree_regle | INTEGER, can be empty | Period length in days (empty until the period ends) |
| estimation_prochain | DATE, can be empty | Predicted next period |
| + sync columns | | |

## 6. grossesse (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Pregnancy id |
| user_id | UUID, FK → utilisateur | The woman |
| ddr | DATE | Last period date |
| dpa | DATE | Expected delivery date |
| + sync columns | | |

## 7. type_danger_grossesse (lookup)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK | Danger sign id |
| description | TEXT | For example "saignement" |

## 8. danger_grossesse (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Record id |
| grossesse_id | UUID, FK → grossesse | Which pregnancy |
| type_danger_grossesse_id | INTEGER, FK → type_danger_grossesse | Which sign |
| date_signalement | TIMESTAMP | When it was reported |
| + sync columns | | |

## 9. enfant (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Child id |
| nom | TEXT | Name |
| mere_id | UUID, FK → utilisateur, can be empty | Mother |
| asc_id | UUID, FK → utilisateur | ASC who follows the child |
| grossesse_id | UUID, FK → grossesse, can be empty | Pregnancy followed in the app |
| region_id | INTEGER, FK → region | Where the child lives |
| date_naissance | DATE | Birth date |
| sexe | ENUM (M, F) | Sex |
| statut_prise_en_charge | ENUM (aucun, suivi, refere, pris_en_charge, gueri, abandon, transfere, non_repondant, decede) | Care status, follows the referral |
| + sync columns | | |

## 10. mesure (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Visit id |
| enfant_id | UUID, FK → enfant (protected) | Which child |
| asc_id | UUID, FK → utilisateur | Who measured |
| date_mesure | DATE | Visit day |
| poids_kg | DECIMAL (0.3–40) | Weight |
| taille_cm | DECIMAL (25–130) | Length or height measured |
| position | ENUM (couche, debout) | Lying or standing |
| pb_mm | INTEGER (70–250), can be empty | MUAC, only from 6 to 59 months |
| oedemes_bilateraux | ENUM (aucun, +, ++, +++) | Swelling of both feet |
| age_jour | INTEGER | Age in days |
| age_mois | INTEGER | Age in months |
| taille_corrigee_cm | DECIMAL | Length after ±0.7 cm |
| waz | DECIMAL, can be empty | Weight for age |
| haz | DECIMAL, can be empty | Height for age |
| whz | DECIMAL, can be empty | Weight for height |
| flag_aberrant | BOOLEAN | Unusual values, measure again |
| alerte | ENUM (vert, orange, rouge) | Traffic light |
| motif_alerte | TEXT | Why that colour |
| ref_oms | TEXT | "WHO2006" |
| signes_danger | JSON (list of codes) | **NEW**: IMCI danger signs seen by the ASC |
| complications_medicales | BOOLEAN | **NEW**: medical complication |
| appetit | ENUM (non_teste, bon, mauvais) | **NEW**: appetite test |
| difficultes_allaitement | BOOLEAN | **NEW**: feeding difficulty (under 6 months) |
| classification | ENUM (mas, mam, normal, nourrisson_a_risque), can be empty | **NEW**, server: result of the clinical config |
| orientation_centre | ENUM (csb, crenam, crenas, creni), can be empty | **NEW**, server: where to refer |
| urgence | ENUM (rouge, orange, jaune), can be empty | **NEW**, server |
| date_prochain_controle | DATE, can be empty | **NEW**, server: next screening or check |
| config_version | INTEGER, can be empty | **NEW**, server: config version used |
| + sync columns | | |

## 11. journal_alimentaire (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Entry id |
| enfant_id | UUID, FK → enfant | Which child |
| date_jour | DATE | Day recorded (one per child per day) |
| type_allaitement | ENUM (exclusif, mixte, aucun) | Breastfeeding |
| g1_lait_maternel … g8_autres_fruits_legumes | BOOLEAN × 8 | The 8 food groups |
| score_diversite | INTEGER (0–8) | Groups eaten |
| notes | TEXT | Comments |
| + sync columns | | |

## 12. csb (lookup)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK | Health centre id |
| name | TEXT | Name |
| type_centre | ENUM (csb, crenam, crenas, creni) | **NEW**: kind of facility, default csb |
| region_id | INTEGER, FK → region | Where |
| tel | TEXT | Phone |

## 13. referencement (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Referral id |
| code_unique | TEXT, unique | Short code, for example R-712d-1102-07 |
| origine | ENUM (enfant, grossesse) | Child or pregnancy alert |
| enfant_id | UUID, FK → enfant, can be empty (protected) | Child |
| grossesse_id | UUID, FK → grossesse, can be empty (protected) | Pregnancy |
| mesure_id | UUID, FK → mesure, can be empty | Visit that caused it |
| asc_id | UUID, FK → utilisateur | ASC who referred |
| csb_id | INTEGER, FK → csb | Destination |
| priorite | ENUM (urgente, haute, normale) | Priority: urgente = rouge, haute = orange, normale = jaune |
| motif | TEXT | Reason |
| status | ENUM (envoye, recu, pris_en_charge, en_suivi, sortie) | Lifecycle: Référé → Reçu → Pris en charge → En suivi → Sortie |
| date_referencement | TIMESTAMP | **NEW**: when the ASC referred, on the phone |
| date_reception | TIMESTAMP, can be empty | **NEW**: patient arrived |
| date_prise_en_charge | TIMESTAMP, can be empty | **NEW** |
| date_suivi | TIMESTAMP, can be empty | **NEW**: status became en_suivi |
| date_sortie | TIMESTAMP, can be empty | **NEW**: required when status = sortie |
| issue_sortie | ENUM (gueri, transfere, non_repondant, abandon, decede), can be empty | **NEW**: exit outcome, only with sortie |
| + sync columns | | |

## 14. consultation_nutritionnelle (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Consultation id |
| enfant_id | UUID, FK → enfant | Child |
| mesure_id | UUID, FK → mesure, can be empty | Triggering visit |
| referencement_id | UUID, FK → referencement, can be empty | Referral answered |
| csb_id | INTEGER, FK → csb | Where |
| agent_medical_id | UUID, FK → utilisateur | Health worker |
| date | DATE | Day |
| diagnostic | TEXT | Diagnosis |
| decision | ENUM (conseil, reference, prise_en_charge) | Decision |
| observations | TEXT | Notes |
| + sync columns | | |

## 15. reference_oms (lookup, copied to the phone)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK, automatic | **NEW** |
| indicateur | ENUM (wfa, lhfa, wfl, wfh) | Which WHO table |
| sexe | ENUM (M, F) | Sex |
| cle | DECIMAL | Age in days, or cm |
| l, m, s | DECIMAL | WHO LMS values |
| mesure_type | ENUM (L, H), can be empty | Lying or standing |

`indicateur` + `sexe` + `cle` must be unique together.

## 16. journal_audit (server only)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK, automatic | Line id |
| user_id | UUID, FK → utilisateur, can be empty | Who (empty for a failed login) |
| action | TEXT | login_…, create, update, delete, status_change, conflit_sync, conflit_resolu, config_…, reinitialiser_pin, export_csv… |
| table_nom | TEXT, can be empty | Which table |
| ligne_id | UUID, can be empty | Which row |
| details | JSON | Extra info |
| date_creation | TIMESTAMP | When |

## 17. historique_version (server only)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK, automatic | Line id |
| table_nom | TEXT | Which table |
| ligne_id | UUID | Which row |
| version | INTEGER | Which version |
| donnees | JSON | Full row in that version |
| device_id | TEXT | Which phone |
| conflit | BOOLEAN | Needs a human check |
| date_creation | TIMESTAMP | When received |

`table_nom` + `ligne_id` + `version` + `device_id` must be unique together.

## 18. rendez_vous (synced)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Appointment id |
| enfant_id | UUID, FK → enfant (protected) | Child |
| referencement_id | UUID, FK → referencement, can be empty | Referral it follows |
| csb_id | INTEGER, FK → csb, can be empty | Where (empty for a community screening) |
| date_prevue | DATE | Planned day |
| type_rendez_vous | ENUM (controle, depistage) | Kind of visit |
| statut | ENUM (prevu, honore, annule) | "Manqué" is computed: still prevu after date_prevue |
| motif | TEXT | Reason |
| + sync columns | | |

## 19. configuration_clinique (server only, read by the phones)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK, automatic | Line id |
| version | INTEGER, unique | Version number, given by the server |
| libelle | TEXT | Name |
| contenu | JSON | Thresholds, referral rules, calendars, danger signs, advice |
| statut | ENUM (brouillon, publiee, retiree) | A published version never changes |
| statut_validation | ENUM (a_valider, validee) | Written validation (spec §11) |
| valide_par | TEXT | Authority and signatory |
| reference_validation | TEXT | Reference of the validation document |
| date_validation | DATE, can be empty | |
| notes | TEXT | |
| cree_par | UUID, FK → utilisateur, can be empty | |
| created_at, updated_at | TIMESTAMP | |
| publiee_le | TIMESTAMP, can be empty | |

## 20. operation_sync (server only)

| Column | Type | What it's for |
|---|---|---|
| id | INTEGER, PK, automatic | Line id |
| cle_idempotence | UUID, unique | Key sent by the phone with each outbox operation |
| user_id | UUID, FK → utilisateur | Who sent it |
| device_id | TEXT | Which phone |
| table_nom | TEXT | Which table |
| operation | ENUM (create, update, delete) | |
| ligne_id | UUID | Which row |
| statut | ENUM (applique, deja_applique, conflit) | Final answer |
| reponse | JSON | Answer given, sent again if the key comes back |
| date_creation | TIMESTAMP | |

## 21. conflit_sync (server only)

| Column | Type | What it's for |
|---|---|---|
| id | UUID, PK | Conflict id |
| table_nom | TEXT | Which table |
| ligne_id | UUID | Which row |
| operation | ENUM (create, update, delete) | What the phone tried |
| version_base | INTEGER, can be empty | Version the phone knew |
| version_serveur | INTEGER | Version on the server |
| donnees_telephone | JSON | The phone's version |
| donnees_serveur | JSON | The server's version |
| user_id | UUID, FK → utilisateur | Who sent it |
| device_id | TEXT | Which phone |
| statut | ENUM (a_verifier, resolu) | |
| resolution | ENUM (serveur, telephone, fusion), can be empty | Decision |
| resolu_par | UUID, FK → utilisateur, can be empty | Who decided |
| resolu_le | TIMESTAMP, can be empty | |
| version_finale | INTEGER, can be empty | Row version after the decision |
| commentaire | TEXT | |
| created_at, updated_at | TIMESTAMP | |
