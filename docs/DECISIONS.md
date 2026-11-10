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
  is outside the config's `plausibilite` range. On an update the server
  re-evaluates it, so a corrected measurement loses the flag: the phone resends
  `flag_aberrant: true` if its own check still applies.

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
- When a table has more rows than `limite`, the answer says `suite: true` with
  a cursor `prochain_depuis` + `apres_id` (keyset on `updated_at`, `id`), so
  rows sharing the same timestamp are never skipped nor repeated forever.
  Datetimes keep their microseconds in the answer for that reason.
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
- Complementary suppression (added after the web dashboard's review, issue 2
  of `docs/API_ISSUES.md`): for each count, if exactly one group is hidden
  while the total is shown, the smallest other group is hidden too (a 0 only
  if nothing else is left); with a single group, the total is hidden. The
  arrivals and the arrival rate are hidden when 1 to 4 referrals didn't
  arrive, since "referrals − arrivals" would reveal that small count. The
  screen and the CSV hide exactly the same values.
- Each CSV export is written to the audit log (`export_csv`).

## D12. Two-factor login (TOTP) for web accounts

- Spec §2: CSB/CRENAS/CRENI staff and supervisors use the web with "double
  authentification". TOTP (RFC 6238: HMAC-SHA1, 30 s, 6 digits) works offline
  with any authenticator app and needs no SMS. It is written with the Python
  standard library: no new dependency.
- Concerns `agent_csb`, `superviseur` and `admin`. ASCs and beneficiaries use
  the phone with a PIN (spec §2 table) and are not concerned.
- `/api/auth/login/` stays compatible: an optional `code_totp` field. Once 2FA
  is active, a right PIN without code answers `401 totp_requis`, a wrong code
  `401 totp_invalide` and **counts as a failed attempt** (same lockout as a
  wrong PIN). The failure counter is only reset when both factors are right.
  A code is accepted one step before or after the current one, never twice.
  The response gets one additive field, `totp_a_configurer`.
- Enrolment: `POST /api/auth/2fa/setup/` (secret + `otpauth://` URI for a QR
  code), then `POST /api/auth/2fa/activate/` with a first code. Activation
  closes the other sessions and returns new tokens.
- `TOTP_OBLIGATOIRE=True` (environment variable, production): a web account
  without 2FA can still log in, but its token is marked `totp_a_configurer`
  and only opens `/api/auth/me/`, `/api/auth/changer-pin/` and
  `/api/auth/2fa/…`; every other endpoint answers `403`. Disabling 2FA is then
  refused. Default `False`, so development and the demo keep working.
- Lost phone: an admin calls `POST /api/profiles/{id}/reset-2fa/` (audited),
  and the person enrols again. No recovery codes in the MVP.
- Limits: the TOTP secret is stored in clear in the database (protect the
  database and its backups; encrypting it needs a key-management decision).
  Django's `/admin/` (staff accounts with a password) is not covered.

## D13. Rights of access and erasure (loi 2014-038)

- **Access**: `GET /api/auth/my-data/` for oneself, `GET /api/profiles/{id}/data/`
  for an admin answering a written request. The export holds the account (no
  PIN hash), and for a beneficiary every health row the server holds about her
  and her children (same scope as what she can read), plus the list of audit
  actions about her account. A health worker's export holds their account and
  audit trail, not their patients' records. Every export is audited
  (`acces_donnees`).
- **Erasure**: `POST /api/auth/my-data/erase/` by the beneficiary herself
  (PIN required; a wrong PIN counts as a failed attempt), or
  `POST /api/profiles/{id}/erase/` by an admin. Only beneficiary accounts:
  a professional account is deactivated instead, because its actions must stay
  traceable.
