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

## D7. Referral lifecycle follows the spec

- Spec §7: `Référé → Reçu → Pris en charge → En suivi → Sortie`. The old
  `envoye → recu → vu → pris_en_charge → clos` conflicted with it, so the
  values are now `envoye` (Référé), `recu`, `pris_en_charge`, `en_suivi`,
  `sortie`. Migration: `vu` → `recu`, `clos` → `sortie` (no outcome: it was
  never recorded).
- Steps are one at a time, except that a discharge is allowed as soon as the
  child has arrived (`recu`, `pris_en_charge` or `en_suivi`): a child can be
  transferred or die before being followed up. A referral never goes back.
- A discharge needs `issue_sortie` (`gueri`, `transfere`, `non_repondant`,
  `abandon`, `decede`) and can only be recorded by an `agent_csb` of the
  destination centre (P6: "seul un professionnel habilité"). The admin keeps
  the other transitions (existing behaviour) but not the discharge.
- "Patient arrivé" is `POST /api/referrals/{id}/status/` with `recu`. Dates
  `date_reception`, `date_prise_en_charge`, `date_sortie` are set by the server.
- New `date_referencement`, sent by the phone (the referral is made offline
  and may sync days later). It is what the "not arrived after 48 h" list and
  the "delay referral → arrival" statistic use. Default: server time.
- The child's `statut_prise_en_charge` follows: `pris_en_charge`, `suivi`, then
  the exit outcome. New child statuses `transfere`, `non_repondant`, `decede`.
- The "not arrived" delay comes from the config
  (`malnutrition.suivi.delai_alerte_non_arrivee_heures`). With no published
  config the list is empty rather than using a hard-coded 48 h.

## D8. Appointments, consultations, food logs

- New synced table `rendez_vous` (follow-up or screening visit). "Manqué" is
  computed (still `prevu` after `date_prevue`), never stored, so it can't go
  stale. A centre agent always books in their own centre.
- "Enfants à revoir" = children whose latest measurement has a
  `date_prochain_controle` (from the orientation rule of the config) that is
  due. Dead children are left out.
- `consultation_nutritionnelle` and `journal_alimentaire` existed in the
  database without an API; they now have `/api/consultations/` (written by the
  centre agent, who is forced as `agent_medical` and their centre as `csb`) and
  `/api/food-logs/` (written by the mother, the ASC or an admin).

## D9. Outbox sync: one push endpoint, one pull endpoint

- `POST /api/sync/push/` takes up to 100 operations
  `{cle_idempotence, table, operation (create|update|delete), id, version, donnees}`.
  They are applied **in the order sent** (a child before its measurement),
  each in its own savepoint: one refused operation never blocks the others.
  Every operation goes through the same ViewSet, serializer, services and
  permissions as the REST endpoint of its table, so the rules can't drift.
- Each operation gets its own answer: `applique`, `deja_applique`, `conflit`,
  `erreur`, `refuse` or `introuvable`. The phone maps them to the statuses of
  spec §9 (`applique`/`deja_applique` → Synchronisé, `conflit` → Conflit).
- Idempotency: the answer to a final operation (`applique`, `deja_applique`,
  `conflit`) is stored with its key (`operation_sync`); the same key gets the
  same answer with `rejoue: true` and nothing is applied twice. Errors are
  **not** stored, so the phone can retry once the cause is fixed (for example
  a referral sent before its child). A key reused by another user is refused.
  A create with a known `id` but a new key also answers `deja_applique`.
- `GET /api/sync/pull/?depuis=…` returns, per table, the rows the user may
  read changed since `depuis`, **soft-deleted rows included** (with
  `deleted_at`), which is how deletions now reach other phones. It also returns
  the state of the user's conflicts and the clinical config when the phone's
  `config_version` is older. `horodatage_serveur` is the request time minus
  5 seconds, so a row committed during the pull is sent again next time rather
  than missed (receiving a row twice is harmless).
- Gzip request bodies are accepted (`Content-Encoding: gzip`, size capped) and
  responses are gzipped when the phone accepts it. TLS is the reverse proxy's
  job (deployment).
- The per-row REST endpoints are unchanged and keep answering `409` on a
  version mismatch: they are used online by the web dashboard, where the user
  sees the conflict at once.

## D10. Conflict queue

- On a **clinical** table (pregnancy, danger sign, child, measurement,
  referral, consultation, appointment), a push whose `version` is not the
  server's never overwrites: both versions are stored (`conflit_sync`, and two
  `historique_version` rows with `conflit = true`), the row is unchanged, and
  the phone gets `conflit` with the server row and the conflict id.
- Personal data (`cycle`, `journal_alimentaire`) is not shown to health workers
  (P5): the phone gets `conflit` with the server row and decides itself.
- A centre agent sees the conflicts on rows they can see; an admin sees all;
  an ASC or a beneficiary sees the ones they sent (read only); a supervisor
  sees none. Only a centre agent or an admin resolves:
  `serveur`, `telephone` or `fusion` (with the merged data).
- The decided data is validated in the **sender's** scope (as if their change
  had gone through) and recorded in the audit log under the **arbiter's**
  name. The row always gets a new version, even when the server's version is
  kept, so every phone pulls the decision.
- Known limit: an update pushed for a row that was deleted on the server meanwhile
  answers `introuvable`; the deletion is not put in the conflict queue.

## D11. Supervisor statistics

- `GET /api/stats/` and `GET /api/stats/export/` (CSV), for supervisors and
  admins. Parameters: `date_debut`, `date_fin` (default: last 30 days),
  `region` or `province`, `grouper_par=region|mois`.
- A regional supervisor is locked to their region (`403` for another one).
- Small counts: any count from 1 to 4 is replaced by `null` and listed in
  `masques` (CSV: `<5`). 0 is shown: it reveals nobody. A rate or an average
  computed on fewer than 5 cases is hidden too. The threshold is the setting
  `TARANAKA_SEUIL_PETITS_EFFECTIFS` (a privacy rule, not a clinical one).
- Zone of each indicator: screenings, MAS/MAM cases and missed appointments
  use the **child's region**; referrals, arrivals and exits use the **region
  of the destination centre** (what a district/region team supervises).
- "Cas MAS / MAM" count **distinct children** with at least one such
  measurement in the period; "dépistages" counts measurements.
- Known limit: no complementary suppression. With `grouper_par`, a hidden
  group value can sometimes be deduced from the total minus the other groups.
- Each CSV export is written to the audit log (`export_csv`).
