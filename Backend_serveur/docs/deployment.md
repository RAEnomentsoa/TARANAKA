# TARANAKA – Deploying the server

How to run the Django API in production. Development and the demo are in
`docs/DEMO.md` at the root of the repository.

## 1. Environment

Copy `Backend_serveur/.env.production.example` to `Backend_serveur/.env` and
fill it in. The settings that matter for safety:

| Variable | Production value | Why |
|---|---|---|
| `DEBUG` | `False` | Never show stack traces. Swagger (`/api/docs/`) is then only open to staff logged in to `/admin/`. |
| `SECRET_KEY` | Long random string, kept secret | Signs the tokens. |
| `ALLOWED_HOSTS` | The API's public host name | Refuses other `Host` headers. |
| `CONFIG_VALIDEE_OBLIGATOIRE` | `True` | Spec §11: a clinical config must be validated in writing before it can be published. The sample marked "À VALIDER" can't go live. |
| `TOTP_OBLIGATOIRE` | `True` | Spec §2: `agent_csb`, `superviseur` and `admin` must use two-factor login. Without it set up, their token only opens `/api/auth/me/`, `/api/auth/changer-pin/` and `/api/auth/2fa/…`. The API enforces it, not only the dashboard. |
| `USE_X_FORWARDED_HOST` | `True` behind a reverse proxy | Links such as the pagination `next` use the public host sent by the proxy (`X-Forwarded-Host`), not `127.0.0.1:8000`. Only set it when a proxy you control sets that header. |
| `CORS_ALLOWED_ORIGINS` | Empty, or the dashboard's origin | See §3. |

`TOTP_OBLIGATOIRE` and `CONFIG_VALIDEE_OBLIGATOIRE` default to `False` so that
development, tests and the demo keep working.

## 2. First start

From `Backend_serveur/`:

```bash
pip install -r requirements.txt
```

```bash
python manage.py migrate
```

```bash
python manage.py importer_tables_oms /path/to/who/tables
```

```bash
python manage.py createsuperuser
```

The WHO tables are `weianthro.txt`, `lenanthro.txt`, `wflanthro.txt` and
`wfhanthro.txt` from https://github.com/WorldHealthOrganization/anthro
(`data-raw/growthstandards`). They are not in the repository (GPL-3). Without
them, the server keeps the phone's z-scores and `/api/who-reference/` answers
`404`.

Load a clinical config validated by the health authorities as a draft, fill in
its validation fields, then publish it (see `endpoint.md`, "Configuration
clinique"). Don't load `charger_demo` on a production database.

## 3. Reverse proxy, HTTPS and the web dashboard

Run the API with a WSGI server (for example gunicorn) behind nginx or another
reverse proxy that terminates TLS (TLS 1.2 or later, spec §9).

**Recommended: one domain.** Serve the web dashboard (`web/`, built with
`npm run build`) and the API from the same domain, for example
`https://taranaka.example/` for the dashboard and `https://taranaka.example/api/`
proxied to Django. No cross-origin request is made, so leave
`CORS_ALLOWED_ORIGINS` empty.

**Two domains.** If the dashboard has its own domain, list its exact origin:
`CORS_ALLOWED_ORIGINS=https://tableau.taranaka.example`. The API then allows
that origin only, with the headers the apps send (`Authorization`,
`Content-Type`, `X-Device-Id`, `Content-Encoding`) and exposes
`Content-Disposition` (CSV file name) and `ETag` (clinical config). Never use a
wildcard: the API carries health data.

The proxy must forward the public host (`proxy_set_header X-Forwarded-Host $host;`
in nginx) for `USE_X_FORWARDED_HOST` to work.

## 4. Data protection

- Encrypted backups of PostgreSQL. The database holds health data and the TOTP
  secrets of web accounts (stored in clear: protect the database and its
  backups).
- The audit log (`journal_audit`) is append-only and kept for traceability.
- Requests under loi 2014-038 (access, erasure) go through the endpoints in
  `endpoint.md`, "Données personnelles". The CMIL declaration and the retention
  policy are documents to write; they are not in the code.

## 5. Checks before going live

```bash
python manage.py check --deploy
```

```bash
python manage.py test
```
