# Application audit report

**Scope:** static review of the Lucee/CFML application, route and role contracts, persistence patterns, upload/download handling, generated workbook workflows, shared navigation, and theme behavior.

**Limit:** this is an engineering audit, not an independent penetration test or a production infrastructure review. The automated HTTP suite could not be executed in the audit workspace because CommandBox is unavailable there; syntax and source-contract checks were run, and the authenticated suite is ready for the Windows field-test environment.

## Findings corrected in this branch

| Severity | Finding | Resolution |
| --- | --- | --- |
| High | Training sign-off files were served using a client-supplied MIME value. | The server now selects MIME from the allowed extension and applies a sandbox policy to inline files. |
| Medium | Training and Inventory pages did not consistently use the portal shell, so the left navigation and selected theme disappeared. | Authenticated HTML pages now use the shared shell and load the same persisted theme before CSS paints. |
| Medium | Training navigation appeared as an inconsistent top menu and exposed Reports to viewer-role users even though the route denied them. | Training navigation is now role-aware and nested under Training Tracker in the left sidebar. |
| Medium | Inventory quality issues were rendered with lifecycle-event headings, hiding the actual issue, severity, expected model, and explanation. | A purpose-built quality-results table now renders the correct fields. |
| Medium | Stored Training video links could use a non-web URI scheme when browser validation was bypassed. | Both route and service now permit only `http://` and `https://`; new-window links use `noopener noreferrer`. |
| Low | Early theme application was duplicated and occurred after content on mounted pages, allowing a flash or apparent reset. | Theme initialization is centralized in a small head-loaded script; toggles continue to share one local-storage key. |
| Low | Baseline browser response protections were absent. | The application now emits `nosniff`, frame denial, a same-origin referrer policy, and a restrictive browser permissions policy. |

## Open engineering findings

| Priority | Finding | Impact |
| --- | --- | --- |
| P0 | No CSRF tokens protect authenticated mutations. | A malicious site could cause a signed-in browser to submit unintended changes. |
| P0 | Fixed first-run administrator credentials, custom password hashing, and no login throttling/MFA. | Weak initial access and authentication controls are unsuitable for production exposure. |
| P0 | Upload protection is not uniform and lacks byte limits, signature inspection, quarantine, and malware scanning. | Malformed or hostile files could consume resources or reach downstream parsers. |
| P0 | Production session cookies are not yet marked `Secure`; mutable files reside under the application tree. | Deployment mistakes could weaken session or data isolation. |
| P1 | Generated-file authorization records only a module subsection, not user/job ownership. Filenames can also collide. | Another authorized user in the same module could retrieve or overwrite a guessed output name. |
| P1 | Training inserts recover IDs with `SELECT MAX(id)` and week numbers with `MAX + 1`. | Concurrent requests can associate follow-up work with the wrong record or allocate duplicate sequence values. |
| P1 | The H2 file database, empty database password, and ad hoc schema initialization do not provide production HA or controlled migrations. | Scaling, recovery, schema governance, and concurrent operation are constrained. |
| P1 | Several multi-step writes lack explicit transactions and uniqueness constraints. | Partial updates and duplicate authorization rows are possible during failures or concurrency. |
| P1 | Configuration JSON updates are locked but not atomic, versioned, or audited. | A failed write can damage operational reference data, with limited traceability and rollback. |
| P1 | Temporary uploads and some generated artifacts do not have a complete retention lifecycle. | Disk growth and retention-policy violations can accumulate over time. |
| P1 | Administrative user creation suppresses exceptions and provides no actionable validation feedback. | Operators may believe an action succeeded and cannot distinguish validation from infrastructure failures. |
| P2 | Malformed JSON is treated as an empty object by the shared request helper. | Invalid clients can receive misleading business-validation outcomes instead of a clear 400 parse error. |
| P2 | Inline scripts, styles, and event handlers prevent a strict site-wide Content Security Policy. | A major browser defense cannot yet be enabled without refactoring. |
| P2 | There is no native GitLab pipeline, browser visual-regression suite, formal accessibility suite, or representative load test. | Regressions and capacity limits are more likely to be discovered manually. |
| P2 | Error logging lacks structured context and user-visible correlation IDs. | Production diagnosis and incident reconstruction will be slow. |

Detailed remediation sequencing and acceptance evidence are in [`ENTERPRISE_READINESS.md`](ENTERPRISE_READINESS.md).
