# USSI Nexus Lucee — Parity Validation

This document tracks runtime parity between the original `greywalks/Logicore-Portal` application and its USSI Nexus Lucee/CFML successor.

## Runtime gate

- [x] Lucee 7 boots cleanly on a fresh GitHub Actions runner.
- [x] `/healthz` succeeds.
- [x] `/login` renders and the default first-run administrator can authenticate.
- [x] Authenticated portal shell renders.

## Portal and permissions

- [x] Portal users and per-module permissions are persisted in H2.
- [x] Invoice Generator child permissions are represented independently.
- [x] Training Tracker roles are represented as admin/editor/viewer.
- [x] Legacy `tbd2` permission remains compatible and is relabeled Inventory Management.
- [x] Generated output ownership is persisted rather than process-local.

## Invoice Generator

- [x] Promethean Workshop analysis/build routes are present.
- [x] Promethean Storage analysis/build routes are present.
- [x] Promethean FedEx Shipment routes are present.
- [x] AMC routes are present.
- [x] TCL routes are present.
- [x] Philips routes are present, including raw-data Month End Report generation.
- [x] Config/reference-data routes are present.
- [x] Authenticated endpoint smoke tests pass under Lucee.
- [x] Billing fixtures are checked against current Python-main behavior.

## SMS NonConforming

- [x] CRUD/search persistence.
- [x] Number generation.
- [x] XLSX export through Apache POI.
- [x] Zebra ZPL label output.
- [x] Source-compatible `next_number`, PATCH, pagination, and 404 behavior.
- [x] Authenticated endpoint smoke tests pass under Lucee.

## Training Tracker

- [x] Weeks/topics/videos/sessions/roster.
- [x] Attendance and digital signature persistence.
- [x] Physical sign-off PDF template.
- [x] Signed-sheet upload/view/remove.
- [x] Attendance-matrix XLSX report.
- [x] Signed-sheet ZIP report.
- [x] Editable content and appearance settings.
- [x] Flask-compatible route aliases.
- [x] Authenticated endpoint smoke tests pass under Lucee.

## Inventory Management

- [x] Mounted at `/inventory-management/` using the legacy `tbd2` permission key.
- [x] Receiving/Shipping/Inventory/Repair/FedEx imports.
- [x] File SHA-256 and event fingerprint deduplication.
- [x] Serial/MSO/model lifecycle views.
- [x] Shipping reports and CSV/XLSX export.
- [x] Promethean reference/serial decoding and AP9-B `-02` rule.
- [x] Quality audit, serial overrides, and global whitelist.
- [x] Quality CSV/XLSX exports.
- [x] Authenticated endpoint smoke tests pass under Lucee.

## Output parity

- [x] AMC, Philips, TCL, Workshop, Storage, and FedEx workbooks preserve source sheet names, headers, live formulas, metadata cells, and identifier types.
- [x] Workshop raw and legacy paths apply current history/shipping deduplication and current-source price tiers.
- [x] Workshop corrected-production and updated-master companion workbooks preserve unrelated source sheets.
- [x] The full authenticated test covers invoice correction/confirmation, downloads, NonConforming CRUD/export/labels, Training reports/sign-offs, Inventory imports/dedup/lifecycle, and restricted users.

## Validation notes

Runtime validation is being performed from a clean Lucee 7 GitHub Actions runner. Compatibility issues discovered by the gate are fixed in the application code rather than bypassed in CI. CFML string literals, URL-fragment hashes, and request-level scopes have been normalized for Lucee 7, CommandBox SES routing uses `cgi.path_info`, and one-time migration workflows are removed after their patches land.

## Known source inconsistency to preserve during parity testing

The current Python `main` implementation of Philips `_split_base_credit()` applies the included 500 sq ft as a 250/250 Demo/Service split by default, even though older comments and a previously discussed billing expectation describe a different allocation. The Lucee port intentionally follows the executable current-source behavior until the billing rule is explicitly changed in both implementations.
