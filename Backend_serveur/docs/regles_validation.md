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

The server returns the same wording only for rules marked **(same on server)**. For the other rules, the server currently returns Django's default English message, so the wording here is for the app.

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
| mesure | `pb_mm`, `age_mois` | `pb_mm` must be `null` unless `age_mois` is from 6 to 59. Hide the field outside that age. | `age_mois` 6–59 | Le périmètre brachial ne peut être saisi qu'entre 6 et 59 mois. **(same on server)** |
| journal_alimentaire | `enfant_id`, `date_jour` | Only one row per child per day. Soft-deleted rows don't count. | – | Un journal existe déjà pour cet enfant à cette date. **(same on server)** |
| journal_alimentaire | `score_diversite` | Stays in range. It equals the number of `g1`–`g8` fields that are true. The server recalculates it on every save. | 0–8 | Le score de diversité doit être compris entre 0 et 8. **(same on server)** |
| referencement | `origine`, `enfant_id` | If `origine` = `enfant`, `enfant_id` is required | – | Un référencement enfant doit indiquer l'enfant, et un référencement grossesse doit indiquer la grossesse. **(same on server)** |
| referencement | `origine`, `grossesse_id` | If `origine` = `grossesse`, `grossesse_id` is required | – | Same message as above **(same on server)** |
| referencement | `code_unique` | Unique across all rows, including soft-deleted rows | – | Ce code de référencement existe déjà. **(same on server)** |

## Fields of the synced tables

### Sync columns (all 8 synced tables)

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `id` | Required | UUID | OBLIGATOIRE |
| `version` | Whole number, starts at 1 | 0–2147483647 | NOMBRE |
| `device_id` | Optional (empty text) | Up to 100 characters | LONGUEUR |
| `deleted_at` | Optional (null) | Date and time | DATE |

### cycle

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `user_id` | Required | User UUID | OBLIGATOIRE |
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
| `user_id` | Required | User UUID | OBLIGATOIRE |
| `ddr` | Required | Date | OBLIGATOIRE |
| `dpa` | Required | Date | OBLIGATOIRE |

### danger_grossesse

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `grossesse_id` | Required | Pregnancy UUID | OBLIGATOIRE |
| `type_danger_grossesse_id` | Required | Id from `type_danger_grossesse` | OBLIGATOIRE |
| `date_signalement` | Required | Date and time | OBLIGATOIRE |

### enfant

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `nom` | Required | Up to 150 characters | OBLIGATOIRE, LONGUEUR |
| `mere_id` | Optional (null) | User UUID | – |
| `asc_id` | Required | User UUID | OBLIGATOIRE |
| `grossesse_id` | Optional (null) | Pregnancy UUID | – |
| `region_id` | Required | Id from `region` | OBLIGATOIRE |
| `date_naissance` | Required | Date | OBLIGATOIRE |
| `sexe` | Required | `M`, `F` | CHOIX |
| `statut_prise_en_charge` | Default `aucun` | `aucun`, `suivi`, `refere`, `pris_en_charge`, `gueri`, `abandon` | CHOIX |

### mesure

