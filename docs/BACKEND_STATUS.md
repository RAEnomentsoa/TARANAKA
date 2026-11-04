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

See the **Changes** section below for every change to an existing endpoint.
The decisions taken where the spec was ambiguous are in `docs/DECISIONS.md`.

_(Filled in as the work lands; see the end of this file.)_
