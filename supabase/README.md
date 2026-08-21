# BUBU.Market · Supabase backend

Four files, run in order in the Supabase SQL editor (or `supabase db push`):

    migrations/0001_schema.sql     tables, enums, indexes
    migrations/0002_rls.sql        row level security, one policy set per table
    migrations/0003_functions.sql  triggers, escrow transitions, buy-lead matching, views
    seed.sql                       the eleven demo businesses, districts, categories, fee rules

Then `supabase-adapter.js` is the only frontend file that changes: it returns the exact
shapes the screens already render, so no markup or render logic moves.

## What the schema owns

**Identity** — `accounts` holds one row per business; `account_users` holds the staff
logins beneath it, each with its own permissions (post, accept quotes, release escrow,
billing). `account_registration` is separate so an admin can verify URSB, TIN, licence,
VAT and NIN independently, each with its own state and an `overall_state` that gates the
verified badge.

**Catalogue** — `products` with `product_specs` and `media`. Listing status is
`draft | published | archived`; only published rows are world readable.

**Demand** — a buyer's `requirements` row is the same object a supplier sees as a buy
lead. `my_buy_leads()` returns only the leads matching the caller's saved categories,
districts, radius and minimum value, computed with `district_km()` from real district
centroids. Revealing a buyer's number goes through `reveal_contact()`, which spends one
`lead_credits` unit atomically and refuses when the balance is zero — the masked phone
never leaves the server unpaid.

**Money** — `orders` never trusts a client total: a trigger recomputes subtotal, 18% VAT
and total from `order_lines`. Escrow moves only through `fund_order()`,
`confirm_delivery()` and `release_escrow()`, and `release_escrow()` refuses while an
unresolved dispute exists. `auto_release_at` is set to seven days after delivery for a
scheduled job to sweep. `invoices` carries `efris_fdn` for the fiscal document number.

**Disputes** — either party may raise one; only an admin may resolve, and
`resolve_dispute()` writes the outcome and moves the escrow in one transaction.

## Row level security

Nothing is readable without a policy. `current_account_id()` resolves the caller's
business from either `accounts.auth_user_id` or `account_users.auth_user_id`, so staff
logins inherit their employer's scope. The rules that matter:

- A supplier cannot read another supplier's leads, orders, conversations or documents.
- Requirements are visible to suppliers only while `open` and only in their categories.
- Quotes are visible to the quoting supplier and the requirement's buyer, nobody else.
- Orders, lines, payments and invoices are visible to the two parties and admin.
- Messages are scoped through the conversation's two participants.
- Only admin may update `applications` or resolve `disputes`.

## Uganda specifics the backend owns

- Phone auth on `+2567XXXXXXXX`; rate-limit OTP to 3 per 15 minutes per number, and
  reply identically whether or not the number is registered.
- Verify URSB and URA TIN against the registries before setting `overall_state` to
  `verified`; store the check result and timestamp on `applications`.
- `licence_expires_on` drives the "Renew by" warning the UI already shows.
- Issue EFRIS-fiscalised invoices and populate `efris_fdn`.
- Call recordings on `messages.recording_path` are kept 90 days under the Data
  Protection and Privacy Act, 2019, then purged by a scheduled job.
- Never accept a MoMo PIN. `payments` records only the prompt and the provider callback.

## Storage

One bucket, `media`, with folders `products/`, `company/`, `documents/`. Registration
documents must be private (signed URLs only); product photos may be public.

## Environment

    window.BUBU_SUPABASE_URL = 'https://<project>.supabase.co';
    window.BUBU_SUPABASE_ANON_KEY = '<anon key>';

Service-role keys never reach the browser. Anything needing one belongs in an Edge
Function: payment webhooks, registry lookups, EFRIS fiscalisation, the auto-release
sweep and the recording purge.
