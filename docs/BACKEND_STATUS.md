# TARANAKA – Backend status against the MVP spec

Compared on 4 Nov 2026: `docs/SPEC.md` (prompt v2) against the Django code in
`Backend_serveur/` (branch `Backend_Serveur`, commit `318aeb3`).

Stack kept as is: Django 6.1 + DRF + simplejwt + PostgreSQL 16, drf-spectacular
for the OpenAPI file. No new dependency was needed.

Legend: ✅ finished · 🟡 partial · ❌ missing · ⏭️ out of MVP scope (spec §14) or phone-only.

## 1. Gap analysis (state before this work)

### Accounts, authentication, RBAC (spec §2, §8)

| Item | State | Notes |
|---|---|---|
| Named accounts, PIN login, JWT access/refresh, rotation, logout | ✅ | `comptes/` |
| 5 wrong PINs → progressive delay, admin unblock | ✅ | 15 min / 1 h / admin |
| Agent PIN reset by supervisor | 🟡 | Only an admin can change a user; no "reset PIN" action |
| Profiles `beneficiaire`, `asc`, `agent_csb`, `admin` | ✅ | |
| **Supervisor** profile (district/region/programme) | ❌ | No profile, no scope |
| Per-action permissions | 🟡 | `AccesParAction` works, but several viewsets use `tuple(CodeProfile.values)`, so any new profile would silently get read access |
| Centre types CSB / CRENAS / CRENI / CRENAM | ❌ | `csb` table has no type: a MAM/MAS child has no typed destination |
| "Only an authorised professional records a discharge" | ❌ | No discharge at all |
| Two-factor authentication for web accounts | ❌ | Not in the requested scope; see "Still missing" |

### Audit log (spec §2)

| Item | State | Notes |
|---|---|---|
| `journal_audit` on create/update/delete/status change | ✅ | Field names only, no health values |
| Device recorded | 🟡 | Yes for row writes; not for logins |
| Audit of sync, conflict arbitration, config publication, CSV export | ❌ | These features did not exist |
| Read access to the log (admin) | 🟡 | Django admin only, no API |
| Log is append-only | 🟡 | Admin is read-only, but the model can still be updated/deleted in code |

### Synchronisation (spec §9)

| Item | State | Notes |
|---|---|---|
| UUID generated on the phone, `version`, soft delete, `updated_since` | ✅ | Per-row REST endpoints |
| Resent create with the same `id` returns the row (no duplicate) | ✅ | |
| **Outbox batch endpoint with idempotency key** | ❌ | No `/sync` |
| Deletions reach other phones | ❌ | Soft-deleted rows are hidden from every list (`endpoint.md` says "ce sera le rôle de /sync") |
| **Conflicts on clinical data kept, never overwritten, queued for the web** | ❌ | REST answers `409` with the server row; `historique_version` exists but is never written |
| Config updates downloaded during sync | ❌ | No config |
| Compressed batches | 🟡 | No gzip in or out |
| Statuses Enregistré / À synchroniser / Synchronisé / Conflit | ⏭️ | Phone-side; the server must answer per operation so the phone can set them |

### Malnutrition screening, referral and case lifecycle (spec §7, §10)

| Item | State | Notes |
|---|---|---|
| Child, measurement, server-side age and length correction | ✅ | |
| MUAC only from 6 to 59 months | ✅ | |
| WHO z-scores on the server | ❌ | `TODO (Z-score step)`; `reference_oms` is never filled |
| **MAS / MAM / normal / at-risk infant classification** | ❌ | The phone's `alerte` is stored as sent |
| Danger signs (IMCI), appetite test, medical complications on a measurement | ❌ | No fields |
| **Automatic orientation CRENI / CRENAS / CRENAM** | ❌ | |
| Referral with offline code, server code fallback | ✅ | Phone code accepted, `R-xxxx-MMDD-n` fallback |
| Referral from a pregnancy danger sign | ✅ | |
| **Lifecycle `Référé → Reçu → Pris en charge → En suivi → Sortie`** | 🟡 | Code has `envoye → recu → vu → pris_en_charge → clos`: conflicts with the spec (no `en suivi`, no exit outcome, `vu` not in spec) |
| Exit outcomes (cured, transferred, non-respondent, defaulted, died) | ❌ | |
| Arrival date (for "delay referral → arrival") | ❌ | Only `updated_at` |
| Incoming queue sorted by urgency then age | 🟡 | List exists, sorted by date only |
| Search by referral code | ❌ | No filter on `code_unique` |
| Follow-up appointments ("programmer un contrôle") | ❌ | No table |
| Missed appointments, referrals not arrived after 48 h | ❌ | |
| `consultation_nutritionnelle` endpoint | ❌ | Model only |
| `journal_alimentaire` endpoint | ❌ | Model only |

### Supervisor dashboard (spec §10)

| Item | State |
|---|---|
| Aggregated, anonymous stats by period and zone | ❌ |
| Small-count suppression (< 5) | ❌ |
| CSV export | ❌ |

### Clinical configuration (spec §11)

