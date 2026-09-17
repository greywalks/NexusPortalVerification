# USSI Nexus integration API (v1)

Groundwork for connecting Inventory Management and invoicing to external systems. All endpoints live under `/index.cfm/api/v1/` (the `/index.cfm` prefix is required under Apache), return JSON, and never use the browser session.

## Authentication

Create a key under **User Management → API Keys** (superadmin). The plaintext key (`nxk_<prefix>_<secret>`) is shown once; only a SHA-256 hash is stored. Send it on every request:

```
Authorization: Bearer nxk_...
```

(`X-Api-Key: nxk_...` is also accepted.) Keys carry scopes and can be revoked instantly. Every call is written to the audit log with the key's name as the actor.

| Scope | Grants |
| --- | --- |
| `inventory:read` | serial / MSO / model lookups, shipping history, quality audit, import history |
| `inventory:write` | `POST /inventory/events` |
| `invoices:read` | pricing configuration, dimension tables, generated-output listing and download |
| `config:read` | audit event export |

## Errors

Every error has the same shape and an HTTP status of 400 (invalid input), 401 (no/invalid key), 403 (missing scope), 404, 409 or 500:

```json
{"ok": false, "error": {"code": "invalid_body", "message": "kind must be one of ..."}, "correlation_id": "3f1c9a2b7e4d"}
```

The `correlation_id` matches the server log entry.

## Endpoints

| Method | Path | Scope | Notes |
| --- | --- | --- | --- |
| GET | `/health` | none | Liveness. |
| GET | `/inventory/imports?limit=100` | inventory:read | Import batches, newest first. |
| GET | `/inventory/serials/{serial}` | inventory:read | Lifecycle events, models and MSOs for one serial. |
| GET | `/inventory/mso/{mso}` | inventory:read | Serials and events for one MSO. |
| GET | `/inventory/models/{model}` | inventory:read | Events whose model contains the value. |
| GET | `/inventory/shipping?preset=custom&start=YYYY-MM-DD&end=YYYY-MM-DD&model=` | inventory:read | Same report as the Shipping page. |
| GET | `/inventory/quality/audit` | inventory:read | 409 until a Promethean reference is installed. |
| POST | `/inventory/events` | inventory:write | Ingest rows (below). |
| GET | `/invoices/prices` | invoices:read | AMC, Philips, TCL, Storage prices, Philips repair tiers, FedEx defaults. |
| GET | `/invoices/dimensions` | invoices:read | AMC and Philips model → square footage. |
| GET | `/invoices/outputs` | invoices:read | Generated files with module, timestamp and size. |
| GET | `/invoices/outputs/{filename}` | invoices:read | Downloads a generated workbook. |
| GET | `/audit/events?action=&actor=&start_date=&end_date=&limit=&offset=` | config:read | Audit events for SIEM pulls. |

### Ingesting inventory events

`POST /inventory/events` accepts rows in **the same column layout as the matching warehouse export**, so external databases can push what the CSV/XLSX importer would have read. Rows go through the same event fingerprinting, so re-sending is safe; an identical payload returns `duplicate_payload: true` and creates nothing.

```json
{
  "kind": "shipping",
  "source": "wms-nightly",
  "rows": [
    {"Ticket Number": "M12345678", "Shipped Date": "08-09-2026", "Model": "AP9-A75-NA-R",
     "Serial Number": "9A75XK001", "Tracking Number": "00987654321"}
  ]
}
```

`kind` is one of `receiving`, `shipping`, `inventory`, `repair`, `fedex`. Required columns per kind:

- **receiving**: Received Date, Model, Serial Number, RMA In Tracking
- **shipping**: Ticket Number, Shipped Date, Model, Serial Number, Tracking Number (Pickup Date optional)
- **inventory**: Transfer Detail ID, Model, Serial Number, Rack, Warehouse (Bin, Grade optional)
- **repair**: Timestamp, Actual Model, Actual Serial, Result
- **fedex**: MSO, Serial Number, Outbound Tracking, Request Date (return/delivery dates optional)

Response `201` with `{"result": {"batch_id": 12, "rows": 1, "events": 1, "duplicate_payload": false}}`. Maximum 5000 rows per request.

## Not yet provided (next steps when the database links are designed)

- Invoice generation over the API (today analysis and generation remain session-driven in the browser).
- Webhooks / change feeds; polling `/inventory/imports` and `/audit/events` is the current mechanism.
- Per-key rate limiting and IP allow-lists.