- What erasure does:
  - cycles: deleted for good (intimate data, spec §4);
  - pregnancies (and danger signs) without a referral: soft-deleted, so the
    ASCs' phones drop them at their next `/sync/pull/` (no endpoint changed);
  - pregnancies with a referral: **kept**, because the health facility must
    keep its clinical record, but they no longer point to an identifiable
    person;
  - children: the link to the mother (and her pregnancy) is removed. With
    `inclure_enfants: true` (she is the legal guardian), the child's name is
    replaced and, when there is no referral, the child and its measurements,
    food logs, appointments and consultations are soft-deleted;
  - the account is anonymised (name, identifier, phone, email), deactivated,
    its PIN made unusable and its sessions closed. The region is kept: alone
    it identifies nobody, and the ASCs see her rows through it, so their
    phones receive the deletions;
  - copies kept by the sync (`operation_sync`, `historique_version`,
    `conflit_sync`) for the erased rows and her own pushes are deleted.
- The audit log is **not** erased (traceability obligation); it only points to
  the anonymised account. The erasure itself is audited with counts only
  (`effacement_donnees`), never names or health values.
- Statistics already computed are anonymous and unaffected.

## D14. Fixes asked by the web dashboard (`docs/API_ISSUES.md`)

- **CSV export:** the view always answers CSV (`text/csv; charset=utf-8`)
  whatever the `Accept` header, so `text/csv` no longer gets `406` and the
  clients that send `application/json` or `*/*` keep working. Errors (`403`…)
  are also written as CSV lines.
- **Who to call:** referrals get `asc` and conflicts `expediteur`
  (`nom`, `prenom`, `phone`), read only, **for staff only**: `asc`,
  `agent_csb`, `admin`. A beneficiary gets `null`; a supervisor has no access
  to these endpoints. The ASC's phone is professional contact data that the
  centre needs to follow up a referral that didn't arrive.
- **`date_suivi`:** set when the status becomes `en_suivi`. For existing rows
  the migration takes the exact date from the audit log (`status_change` to
  `en_suivi`), never a guess.
- **WHO curves:** `GET /api/who-reference/` serves only rows of the loaded
  official tables (`reference_oms`) with the -3/-2/0/+2/+3 SD curves computed
  from their LMS values (WHO formula). No table loaded: `404`, nothing
  invented. Readable by every logged-in profile (reference data, not personal).
- **Deployment:** `USE_X_FORWARDED_HOST` and `CORS_ALLOWED_ORIGINS` are
  environment variables (default off / empty), documented with
  `TOTP_OBLIGATOIRE=True` in `Backend_serveur/docs/deployment.md` and
  `Backend_serveur/.env.production.example`. CORS uses `django-cors-headers`
  (new dependency); a single domain for the dashboard and the API remains the
  recommended setup.
- Left for later, as asked: TOTP backup codes, and server error messages in
  Malagasy (issue 9).

## D15. Access requests for web accounts, and the supervisor's agents page

Not in the spec, asked by the team: a person can ask for a web account from
the login page, and an admin approves it first.

- **Who can ask:** `agent_csb` (nurse or doctor of a CSB, CRENAS, CRENI,
  CRENAM) and `superviseur` only. An ASC is still created by their supervisor
  (spec §2, §8): they work in the field, often without email, and the
  supervisor knows them. A beneficiary registers from the phone (D16). An admin is never
  self-declared.
- **Nothing opens before approval.** A request lives in its own table
  (`demande_acces`), not as an inactive user: no account, no token, nothing
  listed anywhere else. An `agent_csb` account sees the records of its
  centre, so the admin, not the person, decides the profile, centre and
  region: they may correct them when approving.
- **Same login as today:** identifiant + PIN (chosen in the request), then
  the mandatory two-factor login on the web. The PIN is stored hashed in the
  request and erased once it is handled. No email login and no email
  verification: the admin's check (a phone call to the centre) is the real
  safeguard, and the server sends no email yet (none configured on the
  hosting). The phone number is therefore required; the email is optional.
- **Abuse:** the form is public, so it is throttled (5 per hour per address,
  `demande_acces` rate) and an identifiant can't be reserved twice by pending
  requests. The public options endpoint gives centre and region names only.
- **Audit:** `demande_acces_creee`, `demande_acces_approuvee` (plus `create`
  for the new account), `demande_acces_refusee`.
- **Supervisor's agents page:** the web dashboard now uses the existing
  `/api/profiles/` and `reset-pin` endpoints (D1) in a "Mes agents" page:
  list, create an ASC in the supervisor's region, reset a PIN. The PIN is
  shown once to the supervisor to hand over; the server never returns it.
  No change to the API or to the phone.