| Item | State | Notes |
|---|---|---|
| Versioned config, editable without a new app release | ❌ | Nothing; `type_danger_grossesse` is the only configurable list |
| Written validation before production | ❌ | |
| Source and version shown with advice | ❌ | |
| Sample config marked "À VALIDER" | ❌ | |

### Deliverables (spec §15)

| Item | State |
|---|---|
| Unit tests | 🟡 174 tests (accounts, CRUD, referrals); none on classification, sync or a permission matrix |
| API documentation | 🟡 `Backend_serveur/docs/endpoint.md` + live Swagger; no committed OpenAPI file |
| Database schema doc | ✅ `Backend_serveur/database/taranaka_tables_serveur.md` |
| Demo data for the 8 scenarios | ❌ |

### Out of scope for the backend

Phone-only (spec §3–§6, §8): onboarding, cycle predictions, pregnancy calendar
display, red alert screen, SQLCipher, inactivity lock, audio. The server only
stores what the phone syncs and serves the configuration these screens read.
§14: DHIS2/FHIR (prepared only), SMS, teleconsultation.

---

## 2. What was done

The decisions taken where the spec was ambiguous are in `docs/DECISIONS.md`
(D1–D11). The API is described in `Backend_serveur/docs/endpoint.md` and
`docs/openapi.yaml`; the schema in `Backend_serveur/database/taranaka_tables_serveur.md`;
the demo in `docs/DEMO.md`.

| Requested item | State now | Where |
|---|---|---|
| **RBAC** | ✅ 5 profiles (new `superviseur`), explicit per-action lists, supervisor zone, supervisor creates ASCs and resets their PIN, discharge reserved to the destination centre, full endpoint × profile matrix tested | `comptes/`, `comptes/tests_permissions.py` |
| **Audit log** | ✅ Append-only, device on every line (logins included), new actions (sync conflicts, arbitration, config, PIN reset, CSV export), admin API `GET /api/audit/` | `synchro/models.py`, `synchro/views.py` |
| **Idempotent outbox sync** | ✅ `POST /api/sync/push/` (ordered batch, idempotency key, one answer per operation, same rules as REST), `GET /api/sync/pull/` (deletions included, keyset cursor, config update), gzip both ways | `synchro/sync.py`, `synchro/registre.py` |
| **Conflict queue** | ✅ Clinical conflicts never overwrite: both versions in `conflit_sync` + `historique_version`; `/api/conflicts/` to list and arbitrate (server / phone / merge) | `synchro/sync.py` |
| **Referrals and case lifecycle** | ✅ `Référé → Reçu → Pris en charge → En suivi → Sortie`, exit outcomes, dates, child status follows, incoming queue by urgency then age, search by code, not-arrived-after-delay, appointments and missed ones, consultations, follow-up list | `referencement/`, `nutrition/` |
| **Aggregated supervisor stats** | ✅ `/api/stats/` + CSV export, by period, region or month, small counts (< 5) hidden, regional lock | `statistiques/` |
| **Versioned clinical config** | ✅ Draft / published / retired, written validation status, JSON schema, declarative rule engine (no threshold in code), ETag, sample marked "À VALIDER", load command | `config_clinique/` |
| Malnutrition classification | ✅ MAS / MAM / normal / at-risk infant and CRENI / CRENAS / CRENAM / CSB orientation, recomputed by the server from the published config | `nutrition/classification.py`, `config_clinique/regles.py` |
| WHO z-scores | ✅ LMS with WHO's restricted method, from `reference_oms`; `importer_tables_oms` loads WHO's official files | `nutrition/zscores.py` |
| Food log, consultations | ✅ The two existing tables now have an API | `nutrition/views.py` |
| Tests | ✅ 316 tests, all passing (see §4) | |
| OpenAPI | ✅ `docs/openapi.yaml`, no warnings, a test fails if it drifts from the code | |
| Demo data | ✅ `python manage.py charger_demo`, acceptance tests replaying the scenarios | `demo/`, `docs/DEMO.md` |

## 3. Changes to existing endpoints

Working endpoints were only changed where they conflicted with the spec.
Everything else is additive (new fields in responses, new endpoints).

