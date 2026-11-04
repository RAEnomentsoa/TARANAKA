# TARANAKA – Validation rules

These are the rules enforced by the Django models on the central server. The Flutter app must apply the same rules offline, so that a record saved on the phone is not refused at sync.

## How to read the tables

- **Required**: the field must have a value.
- **Optional (empty text)**: send `""`, never `null`. The server column does not accept `null`.
- **Optional (null)**: send `null` when there is no value. This applies to dates, numbers and links.
- **Decimals** such as "2 decimals" are a maximum. Limits such as 0.3–40 include both ends.
- **Enum values** must be sent exactly as written, including case (`M`, not `m`).

## Error messages

Show the messages below to the user.

The server returns the same wording only for rules marked **(same on server)**. For the other rules, the server returns Django's default French message, which may be worded differently, so the wording here is for the app.

Standard messages used in the tables:

| Short name | Message |
|---|---|
| OBLIGATOIRE | Ce champ est obligatoire. |
| LONGUEUR | Ce texte est trop long (maximum indiqué dans le tableau). |
| CHOIX | Cette valeur n'est pas autorisée. |
| NOMBRE | Ce nombre n'est pas valide. |
| DATE | Cette date n'est pas valide. |

## Rules that link several fields

These matter most, because the database refuses the whole record if they fail.

| Table | Fields | Rule | Allowed values | Error message |
|---|---|---|---|---|
| mesure | `poids_kg` | Inside the limits | 0.3–40 kg | Le poids doit être compris entre 0,3 et 40 kg. **(same on server)** |
| mesure | `taille_cm` | Inside the limits | 25–130 cm | La taille doit être comprise entre 25 et 130 cm. **(same on server)** |
| mesure | `pb_mm` | Inside the limits, if filled | 70–250 mm, or `null` | Le périmètre brachial doit être compris entre 70 et 250 mm. **(same on server)** |
| mesure | `pb_mm`, `age_mois` | `pb_mm` must be `null` unless `age_mois` is from 6 to 59. Hide the field outside that age. The server works out `age_mois` itself: see "Calculated by the server". | `age_mois` 6–59 | Le périmètre brachial ne peut être saisi qu'entre 6 et 59 mois. **(same on server)** |
| journal_alimentaire | `enfant_id`, `date_jour` | Only one row per child per day. Soft-deleted rows don't count. | – | Un journal existe déjà pour cet enfant à cette date. **(same on server)** |
| journal_alimentaire | `score_diversite` | Stays in range. It equals the number of `g1`–`g8` fields that are true. The server recalculates it on every save. | 0–8 | Le score de diversité doit être compris entre 0 et 8. **(same on server)** |
| referencement | `origine`, `enfant_id` | If `origine` = `enfant`, `enfant_id` is required | – | Un référencement enfant doit indiquer l'enfant, et un référencement grossesse doit indiquer la grossesse. **(same on server)** |
| referencement | `origine`, `grossesse_id` | If `origine` = `grossesse`, `grossesse_id` is required | – | Same message as above **(same on server)** |
| referencement | `code_unique` | Unique across all rows, including soft-deleted rows | – | Ce code de référencement existe déjà. **(same on server)** |
| referencement | `origine`, `enfant_id`, `grossesse_id` | Only the link that matches `origine` may be filled | – | Un référencement enfant ne peut pas indiquer de grossesse. / Un référencement grossesse ne peut pas indiquer d'enfant. **(same on server)** |
| referencement | `mesure_id`, `enfant_id` | The visit must belong to that child | – | Cette mesure ne correspond pas à cet enfant. **(same on server)** |
| referencement | `status` | Forward only: `envoye` → `recu` → `pris_en_charge` → `en_suivi` → `sortie`. `sortie` is also allowed from `recu` and `pris_en_charge`. | – | Le statut ne peut pas revenir en arrière. / Le statut suivant doit être « … ». **(same on server)** |
| referencement | `status`, `issue_sortie` | `sortie` needs `issue_sortie`; any other status refuses it. Only an `agent_csb` of the destination centre records a `sortie` (`403` otherwise). | `gueri`, `transfere`, `non_repondant`, `abandon`, `decede` | L'issue de sortie est obligatoire. / L'issue ne s'indique que pour une sortie. **(same on server)** |
| rendez_vous | `referencement_id`, `enfant_id` | The referral must be about that child | – | Ce référencement ne concerne pas cet enfant. **(same on server)** |
| consultation_nutritionnelle | `mesure_id` / `referencement_id`, `enfant_id` | Must be about that child | – | Cette ligne ne concerne pas cet enfant. **(same on server)** |
| mesure | `date_mesure`, `date_naissance` | The visit can't be before the birth date | – | La date de mesure ne peut pas être avant la date de naissance. **(same on server)** |
| enfant | `date_naissance` | A new birth date is refused if it makes a saved visit invalid | – | Cette date de naissance rend une mesure déjà enregistrée invalide. **(same on server)** |
| enfant | `grossesse_id`, `mere_id` | The pregnancy must be the mother's | – | Cette grossesse n'est pas celle de la mère indiquée. **(same on server)** |