- **Usernames ignore case** (asked after review): a phone keyboard often
  capitalises the first letter, and an email used as a username may be typed
  in any case. Login (phone, web, Django admin) compares without case; a
  database constraint on `lower(identifiant)` refuses two accounts that differ
  only by case, and so does the access request check. The username is stored
  as typed. Migration `0008` stops with the list of conflicting usernames if
  an existing database already has some, so they can be renamed first. The
  web forms turn off auto-capitalisation on the username fields. No change on
  the phone: the server does the comparison.

## D16. Connected beneficiary: her own account, her data synced, files opened by health workers

Decided with the team and the mobile developer (plan:
`docs/PLAN_BENEFICIAIRE_CONNECTEE.md`). It replaces "Personnel : sans compte"
(spec §2) and "données du mode personnel uniquement si l'utilisatrice
l'active" (spec §9). It follows the original cahier des charges, where the
beneficiary has her own login and her records reach the server.

- **Account from the phone, no approval.** `POST /api/auth/register-beneficiary/`
  (public, 30 per hour per address) takes a first name, the region, a PIN and
  the consent (required, `true`). The server generates a readable username
  (`voahangy.4821`) and a 6-character code (`K7QM4Z`, no 0/O/1/I/L), and logs
  her in at once. The phone stays offline-first: it creates the account the
  first time it has a network, and sends the history then.
- **Everything syncs, except the cycle by default (option a).** Pregnancy,
  CPN contacts, pregnancy checks, baby movements, danger signs, her food
  groups, children, weighings, food logs, vaccines and feeds all go through
  `/sync/push/` and `/sync/pull/`. The cycle (`cycle`, `cycle_jour`) is
  refused unless she turns on `partage_cycle` (`PATCH /api/auth/me/`).
  Turning it off deletes her cycle rows from the server for good.
- **The health worker follows the woman.** An ASC or an agent of CSB finds a
  beneficiary in the list of their zone (`GET /api/beneficiaries/`, the ASC's
  region or the region of the agent's centre), or by the code she shows
  (`POST /api/beneficiaries/lookup/`, any region). Opening her file follows
  her (`suivi_beneficiaire`): from then on, their pulls carry her whole file.
  Recording a pregnancy or a child for her, or registering her (an ASC for a
  woman without a phone, cahier §3.2.A), also follows her. Each opening is
  logged (`consultation_dossier`). `POST /api/beneficiaries/{id}/unfollow/`
  stops it.
- **Narrower than before for the ASC.** An ASC no longer sees every pregnancy
  of their region: only those of the women they follow. The list shows names,
  phone and code only; health data needs the file to be opened.
- **Who writes what.** She writes all her own data. The ASC also writes the
  pregnancy and its follow-up, children, measurements, vaccines (as before
  for pregnancies and children). Nobody but her writes her cycle, her food
  groups, baby movements and feeds. The agent of CSB reads.
- **M1 fixed.** A mother creates her own children (`asc_id` empty, region
  from her account) and their measurements. A measurement without an ASC is
  a weighing at home: it is not counted as a screening in the statistics.
- **Tables aligned on the phone.** New synced tables: `cycle_jour`,
  `alimentation_femme`, `contact_soin`, `suivi_grossesse`, `mouvement_bebe`,
  `mouvement_evenement`, `vaccin_fait`, `tetee`. New columns as on the phone
  in `cycle`, `grossesse` (`ddr`/`dpa` now optional, at least one date is
  required), `danger_grossesse` (`code` of the config and `periode`; the type
  is found from the code), `enfant` (`poids_naissance_kg`) and
  `journal_alimentaire`.
- **PIN forgotten.** The ASC (women of their region) or the agent of CSB
  (women of their zone or followed) sets a new PIN with
  `POST /api/profiles/{id}/reset-pin/`, the woman being in front of them.
- **Erasure.** Also deletes the new tables. The follow-up rows stay, so the
  workers' phones receive the deletions; an erased file can't be opened.