| Endpoint | Change | Why |
|---|---|---|
| `POST /api/referrals/{id}/status/` | Statuses are now `envoye`, `recu`, `pris_en_charge`, `en_suivi`, `sortie` (were `envoye`, `recu`, `vu`, `pris_en_charge`, `clos`). `sortie` needs `issue_sortie`, is allowed from `recu` onwards, and only an `agent_csb` of the destination centre may record it (admin gets `403`). Existing rows migrated: `vu` → `recu`, `clos` → `sortie`. | **Conflict with spec §7** (lifecycle, exit outcomes, "seul un professionnel habilité"). D7. |
| `POST /api/referrals/{id}/status/` | The child's `statut_prise_en_charge` (and its `version`) now follows the referral. | Spec §7 "cycle de vie du dossier". The phone must re-read the child, as already documented for referral creation. |
| `/api/referrals/` | New fields: `urgence`, `date_referencement` (writable on create), `date_reception`, `date_prise_en_charge`, `date_sortie`, `issue_sortie`, `en_retard`. New filters `code`, `en_retard`, `type_centre`, `enfant`. | Spec §7, §10. Additive. |
| `/api/measurements/`, `/api/children/{id}/measurements/` | `waz`, `haz`, `whz` are computed by the server **when the WHO tables are loaded** (the phone's values are kept otherwise, as before). New input fields (`signes_danger`, `complications_medicales`, `appetit`, `difficultes_allaitement`) and server-computed fields (`classification`, `orientation_centre`, `urgence`, `date_prochain_controle`, `config_version`). `flag_aberrant` can be set by the server. | Was documented as "Pour l'instant… le serveur les recalculera à l'étape des Z-scores". D5, D6. |
| `/api/facilities/` | New field `type_centre` and filter. | CRENI/CRENAS/CRENAM destinations, spec §7. D2. |
| `/api/profiles/` | Supervisors can list and create ASC accounts of their zone; new `POST /api/profiles/{id}/reset-pin/`. | Spec §2, §8. D1. |
| All read endpoints | Read lists use an explicit `PROFILS_DOSSIERS` instead of "every known profile". No change for the 4 existing profiles; the new supervisor gets `403`. | Spec §10 (no individual data for supervisors). |
| `DELETE` on synced tables | Unchanged, but deletions now reach phones through `/api/sync/pull/` (the doc said "ce sera le rôle de /sync"). | Spec §9. |
| Login | Audit line also stores `device_id`. No API change. | Spec §2. D3. |
| Every response | May be gzip-compressed when the client sends `Accept-Encoding: gzip`. | Spec §9, §12 (< 100 KB/day). |

No existing endpoint was removed or renamed. One existing test was adapted to
the new lifecycle (`referencement/tests.py`, `StatusTest`), and one to the 5th
profile (`comptes/tests.py`, migration rollback test).

## 4. Test report

Run on PostgreSQL 16, Python 3.13, from `Backend_serveur/`:

```bash
python manage.py test
```

Result on 4 Nov 2026: **316 tests, OK** (174 before this work).

| App | Tests | Covers |
|---|---|---|
| `comptes` | 73 | Login, lockout, PIN, accounts, supervisor, audit log, **permission matrix** (19 reads × 5 profiles, 11 writes × 5 profiles, no token) |
| `nutrition` | 79 | Children, measurements, **classification** (WHO reference cases, MAS/MAM limits, orientation, under 6 months, config-driven thresholds, plausibility) |
| `referencement` | 61 | Referrals, lifecycle and discharge, queue order, appointments, consultations, food logs, follow-ups |
| `synchro` | 35 | **Sync**: forced resend, idempotency key, order, errors, rights, conflicts and arbitration, pull with deletions, cursor, gzip, OpenAPI file |
| `sante_femme` | 32 | Cycles, pregnancies, danger signs |
| `config_clinique` | 12 | Versions, schema, publication, validation in production, ETag, sample "À VALIDER" |
| `statistiques` | 12 | Counts, small-count masking, zones, months, CSV, scenario 8 counter |
| `demo` | 7 | Acceptance: scenarios 1–5, 7, 8 on the demo data through real PIN logins |
| `referentiel` | 5 | Reference lists |

Not covered here (outside the backend): real devices, offline behaviour on the
phone, field tests (spec §12).

## 5. Still missing or partial

| Item | State | Note |
|---|---|---|
| Two-factor authentication for web accounts (spec §2) | ❌ | Not in the requested scope. Recommended next step: TOTP for `agent_csb`, `superviseur`, `admin`. |
| Server-side check of the personal-data sync opt-in (spec §4, §9) | 🟡 | The server stores what the phone sends; the opt-in is the phone's job. There is a single `consentement` flag, not one per module. |
| Right of access / erasure (loi 2014-038) | ❌ | No self-service export or erasure endpoint; an admin can deactivate an account. |
| Vaccination records, ANC attendance, pregnancy follow-up (weight, movements, delivery) | ⏭️ | Personal-mode data with no server table; the calendars are in the config. Add tables if these must be synced. |
| Measurements recorded by the centre | 🟡 | Only ASCs/admins write measurements; centre agents record consultations. |
| Update pushed for a row deleted on the server | 🟡 | Answers `introuvable`, not put in the conflict queue (D10). |
| Complementary suppression in stats | 🟡 | A hidden group value can sometimes be deduced from the total (D11). |
| District level | ❌ | No district table: supervisors are regional or national (D1). |
| Malagasy texts in the config | ❌ | `"mg": null` in the sample: to be written and reviewed by native speakers. |
| Clinical validation of the config | ❌ | Everything is "À VALIDER" until the Ministry / ONN / medical committee signs it. |
| DHIS2 / FHIR export | ⏭️ | Post-MVP (spec §14). The stats service is the natural place for a DHIS2 aggregate export. |
| Anonymous usage analytics (spec §12) | ❌ | Not started. |
| Hosting, TLS, encrypted backups | ⏭️ | Deployment, not code. |