## Fields of the synced tables

### Sync columns (all 9 synced tables)

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `id` | Optional on create: the server creates one if it's missing. Can't change. | UUID | Cet identifiant est déjà utilisé. **(same on server)** |
| `version` | Starts at 1. Ignored on create. **Required on every update**, and must match the server, or the answer is 409. | 1–2147483647 | OBLIGATOIRE, NOMBRE |
| `device_id` | Read from the `X-Device-Id` header. A value in the body is ignored. Longer text is cut at 100 characters. | Up to 100 characters | – |
| `deleted_at` | Set by the server. A value in the body is ignored. | Date and time | – |

### cycle

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `user_id` | A beneficiaire leaves it out. An admin must send it. Can't change. | User UUID | OBLIGATOIRE |
| `date_debut` | Required | Date | OBLIGATOIRE |
| `date_fin` | Optional (null) | Date | DATE |
| `intensite` | Required | `faible`, `moyenne`, `forte` | CHOIX |
| `symptome` | Optional (empty text) | Any text | – |
| `duree_cycle` | Optional (null) | Whole number, 0–32767 | NOMBRE |
| `duree_regle` | Optional (null) | Whole number, 0–32767 | NOMBRE |
| `estimation_prochain` | Optional (null) | Date | DATE |

### grossesse

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `user_id` | A beneficiaire leaves it out. An ASC must send a beneficiaire of their region, and an admin any beneficiaire. Can't change. | User UUID | OBLIGATOIRE |
| `ddr` | Required | Date | OBLIGATOIRE |
| `dpa` | Required | Date | OBLIGATOIRE |

### danger_grossesse

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `grossesse_id` | Taken from the address | Pregnancy UUID | – |
| `type_danger_grossesse_id` | Required | Id from `type_danger_grossesse` | OBLIGATOIRE |
| `date_signalement` | Optional: the server uses the current time if it's missing | Date and time | DATE |
| `csb_id` | Optional, only used when an ASC creates the sign. A missing or wrong value never refuses the sign: it's saved with a warning and without a referral. | Id from `csb` | – |

### enfant

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `nom` | Required | Up to 150 characters | OBLIGATOIRE, LONGUEUR |
| `mere_id` | Optional (null). For an ASC, a beneficiaire of their region. | User UUID | – |
| `asc_id` | An ASC leaves it out. An admin must send it. | User UUID | OBLIGATOIRE |
| `grossesse_id` | Optional (null). See the linked rule above. | Pregnancy UUID | – |
| `region_id` | Required | Id from `region` | OBLIGATOIRE |
| `date_naissance` | Required | Date | OBLIGATOIRE |
| `sexe` | Required | `M`, `F` | CHOIX |
| `statut_prise_en_charge` | Default `aucun` | `aucun`, `suivi`, `refere`, `pris_en_charge`, `gueri`, `abandon` | CHOIX |

### mesure

