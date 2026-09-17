# QA checklist

Status key: **reviewed** (read and assessed), **changed** (modified in this branch), **verified** (runtime-tested here), **static** (changed but only statically reviewed; needs a Lucee run), **blocked**, **not reviewed**.

## Coverage by subsystem

| Area | Files | Status | Notes |
| --- | --- | --- | --- |
| Application bootstrap, headers, error handling | `Application.cfc` | changed / CI | Origin check, correlation IDs, upload cleanup; runtime-root fix is static (QA step 7). |
| Routing, auth helpers, config API, invoice API, NonConforming API, downloads | `index.cfm` | changed / CI | POST-only config, validation errors, throttle, admin feedback. |
| Authentication and permissions | `services/AuthService.cfc`, `LuceeAuthService.cfc` | changed / CI | PBKDF2 hashing, bootstrap guard, username/password policy. |
| Reference data | `services/ConfigService.cfc`, `config/*.json` | changed / CI | Validation, atomic writes. JSON defaults checked for duplicates/negatives (none). |
| Invoice math (AMC, Philips, TCL, FedEx, Storage, Workshop) | `services/InvoiceService.cfc`, `InvoiceWorkbookService.cfc`, `PhilipsReportService.cfc`, `template/layouts/*.xlsx` | reviewed; billing fixtures and parity suite pass in CI; Storage non-empty include path static | Rounding is HALF_EVEN and `Math.rint`, matching Python `round()`. Fixture workbooks have no external links or `#REF!`. |
| Excel I/O | `services/ExcelService.cfc` | changed / static | Stream leak on unreadable upload. |
| NonConforming | `services/NonConformingService.cfc`, `LuceeNonConformingService.cfc` | changed / CI | Export filename suffix. Number generation already serializable. |
| Training Tracker | `routes/TrainingRoutes.cfm`, `services/LuceeTrainingService.cfc`, `TrainingImportService.cfc`, `TrainingPdfService.cfc` | changed / CI | Generated keys, week-number lock, video 404. Output encoding reviewed: consistent. |
| Inventory Management | `routes/InventoryRoutes.cfm`, `services/InventoryService.cfc` | changed / CI (runtime-root fix static) | CSV injection guard, runtime-root fix. Output encoding reviewed: consistent. |
| Browser scripts and portal shell | `static/js/*.js`, `views/portal.html` | changed / **verified** | `tests/frontend/portal_regression.test.js`, 29/29 in four time zones. |
| Deployment and web tier | `.htaccess`, `server.json`, `deploy/*` | changed / static | Shell syntax and JSON parsed. |
| CI | `.github/workflows/*.yml` | changed / static | YAML parsed. Frontend job added. |
| Parity suite | `tests/http_parity.py`, `tests/billing_parity.cfm` | changed / CI | Disposable guard, dimension restore, new server assertions; passes end to end. |
| Generated CSS, images, upstream Jinja templates | `static/css/tailwind.css`, `static/*.png`, `migration/` | not reviewed | Build outputs and reference copies. |
| Python build helpers | `migration/*.py` | reviewed | Build-time only. |

## Runtime verification

Steps 1–5 below were completed by GitHub Actions run `35183539818` (Lucee 7.1.0.204) on commit `aeb1020`. Steps 6–10 still require a human on a real deployment.


1. `box server start` with `USSI_NEXUS_BOOTSTRAP_PASSWORD` set; confirm `/index.cfm/healthz` returns `ok:true` (exercises `AuthService.init` and the PBKDF2 path when the database is new).
2. Sign in as the bootstrap user; sign out via the Log out button; sign in again (second login rehashes a v2 hash to v3 — check the `users.password_hash` value now starts with `v3$`).
3. Change your own password from **My Account** with a 12+ character value; sign out and back in.
4. As superadmin, create a user with a short password: the admin page must show the validation message. Create a valid user and confirm the notice.
5. Run `USSI_NEXUS_TEST_DISPOSABLE=1 python tests/http_parity.py` against the disposable instance. It must end with the new `PASS: POST-only reference data…` line.
6. Start once with `USSI_NEXUS_ENV=production` and an **empty** database and no bootstrap password: startup must fail with the `Logicore.Bootstrap` message. Then set the password and start again.
7. Set `USSI_NEXUS_RUNTIME_ROOT` to a separate directory, upload a Training sign-off and download the Training attendance matrix and an Inventory shipping XLSX (regression for S-07).
8. In a browser: open Config, save prices, clear one price and save (must refuse), open the Philips repair-cost editor and save (check `config/philips_reference.json` still has `box_build` values).
9. Generate one invoice per builder end to end under the Apache deployment (progress stream must complete; regression for F-01).
10. From a page on another origin, submit a POST to `/index.cfm/set_amc_prices`: the response must be 403.

## Manual checks for the feature groundwork

- **SSO:** on a non-production host with a test app registration, complete a Microsoft sign-in for (a) a user whose email is set on their account (expect `auth.sso_linked` then `auth.login method:sso`), (b) an unknown user with auto-provision off (expect the refusal page and `auth.sso_unlinked`), (c) an expired/reused callback URL (expect "could not be verified").
- **API:** create a key with only `inventory:read`; confirm `POST /api/v1/inventory/events` returns 403; revoke and confirm 401. Point a real WMS extract at the ingest endpoint with a handful of rows and compare the serial pages with the CSV import of the same rows.
- **Audit log:** filter by your own username and confirm the last hour of actions is complete; export CSV and open it in Excel (values starting with `=` must appear as text).
- **Pricing:** change a Philips rate, generate a Philips invoice, open the workbook and confirm the *Breakdown* unit-price cells and the total both reflect the new rate; reset to defaults.

- **Home hub:** as a Home Page Editor, fill in a few real addresses from the old intranet, add a bulletin with bold text and a link that opens in a new tab, move a section between columns, and confirm a user without the permission sees the page but not the *Edit home page* button. Images in bulletins are not supported yet (paste is plain-text only).

## Manual browser checks (not automated)

- Keyboard: tab through the review tables; dynamically rendered inputs now carry `aria-label`s.
- Mobile width: sidebar opens and closes; review tables scroll horizontally.
- Light/dark theme persists across portal, Training and Inventory pages.
- Two browser tabs running the same builder still share session state (open P1).

## Frontend suite

```bash
npm install jsdom@24
TZ=America/New_York node tests/frontend/portal_regression.test.js
TZ=Pacific/Auckland node tests/frontend/portal_regression.test.js
```

The suite loads `views/portal.html` with the real `static/js` files, mocks every server response, and covers both the fixed defects and the unchanged happy paths (AMC, Workshop, TCL, pricing, repair-cost editing, NonConforming delete).
