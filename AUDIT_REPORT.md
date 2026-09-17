# Application audit report

**Scope:** release-readiness review of the USSI Nexus Lucee/CFML application: `Application.cfc`, `index.cfm`, `routes/`, `services/`, the browser scripts and portal shell, reference-data JSON, deployment configuration, CI workflows and the Python parity suite. Generated assets (`static/css/tailwind.css`), images and the upstream Jinja templates under `migration/` were not reviewed line by line.

**Limits:** the audit workspace has no Lucee, CommandBox or H2 runtime. Every CFML change below is **statically reviewed only** (bracket/string balance checked by script, logic reviewed by hand) and must be exercised by the CI smoke test and `tests/http_parity.py` before merge. The browser changes **were runtime-tested** with the jsdom suite in `tests/frontend/`. This is an engineering audit, not a penetration test.

**Release readiness:** not ready for untrusted-network exposure until the CFML changes have passed the CI smoke test and parity suite on a real Lucee runtime and the remaining Priority 0 items (below) are closed. The application is suitable for continued controlled field testing.

## Findings corrected in this branch

IDs prefixed `S` are server side (statically reviewed); `F` are browser side (runtime-tested).

| ID | Severity | Finding | Resolution | Verification |
| --- | --- | --- | --- | --- |
| S-01 | High | State-changing config endpoints (`/set_storage_prices`, `/set_amc_prices`, `/set_philips_repair_cost`, `/set_fedex_shipment_defaults`, `/config/serial_rules` save) accepted any HTTP method with no CSRF protection. A plain link click by a signed-in Config user replaced the FedEx defaults with `{}` and deleted every Philips repair-cost tier, after which all Philips repairs billed at $0. | Mutating config routes require POST (405 otherwise). `Application.cfc` rejects POST/PUT/PATCH/DELETE whose `Origin` (or `Referer`) host differs from the request host (403). `/logout` is POST-only. | Parity suite asserts 405/403; static review. |
| S-02 | High | Reference data was written verbatim from JSON bodies: unknown keys, strings, negative prices and empty tier lists were persisted and later used in invoice arithmetic. Malformed JSON was treated as `{}`. | `ConfigService` validates every save (known keys, numeric ≥ 0, tier ranges, serial-rule shape, FedEx field set) and throws `Logicore.Validation`; routes return 400 with the message. Config JSON is written via a temp file and moved, so an interrupted write cannot truncate the file. `bodyJson()` returns 400 on invalid JSON. | Parity suite asserts rejected writes leave data unchanged; static review. |
| S-03 | High | On a production deployment with an empty database and no `USSI_NEXUS_BOOTSTRAP_PASSWORD`, the first administrator was created with a hard-coded default password hash. | `AuthService.init()` refuses to start in production when the database is empty and no bootstrap password is configured; the legacy `admin/admin` upgrade path is disabled in production. | Static review. `USSI_NEXUS_BOOTSTRAP_PASSWORD` is now mandatory for first production start (see deployment doc). |
| S-04 | High | Passwords used a custom iterated SHA-256 construction. | New and changed passwords use PBKDF2-HMAC-SHA256 (600,000 iterations, 16-byte random salt, `v3$` prefix). Existing v1/v2 hashes still verify and are rehashed transparently on the next successful login. | Static review only. **Verify on Lucee that `generatePBKDFKey("PBKDF2WithHmacSHA256", …)` is available before merge**; a failure here would block all logins. |
| S-05 | Medium | Every application start forced `is_superadmin=1` on the hard-coded username `matt.shaw`, regardless of configuration, so any later account created with that name became a superadmin at the next restart. | The elevation now targets the configured bootstrap username (`USSI_NEXUS_BOOTSTRAP_USERNAME`, default `matt.shaw`). Behaviour is unchanged for the documented production configuration. | Static review. |
| S-06 | Medium | `buildStorage()` summed `Price` values from client-supplied "included unmatched" rows, so a modified request could add arbitrary amounts to the invoice. | Included rows are now resolved by index or serial against the server-side analysis and priced from configuration; unknown rows are rejected. | Static review; existing clients send an empty list so behaviour is unchanged for them. |
| S-07 | Medium | With `USSI_NEXUS_RUNTIME_ROOT` set, `LuceeTrainingService` and `InventoryService` wrote reports and stored sign-off scans under the code checkout while the routes read from the runtime root, so those downloads failed. | `Application.cfc` passes the runtime root to both services. | Static review. |
| S-08 | Medium | No login throttling. | Ten failed attempts for the same username/IP within 15 minutes return 429 until the window passes. In-memory, per instance. | Static review. |
| S-09 | Medium | Administrative user creation swallowed exceptions; the admin saw nothing when a username was taken or invalid. Admin-set passwords only needed 4 characters while self-service required 12; the confirmation comparison was case-insensitive. | `createUser` validates username/password/initials and throws; the route logs and redirects with an `error`/`notice` shown on the admin page. One 12-character password policy everywhere; confirmation uses a case-sensitive compare. | Parity suite; static review. |
| S-10 | Medium | Training inserts recovered IDs with `SELECT MAX(id)`; week numbers used `MAX+1` without serialization. | Inserts use the driver-reported generated key (fallback to `MAX(id)` only if unavailable); week-number allocation runs under an exclusive named lock (single-instance deployment). | Static review. |
| S-11 | Medium | Uploaded invoice source workbooks were never deleted. | Files under `uploads/` older than 72 hours are removed at application start (sign-off scans are stored elsewhere and untouched). | Static review. |
| S-12 | Low | Inventory CSV exports did not neutralize leading `=`, `+`, `-`, `@` (formula injection when opened in a spreadsheet). | `csvLine()` prefixes such values with `'`. | Static review. |
| S-13 | Low | `ExcelService` leaked the `FileInputStream` when POI could not open an upload; NonConforming exports used a second-resolution filename that could collide across users; deleting a missing Training video returned 500; unexpected API errors leaked internal messages and had no correlation ID. | Stream closed on open failure with a clear message; export names carry a random suffix; missing video returns 404; `onError` and API failures log with a correlation ID and show it to the user. | Static review. |
| S-14 | Low | Deployment deny rules missed `views/`, `.github/`, `.htaccess`, `.gitignore` and the routed `/index.cfm/tests/…` path; `check-deployment` did not test them; `prepare-linux.sh` could run against an incomplete checkout; `import-source-assets.yml` pushed an unpinned upstream branch with write permissions on any push to itself. | Rules and checks extended in `.htaccess`, the vhost example, `server.json` and both check scripts; `prepare-linux.sh` verifies `config/` and `views/portal.html`; the import workflow is manual-only with a required source SHA. | Shell syntax checked; JSON/YAML parsed. |
| S-15 | Low | `tests/http_parity.py` replaces the AMC/Philips dimension tables and leaves inventory events behind, yet the previous report suggested running it in the field-test environment. | The suite refuses to run unless `USSI_NEXUS_TEST_DISPOSABLE=1`, and snapshots/restores the dimension tables on exit. CI sets the variable. | Guard verified locally (exits before any request). |
| F-01 | High | `EventSource` progress streams and two NonConforming navigations bypassed the `/index.cfm` route prefix, so invoice generation and label/export downloads failed under the documented Apache deployment. | `theme-init.js` routes `EventSource`; `nonconforming.js` uses the shared route helper. | jsdom suite. |
| F-02 | High | Workbook values (models, serials, FedEx tracking/reasons, TCL models, Workshop issue rows) were inserted into `innerHTML` unescaped. | All dynamic review markup is escaped. | jsdom suite with injected markup. |
| F-03 | High | Saving Philips repair-cost tiers reset every tier's `box_build` to 0. | Stored value is preserved through the editor. | jsdom suite. |
| F-04 | High | Blank or mistyped prices were saved as $0.00; negative prices and square footage were accepted. | The page refuses to save and names the bad fields; server validation added in S-02. | jsdom suite. |
| F-05 | Medium | "Generate Another" in the legacy Workshop form re-submitted the form, generating the invoice twice. | `type="button"`. | jsdom suite. |
| F-06 | Medium | Default dates were computed in UTC (wrong day in US evenings). | Local calendar day. | jsdom suite in four time zones. |
| F-07 | Medium | Expired sessions (HTML instead of JSON) and dropped streams left buttons disabled; Config load failure threw. | Shared `readJson`/`requestJson` helpers; every flow re-enables controls and reports the failure. | jsdom suite. |
| F-08 | Medium | Client navigation threw when the server removed Config for a limited user; the default page could reveal an ungranted client. | Null-safe navigation; default page chosen from permitted entries only. | jsdom suite. |
| F-09 | Medium | A missing Promethean form aborted script initialization for every later module. | Optional-chained bindings. | jsdom suite. |
| F-10 | Medium | A failed NonConforming delete closed the record as if deleted; slow searches could overwrite newer results. | Delete checks the response; requests are sequence-guarded. | jsdom suite. |
| F-14–16 | Low | Legacy tab styling, serial-rule `year_pos` 0 saved as 5, unencoded download filenames. | Fixed. | jsdom suite. |