The limits on `poids_kg`, `taille_cm` and `pb_mm` are listed above under "Rules that link several fields".

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `enfant_id` | Required, or taken from the address. Can't change. | Child UUID | OBLIGATOIRE |
| `asc_id` | Optional: it defaults to the child's ASC | User UUID | – |
| `date_mesure` | Required | Date | OBLIGATOIRE |
| `poids_kg` | Required, 2 decimals | See limits above | OBLIGATOIRE, NOMBRE |
| `taille_cm` | Required, 1 decimal | See limits above | OBLIGATOIRE, NOMBRE |
| `position` | Required | `couche`, `debout` | CHOIX |
| `pb_mm` | Optional (null), whole number | See limits above | NOMBRE |
| `oedemes_bilateraux` | Default `aucun` | `aucun`, `+`, `++`, `+++` | CHOIX |
| `signes_danger` | Optional, default `[]`. Codes from `signes_danger.enfant` of the clinical config. | List of up to 20 texts of up to 50 characters | – |
| `complications_medicales` | Default `false` | `true`, `false` | – |
| `appetit` | Default `non_teste` | `non_teste`, `bon`, `mauvais` | CHOIX |
| `difficultes_allaitement` | Default `false` (used under 6 months) | `true`, `false` | – |
| `classification`, `orientation_centre`, `urgence`, `date_prochain_controle`, `config_version` | Calculated by the server. A value in the body is ignored. | – | – |
| `age_jour` | Calculated by the server. A value in the body is ignored. | – | – |
| `age_mois` | Calculated by the server. A value in the body is ignored. | – | – |
| `taille_corrigee_cm` | Calculated by the server. A value in the body is ignored. | – | – |
| `waz` | Optional (null), 2 decimals | -999.99 to 999.99 | NOMBRE |
| `haz` | Optional (null), 2 decimals | -999.99 to 999.99 | NOMBRE |
| `whz` | Optional (null), 2 decimals | -999.99 to 999.99 | NOMBRE |
| `flag_aberrant` | Default `false` | `true`, `false` | – |
| `alerte` | Required | `vert`, `orange`, `rouge` | CHOIX |
| `motif_alerte` | Optional (empty text) | Any text | – |
| `ref_oms` | Default `WHO2006` | Up to 20 characters | LONGUEUR |

**Calculated by the server** (the app must use the same formulas offline):

- `age_jour` = `date_mesure` – `date_naissance`, in days.
- `age_mois` = `age_jour / 30.4375`, rounded down.
- `taille_corrigee_cm`: under 731 days and `debout`, `taille_cm + 0.7`. From 731 days and `couche`, `taille_cm - 0.7`. Otherwise `taille_cm`.

