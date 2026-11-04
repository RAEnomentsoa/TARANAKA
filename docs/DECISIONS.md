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
