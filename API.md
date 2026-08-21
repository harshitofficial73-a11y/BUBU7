# BUBU.Market — backend contract

Frontend is complete and reads all screen data from one place. To connect a backend,
replace the seed constants in the logic class with `fetch` calls returning the shapes below.
Nothing else in the UI needs to change: every screen renders from these objects.

Base URL: `/api/v1`. All money is integer UGX (no decimals). All dates ISO 8601.
Auth: `Authorization: Bearer <jwt>`; the JWT carries `accountId` and `role`.

---

## 1. Where the frontend reads data today

| Frontend constant | Screens it feeds | Replace with |
|---|---|---|
| `ACCOUNTS` | sign-in, profile, storefront, settings, documents, invoices | `GET /accounts/me`, `GET /accounts` (admin) |
| `PRODUCTS` | marketplace search, product page, buyer basket | `GET /products` |
| `OFFERS` | supplier quotes per product | `GET /products/:id/offers` |
| `INDUSTRY[acct]` | supplier dashboard, buy leads, catalog views, contacts | `GET /suppliers/me/dashboard`, `GET /leads`, `GET /analytics/catalog` |
| `IND_CONTACTS(state)` | lead manager, chat threads | `GET /conversations` |
| `APPLICANTS` | admin verification queue | `GET /admin/applications` |
| `DISTRICTS`, `kmBetween` | lead radius filtering | keep client-side, or `GET /geo/districts` |
| `MODALS` | dialog field definitions | keep client-side (presentation only) |

---

## 2. Core resources

### Account
```json
{
  "id": "acc_01",
  "role": "supplier",              // buyer | supplier | admin
  "bizType": "Manufacturer",       // Trader | Manufacturer
  "tier": "Industry leader",       // Star supplier | Industry leader | null
  "company": "Nile Grain and Produce Limited",
  "tradeName": "Nile Grain",
  "initials": "NG",
  "person": "Denis Okot",
  "roleTitle": "General manager",
  "phone": "+256774552013",
  "email": "denis@nilegrain.co.ug",
  "address": "Plot 9, Aputi Road, Lira Industrial Area",
  "district": "Lira",
  "categories": ["Agriculture & produce", "Packaging"],
  "registration": {
    "ursb": "80020004417755",
    "tin": "1003882140",
    "tradingLicence": "LMC/TL/2026/00921",
    "vatRegistered": false,
    "nin": "CF88031277KJ4A",
    "incorporatedOn": "2018-01-22",
    "verificationStatus": "verified"   // unverified | pending | verified | rejected
  },
  "profile": { "about": "...", "coverage": "...", "nature": "...", "staff": "...", "turnover": "...", "brands": "..." }
}
```

### Product / listing
```json
{
  "id": "p3",
  "supplierId": "acc_03",
  "name": "White maize grain, grade 1",
  "category": "Agriculture & produce",
  "family": "Grain and pulses",
  "price": 1450,
  "unit": "kg",
  "moq": 1000,
  "photos": ["/media/a-maize-grain.png"],
  "specs": [{ "key": "Moisture", "value": "13.5%" }],
  "description": "...",
  "rating": 4.6,
  "orderCount": 214,
  "status": "published"            // draft | published | archived
}
```

### Offer (a supplier's quote against a product)
```json
{ "supplierId": "acc_03", "supplierName": "...", "district": "Lira",
  "price": 1390, "moq": "5,000 kg", "phone": "+256758441260",
  "verified": true, "yearsOnPlatform": 5 }
```
Phone numbers must be masked server-side until the buyer spends a reveal:
`POST /offers/:id/reveal` → `{ "phone": "+256758441260", "creditsRemaining": 10 }`

### Requirement (buyer RFQ) and Lead (supplier view of it)
```json
{
  "id": "req_1042",
  "buyerId": "acc_06",
  "title": "White maize grain, grade 1",
  "category": "Agriculture & produce",
  "quantity": { "amount": 500, "unit": "tonnes" },
  "specification": "13.5% moisture, machine cleaned",
  "deliverTo": { "address": "...", "district": "Kampala" },
  "neededBy": "2026-09-12",
  "estimatedValue": 348000000,
  "purpose": "Business use",        // Business use | Resale | Tender
  "status": "open",                 // open | quoted | awarded | withdrawn | expired
  "createdAt": "2026-08-19T08:12:00Z"
}
```
`GET /leads?district=&radiusKm=&categories=&minValue=&verifiedBuyer=&postedWithin=`
returns requirements matched to the caller's lead preferences. Radius filtering uses
district centroids — the frontend already computes this with `DISTRICTS` + `kmBetween`
if you would rather keep it client-side.