- `waz`, `haz`, `whz`: WHO 2006 LMS formula (WHO's restricted method beyond ±3 SD for weight-based indicators), from `reference_oms`. Weight-for-length under 731 days, weight-for-height from 731 days, both on `taille_corrigee_cm`. Rounded to 2 decimals. **Only when the WHO table of the indicator is loaded**; otherwise the phone's value is kept. Empty when the child is outside the table.
- `classification`, `orientation_centre`, `urgence`, `date_prochain_controle`: rules of the published clinical config (`malnutrition` section), saved with its `config_version`. Empty when no config is published.
- `flag_aberrant`: the phone's value is kept; the server sets it to `true` when a z-score is outside `malnutrition.plausibilite` of the config. On an update the server re-evaluates it: resend `flag_aberrant: true` if the phone's own check still applies.
- `alerte` and `motif_alerte` are kept as the phone sends them.

### journal_alimentaire

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `enfant_id` | Required | Child UUID | OBLIGATOIRE |
| `date_jour` | Required | Date | OBLIGATOIRE |
| `type_allaitement` | Required | `exclusif`, `mixte`, `aucun` | CHOIX |
| `g1_lait_maternel` to `g8_autres_fruits_legumes` | Default `false` | `true`, `false` | – |
| `notes` | Optional (empty text) | Any text | – |

### referencement

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `code_unique` | Optional: the server creates `R-<first 4 chars of the ASC id>-<MMDD>-<n>` if it's missing. Can't change. The phone normally sends its offline code, for example `TRK-7F3K-92`. | Up to 30 characters | LONGUEUR |
| `origine` | Required | `enfant`, `grossesse` | CHOIX |
| `enfant_id` | Optional (null), see linked rule above | Child UUID | – |
| `grossesse_id` | Optional (null), see linked rule above | Pregnancy UUID | – |
| `mesure_id` | Optional (null), see linked rule above | Visit UUID | – |
| `asc_id` | An ASC leaves it out. An admin must send it for a pregnancy. | User UUID | OBLIGATOIRE |
| `csb_id` | Required | Id from `csb` | OBLIGATOIRE |
| `priorite` | Required | `urgente`, `haute`, `normale` | CHOIX |
| `motif` | Required | Any text | OBLIGATOIRE |
| `status` | Starts at `envoye`. Only changes through `/api/referrals/{id}/status/`. | `envoye`, `recu`, `pris_en_charge`, `en_suivi`, `sortie` | CHOIX |
| `date_referencement` | Optional: when the ASC referred, on the phone. Default: the server's time. Can't change. | Date and time | DATE |
| `date_reception`, `date_prise_en_charge`, `date_sortie`, `issue_sortie` | Set by the server when the status changes. A value in the body is ignored. | – | – |
| `urgence`, `en_retard` | Calculated, read only: `urgence` from `priorite` (`urgente` = `rouge`, `haute` = `orange`, `normale` = `jaune`); `en_retard` = still `envoye` after the config's delay. | – | – |

### consultation_nutritionnelle

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `enfant_id` | Required | Child UUID | OBLIGATOIRE |
| `mesure_id` | Optional (null) | Visit UUID | – |
| `referencement_id` | Optional (null) | Referral UUID | – |
| `csb_id` | An agent_csb leaves it out: it is their centre. An admin must send it. | Id from `csb` | OBLIGATOIRE |
| `agent_medical_id` | An agent_csb leaves it out: it is them. An admin must send an agent_csb. | User UUID | OBLIGATOIRE |
| `date` | Required | Date | OBLIGATOIRE |
| `diagnostic` | Required | Any text | OBLIGATOIRE |
| `decision` | Required | `conseil`, `reference`, `prise_en_charge` | CHOIX |
| `observations` | Optional (empty text) | Any text | – |

### journal_alimentaire (read only fields)

| Field | Rule |
|---|---|
| `score_diversite` | Calculated by the server: number of `g1`–`g8` that are true. |
| `diversite_minimale_atteinte` | Calculated, read only: `score_diversite` ≥ `alimentation_enfant.diversite_minimale_groupes` of the config, or `null` without config. |

### rendez_vous

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `enfant_id` | Required, a child the user can see. Can't change. | Child UUID | OBLIGATOIRE |
| `referencement_id` | Optional (null), see linked rule above | Referral UUID | – |
| `csb_id` | Optional (null). An agent_csb leaves it out: it is their centre. | Id from `csb` | – |
| `date_prevue` | Required | Date | OBLIGATOIRE |
| `type_rendez_vous` | Default `controle` | `controle`, `depistage` | CHOIX |
| `statut` | Default `prevu` | `prevu`, `honore`, `annule` | CHOIX |
| `motif` | Optional (empty text) | Any text | – |
| `manque` | Calculated, read only: `prevu` and `date_prevue` before today | – | – |

## Sync operations (`/api/sync/push/`)

| Field | Rule | Allowed values |
|---|---|---|
| `operations` | Required, 1 to 100 operations, applied in order | List |
| `cle_idempotence` | Required, one new UUID per operation, kept until the server answers | UUID |
| `table` | Required | `cycle`, `grossesse`, `danger_grossesse`, `enfant`, `mesure`, `journal_alimentaire`, `referencement`, `consultation_nutritionnelle`, `rendez_vous` |
| `operation` | Required | `create`, `update`, `delete` |
| `id` | Required: the row's UUID, created on the phone | UUID |
| `version` | Required for `update`: the version the phone knows. Optional for `delete` (checked if sent). | Whole number ≥ 1 |
| `donnees` | The row's fields, with the same rules as the REST endpoint of the table. For `danger_grossesse`, `grossesse_id` is required on create. | Object |

## Accounts

### utilisateur

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `identifiant` | Required, unique | Up to 50 characters | OBLIGATOIRE, LONGUEUR, Cet identifiant est déjà utilisé. **(same on server)** |
| `nom` | Required | Up to 100 characters | OBLIGATOIRE, LONGUEUR |
| `prenom` | Required | Up to 100 characters | OBLIGATOIRE, LONGUEUR |
| `email` | Optional (empty text), valid email format | Up to 254 characters | Saisissez une adresse e-mail valide. |
| `phone` | Optional (empty text), **not unique** | Up to 20 characters | LONGUEUR |
| `profile_code` | An ASC leaves it out and can only create `beneficiaire`. A supervisor leaves it out and can only create `asc` (in their region, if they have one). An admin must send it. | Code from `profile` | OBLIGATOIRE |
| `consentement` | Default `false` | `true`, `false` | – |
| `region_id` | Required for a beneficiaire. An ASC can't choose it: the account takes the ASC's region. Optional (null) for the other profiles. | Id from `region` | La région est obligatoire pour une bénéficiaire. **(same on server)** |
| `csb_id` | Required for an agent_csb. Always empty for the other profiles. | Id from `csb` | Le CSB est obligatoire pour un agent de CSB. **(same on server)** |
| `pin` | Required on create only, same format as `nouveau_pin` below | 4 to 6 digits | Le PIN doit contenir de 4 à 6 chiffres. **(same on server)** |

### PIN

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `nouveau_pin` | Required, digits 0–9 only | 4 to 6 digits | Le PIN doit contenir de 4 à 6 chiffres. **(same on server)** |

The login doesn't check the PIN format: a badly formatted PIN just counts as a wrong PIN.

### Two-factor login and erasure

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `code_totp` (login) | Required once the account turned 2FA on, ignored otherwise. A wrong code counts as a failed attempt. A code is accepted once. | 6 digits | Saisissez le code à 6 chiffres… / Code d'authentification incorrect. **(same on server)** |
| `code` (`/2fa/activate/`, `/2fa/disable/`) | Required | 6 digits | Code d'authentification incorrect. **(same on server)** |
| `pin` (`/my-data/erase/`, `/2fa/disable/`) | Required; a wrong PIN counts as a failed attempt | The account's PIN | Le PIN est incorrect. **(same on server)** |
| `inclure_enfants` (erasure) | Default `false` | `true`, `false` | – | Administration accounts (`is_staff`) use a password instead of a PIN, and it follows Django's password rules.

### Failed attempts

The server applies these rules, so the app only has to show the message it receives. See `docs/endpoint.md`.

| Wrong PINs in a row | Result |
|---|---|
| 5 | Blocked for 15 minutes |
| 10 | Blocked for 1 hour |
| 15 | Blocked until an administrator unblocks the account |

Only a correct PIN resets the count. A block ending doesn't reset it.

## Server-managed tables

The phone reads these tables and never changes them, so it doesn't need to apply these rules. They are listed so this file covers every rule.

| Table | Field | Rule | Allowed values |
|---|---|---|---|
| province | `nom` | Required | Up to 100 characters |
| region | `nom` | Required | Up to 100 characters |
| region | `province_id` | Required | Id from `province` |
| profile | `code` | Required, unique | Up to 30 characters. Known to the API: `beneficiaire`, `asc`, `agent_csb`, `superviseur`, `admin` |
| profile | `libelle` | Required | Up to 100 characters |
| csb | `name` | Required | Up to 150 characters |
| csb | `region_id` | Required | Id from `region` |
| csb | `tel` | Required | Up to 20 characters |
| csb | `type_centre` | Default `csb` | `csb`, `crenam`, `crenas`, `creni` |
| type_danger_grossesse | `description` | Required | Any text |
| reference_oms | `indicateur` | Required | `wfa`, `lhfa`, `wfl`, `wfh` |
| reference_oms | `sexe` | Required | `M`, `F` |
| reference_oms | `cle` | Required, 1 decimal | Up to 99999.9 |
| reference_oms | `l`, `m` | Required, 4 decimals | Up to 9999.9999 in absolute value |
| reference_oms | `s` | Required, 5 decimals | Up to 999.99999 in absolute value |
| reference_oms | `mesure_type` | Optional (empty text) | `L`, `H` |
| reference_oms | `indicateur` + `sexe` + `cle` | Unique together | – |
| journal_audit | `user_id` | Optional (null), so failed logins can be recorded | User UUID |
| journal_audit | `action` | Required | Up to 50 characters |
| journal_audit | `table_nom` | Optional (empty text) | Up to 100 characters |
| journal_audit | `ligne_id` | Optional (null) | UUID |
| journal_audit | `details` | Optional, default `{}` | JSON |
| historique_version | `table_nom` | Required | Up to 100 characters |
| historique_version | `ligne_id` | Required | UUID |
| historique_version | `version` | Required | 0–2147483647 |
| historique_version | `donnees` | Required | JSON |
| historique_version | `device_id` | Optional (empty text) | Up to 100 characters |
| historique_version | `table_nom` + `ligne_id` + `version` + `device_id` | Unique together | – |
| configuration_clinique | `contenu` | Required; the `malnutrition` section must follow `config_clinique/schema.json` | JSON |
| configuration_clinique | `contenu`, `libelle`… | Can't change once `publiee` | – |
| configuration_clinique | publication | With `CONFIG_VALIDEE_OBLIGATOIRE=True`: `statut_validation = validee` and `valide_par`, `reference_validation`, `date_validation` filled | – |
| operation_sync | `cle_idempotence` | Unique | UUID |
| conflit_sync | resolution | Once only; `fusion` needs `donnees` | `serveur`, `telephone`, `fusion` |

## What the server does not check

The models don't enforce these. If the app needs them, they have to be added on the app side:

- `date_fin` is on or after `date_debut`, or `dpa` is after `ddr`.
- When `flag_aberrant` should be set for unusual raw values (weight, length): the server only adds the flag from the z-scores, when the WHO tables are loaded.
