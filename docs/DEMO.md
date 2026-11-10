# TARANAKA – Demo data and the 8 scenarios

All data is **fictional** (people, centres, phone numbers). The clinical
configuration is the sample marked **"À VALIDER"**: never use it in production.

## Load

From `Backend_serveur/`, on an empty database:

```bash
python manage.py migrate
```

```bash
python manage.py charger_demo --tables-oms /path/to/who/tables
```

`--tables-oms` is optional. It imports `weianthro.txt`, `lenanthro.txt`,
`wflanthro.txt` and `wfhanthro.txt` from
https://github.com/WorldHealthOrganization/anthro (`data-raw/growthstandards`),
so the server computes the WHO z-scores itself. Without it, the phone's
z-scores are kept and the classification relies on MUAC and oedema.

Dates are relative to the day of loading. The command refuses to run twice.

The acceptance tests in `Backend_serveur/demo/tests.py` replay the server side
of the scenarios on this data:

```bash
python manage.py test demo
```

## Accounts

| Identifiant | Profile | PIN | Role in the demo |
|---|---|---|---|
| `admin.demo` | admin | 1111 | Second device in scenario 7 |
| `sup.analamanga` | superviseur (Analamanga) | 2222 | Scenario 8, MAS counter |
| `sup.national` | superviseur (national) | 2223 | All regions |
| `ac.rasoa` | asc (Analamanga) | 1234 | Scenarios 5, 7, 8 |
| `ac.hery` | asc (Analamanga) | 1235 | Background activity |
| `ac.antsirabe` | asc (Vakinankaratra) | 1236 | Second region |
| `inf.crenas` | agent_csb – CRENAS Ambohitsoa | 3333 | Scenario 8 nurse |
| `inf.creni` | agent_csb – CRENI | 3334 | |
| `inf.crenam` | agent_csb – CRENAM | 3335 | |
| `inf.csb` | agent_csb – CSB2 | 3336 | |
| `mere.voahangy` | beneficiaire, code `VHG444` | 4444 | Scenario 2 |
| `mere.lalao` | beneficiaire, code `RZM445` | 4445 | Scenario 3 |
| `mere.fara` | beneficiaire, code `FAR446` | 4446 | Scenario 4 |

Log in with `POST /api/auth/login/` `{"identifiant": "...", "pin": "..."}`, then
send `Authorization: Bearer <access>` and `X-Device-Id: <phone id>`.

The beneficiary code (D16) is what a mother shows her ASC: an ASC or a nurse
opens her file with `POST /api/beneficiaries/lookup/` `{"code": "VHG444"}`, and
then follows her (their next `/api/sync/pull/` carries her data).

## What is loaded

- 2 regions (Analamanga, Vakinankaratra), 5 centres: CSB2, CRENAM, CRENAS and
  CRENI in Analamanga, a CRENAS in Vakinankaratra.
- Pregnancy danger types from the sample config.
- Clinical config v1, published, "À VALIDER".
- Background activity in Analamanga over the last 25 days: 6 MAS children
  (one with a complication, sent to the CRENI), 3 MAM, 4 normal; 8 referrals at
  every step of the lifecycle (one cured, one defaulted); one referral to the
  CRENAM **not arrived** after 48 h and one **missed appointment** (both on
  `ac.rasoa`'s follow-up list); 2 children screened in Vakinankaratra.
- **The CRENAS queue holds no pending referral**, so scenario 5's referral comes
  first in it (scenario 8).

## Scenarios

| # | Scenario | Where it happens | Demo data / how to run |
|---|---|---|---|
| 1 | First launch in Malagasy, profile in < 60 s, offline | Phone only | At its first sync, the phone downloads the config (`GET /api/sync/pull/` → `config_clinique.mise_a_jour`, languages `mg`/`fr`). |
| 2 | 3 cycles → prediction "fiable", contraception warning | Phone computes; server stores synced cycles | `mere.voahangy` has 3 synced cycles of 28, 29 and 28 days. The config gives `cycle.cycles_pour_prediction_fiable = 3` and the warning text. |
| 3 | DDR at D-84 → 12 SA + 0 d, due date, next ANC; red alert on "saignement" in < 1 s offline | Phone computes and alerts | `mere.lalao`'s pregnancy has `ddr` = today − 84, `dpa` = ddr + 280. Next ANC contacts come from `calendrier_cpn`. The "Saignement vaginal" danger type exists; when synced it is stored (and referred if an ASC records it). |
| 4 | 9-month-old ate vary + anana + breast milk → 3/8 "insuffisante", advice to add an animal food | Phone computes; server re-counts | `mere.fara`'s child Kanto (9 months) has today's food log with groups 1, 2, 7: `score_diversite = 3`, `diversite_minimale_atteinte = false`. Advice `ajouter_aliment_animal` in the config. |
| 5 | ASC screens an 18-month-old, MUAC 112 mm → MAS, CRENAS, orange; offline code, "Non transmise" | Phone; server re-classifies at sync | Child **Soa** (18 months, `ac.rasoa`) has no measurement yet. Push the measurement and the referral (below): the server answers `mas`, `crenas`, `orange`. |
| 6 | 1–5 work in airplane mode and survive a reboot | Phone only | — |
| 7 | Back online → "Synchronisé"; forced resend → no duplicate; concurrent change → conflict on the web | Server | Resend the same push: every result has `rejoue: true`, no new row. Then `admin.demo` renames Soa with `PATCH /api/children/{id}/`, and `ac.rasoa` pushes another change with the old version: `conflit`, visible to `inf.crenas` in `GET /api/conflicts/`. |
| 8 | CRENAS nurse sees it first, clicks "Patient arrivé"; ASC sees "Reçu par le centre"; supervisor's MAS counter +1, no names | Server | `inf.crenas`: `GET /api/referrals/incoming/` (first line), `POST /api/referrals/{id}/status/` `{"status": "recu", "version": n}`. `ac.rasoa`: `GET /api/sync/pull/?tables=referencement` → `status: "recu"`. `sup.analamanga`: `GET /api/stats/` → `cas_mas` from 6 to 7. |

### Scenario 5 push (as `ac.rasoa`)

Replace `<soa-id>` (from `GET /api/children/?search=Soa`), the dates, and use
new UUIDs.

```json
{
  "operations": [
    {
      "cle_idempotence": "0b6f8f0e-0f43-4c55-9a51-6f3c1c6b8a01",
      "table": "mesure",
      "operation": "create",
      "id": "5a0c9d55-6c47-4a40-8b47-3a2f0c1d7e01",
      "donnees": {
        "enfant_id": "<soa-id>",
        "date_mesure": "2026-11-04",
        "poids_kg": "8.60",
        "taille_cm": "77.5",
        "position": "couche",
        "pb_mm": 112,
        "oedemes_bilateraux": "aucun",
        "alerte": "rouge"
      }
    },
    {
      "cle_idempotence": "0b6f8f0e-0f43-4c55-9a51-6f3c1c6b8a02",
      "table": "referencement",
      "operation": "create",
      "id": "5a0c9d55-6c47-4a40-8b47-3a2f0c1d7e02",
      "donnees": {
        "code_unique": "TRK-7F3K-92",
        "origine": "enfant",
        "enfant_id": "<soa-id>",
        "mesure_id": "5a0c9d55-6c47-4a40-8b47-3a2f0c1d7e01",
        "csb_id": 3,
        "priorite": "haute",
        "motif": "MAS – PB 112 mm",
        "date_referencement": "2026-11-04T07:30:00Z"
      }
    }
  ]
}
```

`csb_id` is the CRENAS id from `GET /api/facilities/?type_centre=crenas`.
