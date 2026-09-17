# Enterprise readiness assessment

This assessment records the gaps between functional application parity and an enterprise production posture. It is a prioritized engineering backlog, not a certification or penetration-test report.

## Current baseline

The Lucee conversion implements the established invoice, NonConforming, Training Tracker, Inventory Management, authentication, authorization, and workbook workflows. Automated tests exercise the principal authenticated workflows. The application is suitable for controlled field testing on a trusted workstation.

Do not expose the current baseline directly to an untrusted network. Complete the Priority 0 controls first.

## Priority 0 — required before production exposure

| Control | Current gap | Recommended change | Acceptance evidence |
| --- | --- | --- | --- |
| Identity and bootstrap | A new database creates a fixed first-run administrator; there is no forced credential rotation, lockout, or MFA. | Disable fixed bootstrap credentials. Provision the first administrator from a secret or one-time setup flow, require a strong password, add throttling, and integrate enterprise SSO/MFA where available. | A clean deployment cannot be accessed with a documented default; repeated failures are throttled; privileged access requires MFA. |
| Password storage | Passwords use a custom iterated SHA-256 construction. | Migrate hashes to Argon2id or an approved adaptive password-hashing library. Rehash transparently after successful login and retire the legacy format after migration. | New passwords use the approved algorithm and parameters; migration and rollback tests pass. |
| CSRF protection | Authenticated mutations rely on cookies but do not validate anti-CSRF tokens. | Add framework-level CSRF tokens to every state-changing form and JSON request. Reject missing or invalid tokens and validate `Origin`/`Referer` as defense in depth. | Automated negative tests cover every mutating route. |
| Transport and sessions | The application permits non-TLS local HTTP and sets session cookies with `secure=false`. | Terminate TLS at an approved reverse proxy, set `Secure`, retain `HttpOnly` and `SameSite`, rotate session IDs at authentication and privilege changes, and define idle/absolute timeouts. | Browser inspection and automated tests verify cookie and TLS policy. |
| Upload security | Extension allowlists exist, but there are no uniform byte limits, file-signature checks, quarantine, or malware scanning. | Enforce request and per-file limits, verify magic bytes and workbook structure, randomize stored names, quarantine uploads, scan them, and store them outside the served application tree. | Oversize, renamed executable, malformed archive, and malware-test uploads are rejected safely. |
| Runtime isolation | Source, runtime data, uploads, and generated files share the application tree and depend on request filtering. | Run behind a hardened web tier, expose only intended routes/static assets, and move mutable data outside the web root with least-privilege service-account permissions. | Direct requests to every protected path fail at the outer web tier and application layer. |

## Priority 1 — reliability, governance, and scale

| Area | Recommended change |
| --- | --- |
| Database | Replace the file-based H2 production store with a managed relational database; introduce versioned migrations, tested backup/restore, encryption, connection pooling, and least-privilege credentials. |
| Concurrency and integrity | Replace `MAX(id)`/`MAX(week_number)+1` allocation with database-generated key retrieval and transaction-safe sequences; add unique constraints for permissions and business keys; wrap multi-step writes in transactions. |
| Output authorization | Record the generating user/job in output metadata, use collision-resistant object IDs, authorize each download against ownership plus role, and prevent cross-user overwrites. |
| Audit trail | Add an append-only audit event for authentication, permission changes, configuration changes, imports, overrides, invoice generation, downloads, and deletes. Include actor, timestamp, object, outcome, and correlation ID without recording secrets. |
| Observability | Emit structured logs with request/correlation IDs, sanitized exception details, health/readiness checks for dependencies, metrics, dashboards, and actionable alerts. |
| Data lifecycle | Define retention and purge policies for temporary uploads, signed sheets, exports, invoices, logs, and backups. Add legal/records review where required. |
| Delivery controls | Add native GitLab CI for CFML/static checks and authenticated workflow tests, plus dependency, secret, SAST, container, and license scanning. Produce an SBOM and require protected-branch review/approval. |
| Configuration | Move secrets and environment settings out of source, validate configuration at startup, use atomic/versioned reference-data updates, and support auditable rollback. |

## Priority 2 — application quality and maintainability

| Area | Recommended change |
| --- | --- |
| Browser security | Refactor inline scripts/styles and event handlers, then deploy a restrictive site-wide Content Security Policy. Retain `nosniff`, frame protection, referrer, and permissions policies already emitted by the application. |
| Validation and errors | Centralize request schemas, distinguish malformed JSON from an empty payload, validate URL schemes and field lengths server-side, return stable error codes, and display correlation IDs instead of internal details. |
| Accessibility and UX | Complete a WCAG 2.2 AA review, keyboard/focus testing, semantic labels, contrast checks in both themes, responsive browser tests, and visual-regression snapshots for every rendered page and role. |
| API and code structure | Separate routing, view templates, validation, and services; document/version API contracts; remove compatibility endpoints after a measured deprecation period. |
| Performance and capacity | Establish representative datasets and service-level objectives, then load-test imports, workbook generation, reports, session storage, and concurrent users. Move long-running jobs to a queue if needed. |
| Operations | Document deployment, rollback, incident response, disaster recovery, key rotation, access review, and quarterly restore exercises. Define RTO/RPO and ownership. |

## Recently added safeguards

- Shared portal shell and permission-aware left navigation for authenticated HTML pages.
- One persisted light/dark preference shared across portal, administration, Training Tracker, Inventory Management, and sign-in.
- Baseline `nosniff`, frame, referrer, and browser permissions response headers.
- Server-selected MIME types and a sandbox policy for inline Training Tracker sign-off files.
- Server-side `http`/`https` validation and safe new-window behavior for Training Tracker video links.
- Regression assertions for shared navigation, role-aware Training links, theme initialization, and sign-off MIME handling.

## Verification approach

Use OWASP ASVS as the application-security acceptance framework and map each applicable control to test evidence. Use the OWASP cheat sheets for password storage, CSRF, uploads, sessions, and logging. Align identity policy with the organization’s current NIST SP 800-63 guidance and internal security standards.

Functional parity tests remain necessary, but they do not replace threat modeling, dependency review, secure configuration review, accessibility testing, load testing, disaster-recovery exercises, or an independent penetration test.