The limits on `poids_kg`, `taille_cm` and `pb_mm` are listed above under "Rules that link several fields".

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `enfant_id` | Required | Child UUID | OBLIGATOIRE |
| `asc_id` | Required | User UUID | OBLIGATOIRE |
| `date_mesure` | Required | Date | OBLIGATOIRE |
| `poids_kg` | Required, 2 decimals | See limits above | OBLIGATOIRE, NOMBRE |
| `taille_cm` | Required, 1 decimal | See limits above | OBLIGATOIRE, NOMBRE |
| `position` | Required | `couche`, `debout` | CHOIX |
| `pb_mm` | Optional (null), whole number | See limits above | NOMBRE |
| `oedemes_bilateraux` | Default `aucun` | `aucun`, `+`, `++`, `+++` | CHOIX |
| `age_jour` | Required, whole number | 0–2147483647 | OBLIGATOIRE, NOMBRE |
| `age_mois` | Required, whole number | 0–32767 | OBLIGATOIRE, NOMBRE |
| `taille_corrigee_cm` | Required, 1 decimal | Up to 9999.9 | OBLIGATOIRE, NOMBRE |
| `waz` | Optional (null), 2 decimals | -999.99 to 999.99 | NOMBRE |
| `haz` | Optional (null), 2 decimals | -999.99 to 999.99 | NOMBRE |
| `whz` | Optional (null), 2 decimals | -999.99 to 999.99 | NOMBRE |
| `flag_aberrant` | Default `false` | `true`, `false` | – |
| `alerte` | Required | `vert`, `orange`, `rouge` | CHOIX |
| `motif_alerte` | Optional (empty text) | Any text | – |
| `ref_oms` | Default `WHO2006` | Up to 20 characters | LONGUEUR |

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
| `code_unique` | Required | Up to 30 characters | OBLIGATOIRE, LONGUEUR |
| `origine` | Required | `enfant`, `grossesse` | CHOIX |
| `enfant_id` | Optional (null), see linked rule above | Child UUID | – |
| `grossesse_id` | Optional (null), see linked rule above | Pregnancy UUID | – |
| `mesure_id` | Optional (null) | Visit UUID | – |
| `asc_id` | Required | User UUID | OBLIGATOIRE |
| `csb_id` | Required | Id from `csb` | OBLIGATOIRE |
| `priorite` | Required | `urgente`, `haute`, `normale` | CHOIX |
| `motif` | Required | Any text | OBLIGATOIRE |
| `status` | Default `envoye` | `envoye`, `recu`, `vu`, `pris_en_charge`, `clos` | CHOIX |

### consultation_nutritionnelle

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `enfant_id` | Required | Child UUID | OBLIGATOIRE |
| `mesure_id` | Optional (null) | Visit UUID | – |
| `referencement_id` | Optional (null) | Referral UUID | – |
| `csb_id` | Required | Id from `csb` | OBLIGATOIRE |
| `agent_medical_id` | Required | User UUID | OBLIGATOIRE |
| `date` | Required | Date | OBLIGATOIRE |
| `diagnostic` | Required | Any text | OBLIGATOIRE |
| `decision` | Required | `conseil`, `reference`, `prise_en_charge` | CHOIX |
| `observations` | Optional (empty text) | Any text | – |

## Accounts

### utilisateur

| Field | Rule | Allowed values | Error message |
|---|---|---|---|
| `identifiant` | Required, unique | Up to 50 characters | OBLIGATOIRE, LONGUEUR, Cet identifiant est déjà utilisé. **(same on server)** |
| `nom` | Required | Up to 100 characters | OBLIGATOIRE, LONGUEUR |
| `prenom` | Required | Up to 100 characters | OBLIGATOIRE, LONGUEUR |
| `email` | Optional (empty text), valid email format | Up to 254 characters | Saisissez une adresse e-mail valide. |
| `phone` | Optional (empty text), **not unique** | Up to 20 characters | LONGUEUR |
| `role` | Required | `femme`, `asc`, `agent_csb`, `admin` | CHOIX |
| `consentement` | Default `false` | `true`, `false` | – |
| `profile_id` | Optional (null) | Id from `profile` | – |
| `region_id` | Optional (null) | Id from `region` | – |

**PIN:** the PIN format is not defined in the models yet. It will be validated separately in the login.

## Server-managed tables

The phone reads these tables and never changes them, so it doesn't need to apply these rules. They are listed so this file covers every rule.

| Table | Field | Rule | Allowed values |
|---|---|---|---|
| province | `nom` | Required | Up to 100 characters |
| region | `nom` | Required | Up to 100 characters |
| region | `province_id` | Required | Id from `province` |
| profile | `type` | Required | `femme`, `mere`, `asc`, `agent_csb`, `admin` |
| csb | `name` | Required | Up to 150 characters |
| csb | `region_id` | Required | Id from `region` |
| csb | `tel` | Required | Up to 20 characters |
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

## What the server does not check

The models don't enforce these. If the app needs them, they have to be added on the app side:

- `date_fin` is on or after `date_debut`, or `dpa` is after `ddr`.
- `age_jour` and `age_mois` match `date_naissance` and `date_mesure`.
- A referral has only the link that matches its `origine`. For example, a child referral can also have a `grossesse_id`.
- When `flag_aberrant` should be set. The rule for unusual values is not in the models.