## Open findings

| Priority | Finding | Impact / next step |
| --- | --- | --- |
| P0 | All CFML changes in this branch are not runtime-verified. | Run the CI smoke test and `tests/http_parity.py` on a Lucee runtime before merge; confirm `generatePBKDFKey` support (S-04) and the login flow first. |
| P0 | CSRF protection is Origin/Referer based plus `SameSite=Lax`; there are no synchronizer tokens. | Adequate for modern browsers; add per-session tokens to forms and `fetch` calls for defence in depth. |
| P0 | Upload handling still lacks byte limits below Apache's 100 MB, magic-byte checks and malware scanning. Uploads reside under the application tree unless `USSI_NEXUS_RUNTIME_ROOT` is set. | Unchanged from the previous assessment. |
| P1 | Analysis state (`session.amc`, `session.workshop`, …) is per session, so two browser tabs running the same module interfere with each other. | Key state by a per-analysis token returned to the client. |
| P1 | Generated-file authorization records only a module subsection; user-chosen output names can collide and overwrite another user's file in the same module. | Record owner and use collision-resistant names. |
| P1 | H2 file database, empty database password, ad hoc schema initialization, no migrations. | Unchanged. |
| P1 | No audit trail for configuration changes, permission changes or invoice generation. | Unchanged. |
| P2 | Philips unit prices (1910, 3.50, 6) and TCL pallet/box rates are hard-coded while AMC/Storage prices are configurable. | Parity with the Python source is preserved; decide whether they should be configurable. |
| P2 | Workshop corrections accept any value for "Derive Size"/"Category"; an unrecognized value silently drops the row from billing instead of listing it as excluded. | Validate against the suggested values and report dropped rows. |
| P2 | `serial_rules.json` is editable at runtime but tracked in git; the two `Sample_Promethean_*` workbooks contain production-like rows. | Move runtime edits to an override file; scrub or remove the samples. |
| P2 | Inline scripts/styles prevent a strict CSP; no structured logging beyond the new correlation ID. | Unchanged. |

## Known source inconsistency preserved

The Philips `_split_base_credit()` 250/250 split is intentionally preserved (see `MIGRATION_PARITY.md`).

Detailed verification steps are in [`QA_CHECKLIST.md`](QA_CHECKLIST.md); remediation sequencing remains in [`ENTERPRISE_READINESS.md`](ENTERPRISE_READINESS.md).
