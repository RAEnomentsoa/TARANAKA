# TARANAKA backend – Decisions

Decisions taken while finishing the MVP backend, where the spec was ambiguous
or silent. Each one follows the principles of `docs/SPEC.md` §1, quoted as
**P1** (offline first) … **P7** (shared phone).

## D1. Supervisor profile and scope

- A new profile `superviseur` is added (migration `comptes/0005`).
- Its zone is its `region_id`. A supervisor without a region is national /
  programme level. There is no district table in the schema yet, so "district"
  supervisors are not possible without a schema change.
- A supervisor **never reads an individual health record** (spec §10:
  aggregated and anonymous only). All row endpoints answer `403`.
- Spec §2 and §8 also say agent accounts are "created by a supervisor" and
  "reset by the supervisor". So the supervisor can create `asc` accounts in
  their region, read those accounts (identity only, no health data) and reset
  their PIN with `POST /api/profiles/{id}/reset-pin/`. They cannot edit or
  deactivate accounts: that stays with the admin.
- Read access lists that used `tuple(CodeProfile.values)` were replaced by an
  explicit `PROFILS_DOSSIERS`, so a new profile never gets access by accident.

## D2. Centre types

- Spec §7 needs CRENI, CRENAS and CRENAM as referral destinations. Instead of
  new tables, the existing `csb` table gets `type_centre`
  (`csb`, `crenam`, `crenas`, `creni`, default `csb`). Existing rows stay CSBs,
  existing API fields are unchanged, and an `agent_csb` attached to a CRENAS is
  the "infirmier du CRENAS" of scenario 8.

## D3. Login audit records the device

- Spec §2: "qui, quoi, quand, sur quel appareil". Login lines now also store
  `device_id` (from `X-Device-Id`) in `details`.
- `journal_audit` is append-only in code: `save()` on an existing line and
  `delete()` raise an error. Admins read it through `GET /api/audit/`.

## D4. Clinical configuration: one versioned JSON document

- New app `config_clinique`, table `configuration_clinique`. One row = one
  version: `contenu` (JSON), publication status (`brouillon` → `publiee` →
  `retiree`) and a separate validation status (`a_valider` / `validee`, with
  who validated, the reference of the written validation and its date).
- A published version never changes. The current version is the published one
  with the highest number; retiring it falls back to the previous one.
- Spec §11 requires written validation before production. The setting
  `CONFIG_VALIDEE_OBLIGATOIRE=True` (environment variable) refuses to publish a
  version that is not validated. It is `False` by default so the sample config
  marked "À VALIDER" can run the demo.
- The server checks the sections it executes (`malnutrition`) with a JSON
  schema (`config_clinique/schema.json`): unknown field names or operators are
  refused, so a typo can't silently disable a rule. The other sections
  (calendars, danger signs, advice, food list) are passed to the phone as is.
- Rules are declarative: ordered list, first match wins, conditions
  `inferieur_a`, `superieur_a`, `egal`, `dans`, `non_vide`… on named fields,
  with optional `age_mois_min` / `age_mois_max`. A condition on a missing value
  is false. The code holds no threshold, no destination and no delay.
- Malagasy sentences are left as `"mg": null` in the sample: they must be
  written and reviewed by native speakers (spec §11). Food names are given in
  Malagasy as in the spec.
- In the sample config every section and every rule carries
  `"statut": "À VALIDER"` (marking each number individually would make the
  rule format unreadable for the phone).

## D5. Who classifies: the server re-computes

- The phone classifies offline (P1). The server re-applies the published config
  to every measurement it receives and stores `classification`,
  `orientation_centre`, `urgence`, `date_prochain_controle` and the
  `config_version` used. Values sent by the phone for these fields are ignored,
  like `age_jour`.
- Without a published config, the fields stay empty: a measurement is never
  refused because the config is missing (P1).
- `alerte` / `motif_alerte` (the parent's traffic light) are unchanged: still
  sent by the phone.
- Spec "MAM: -3 ≤ P/T < -2" is applied as "not MAS, and WHZ < -2": a WHZ of
  exactly -3.00 is MAM, -3.01 is MAS. Same for MUAC: 115 mm is MAM, 114 is MAS.
- Under 6 months, oedema is classed "nourrisson à risque" (not MAS) and always
  sent to a professional, as the spec says for infants.
- Orientation `urgence` (rouge/orange/jaune) maps to the existing referral
  `priorite` values: rouge = `urgente`, orange = `haute`, jaune = `normale`.
  The referral keeps `priorite` (no breaking change) and gains a read-only
  `urgence`.

## D6. WHO z-scores on the server

- `waz`, `haz`, `whz` are computed with the WHO LMS formula (with WHO's
  restricted method beyond ±3 SD for weight-based indicators) from
  `reference_oms`. Weight-for-length is used under 731 days, weight-for-height
  from 731 days, on the corrected length.
- The WHO tables are **not committed** (the WHO `anthro` package that publishes
  them is GPL-3). `python manage.py importer_tables_oms <folder>` loads
  `weianthro.txt`, `lenanthro.txt`, `wflanthro.txt` and `wfhanthro.txt` from
  https://github.com/WorldHealthOrganization/anthro (`data-raw/growthstandards`).
- When an indicator's table is not loaded, the phone's value is kept (previous
  behaviour). When it is loaded, the server's value wins, and is empty outside
  the table (for example a length under 45 cm).
- `flag_aberrant`: the phone's flag is kept; the server adds one when a z-score
  is outside the config's `plausibilite` range.