### Quote
```json
{ "id": "quo_88", "requirementId": "req_1042", "supplierId": "acc_03",
  "unitPrice": 1390, "quantity": "500 tonnes", "leadTime": "48 hours from order",
  "delivery": "Delivered", "validityDays": 10, "message": "...",
  "attachments": ["/media/spec.pdf"], "status": "sent" }
```
Status flow: `draft → sent → accepted | rejected | expired`.

### Order and escrow
```json
{
  "id": "BM-4471-LIR",
  "buyerId": "acc_06", "supplierId": "acc_03",
  "lines": [{ "productId": "p3", "quantity": 500, "unit": "tonnes", "unitPrice": 1390 }],
  "subtotal": 695000000, "vatRate": 0.18, "vat": 125100000, "total": 820100000,
  "payment": { "method": "mtn_momo", "payerPhone": "+256772903445", "reference": "MP260819.1204.A1" },
  "escrow": { "status": "held", "fundedAt": "...", "releasedAt": null },
  "status": "dispatch",   // pending_payment | funded | dispatch | in_transit | delivered | closed | refunded
  "documents": { "proforma": "/api/v1/orders/BM-4471-LIR/proforma.pdf",
                 "taxInvoice": null, "deliveryNote": null }
}
```
Escrow transitions: `POST /orders/:id/fund`, `/dispatch`, `/confirm-delivery`, `/dispute`.
Auto-release 7 days after delivery when no dispute exists.

### Dispute
```json
{ "id": "dsp_12", "orderId": "BM-4471-LIR", "raisedBy": "buyer",
  "claim": "Short delivery, 40 bags", "amountHeld": 1340000,
  "evidence": ["/media/photo1.jpg"], "status": "open",
  "resolution": null }          // { outcome: "refund_buyer" | "release_supplier", decidedBy, decidedAt, note }
```
`POST /admin/disputes/:id/resolve` with `{ "outcome": "refund_buyer", "note": "..." }`.

### Conversation and message
```json
{ "id": "cnv_7", "counterpartyId": "acc_06", "requirementId": "req_1042",
  "labels": ["Hot lead"], "lastMessageAt": "..." }

{ "id": "msg_91", "conversationId": "cnv_7", "direction": "out",
  "channel": "app",             // app | whatsapp | sms | call
  "body": "...", "sentAt": "...", "readAt": "..." }
```
`POST /conversations/:id/messages` → the sent message. Call events are messages with
`channel: "call"` and `meta: { durationSeconds, missed }`.

### Verification application (admin)
```json
{ "id": "app_31", "accountId": "acc_12", "submittedAt": "...", "waitingDays": 3,
  "registration": { "ursb": "...", "tin": "...", "tradingLicence": "..." },
  "documents": [{ "type": "certificate_of_incorporation", "url": "..." }],
  "registryChecks": { "ursb": "match", "ura": "match", "licence": "current", "sanctions": "clear" },
  "status": "pending" }
```
`POST /admin/applications/:id/approve` | `/reject` with `{ "reason": "..." }`.

---

## 3. Auth and OTP

```
POST /auth/request-otp   { "phone": "+256772415908" }        → { "challengeId", "expiresIn": 300 }
POST /auth/verify-otp    { "challengeId", "code": "123456" } → { "token", "account" }
POST /auth/refresh       { "refreshToken" }
POST /auth/logout
```
Rate limit OTP requests per phone (3 per 15 minutes). Never return whether a phone
is registered — reply identically either way.

Uganda specifics the backend must own:
- Validate phone as `+2567XXXXXXXX`; accept MTN, Airtel and UTL prefixes.
- Verify URSB registration number and URA TIN against the registries before granting
  the verified badge; store the check result and timestamp.
- Trading licence carries a district issuer and an expiry — surface the expiry so the
  frontend can show "Renew by".
- Issue EFRIS-fiscalised tax invoices; the frontend expects a `fiscalDocumentNumber`
  on every invoice PDF.
- Retain personal data and call recordings per the Data Protection and Privacy Act, 2019
  (recordings 90 days).

## 4. Payments

```
POST /payments/collect  { "orderId", "method": "mtn_momo", "phone": "+2567..." }
   → { "paymentId", "status": "prompt_sent" }
POST /payments/webhook  (provider callback: MTN MoMo, Airtel Money, bank)
GET  /payments/:id      → { status: prompt_sent | success | failed | timeout }
```
The UI polls the payment after showing "prompt sent". Never accept a PIN in the frontend.

## 5. Conventions

- Pagination: `?page=1&limit=20`, response `{ "data": [...], "meta": { "page", "limit", "total" } }`.
- Errors: `{ "error": { "code": "validation_failed", "message": "...", "fields": { "tin": "..." } } }`.
- Media: upload via `POST /media` (multipart) → `{ "url" }`; the frontend stores only URLs.
- Every list endpoint must accept the same filters the UI already exposes, so the filter
  chips map one-to-one onto query parameters.
- Role scoping is server-side: a supplier token must never return another supplier's
  leads, orders, conversations or documents.
