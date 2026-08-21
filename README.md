# BUBU.Market — deployment package

    index.html            The platform (buyer, supplier and admin portals)
    desktop.html          Identical build, kept under its explicit name
    supabase-config.js    Your project URL and publishable key
    supabase-adapter.js   Data layer between the UI and Supabase
    .env.example          Same values as NEXT_PUBLIC_* for a Next.js or Vercel host
    supabase/             Backend: schema, RLS, functions, seed
    API.md                Resource shapes and Uganda compliance rules
    app/                  Editable sources

## 1. Deploy the frontend

Upload the folder as-is to Netlify, Vercel or any static host. index.html is
self-contained apart from supabase-config.js and supabase-adapter.js, which must sit
beside it. No build step.

## 2. Create the database

In the Supabase SQL editor run, in order:

    supabase/migrations/0001_schema.sql
    supabase/migrations/0002_rls.sql
    supabase/migrations/0003_functions.sql
    supabase/seed.sql
    supabase/seed_admin.sql   creates the operations login

Then create a storage bucket named `media` with folders products/, company/ and
documents/. Keep documents/ private and serve it by signed URL only.

## 3. Authentication

Buyers, suppliers and admins all sign in with **email and password**, so enable the
Email provider in Authentication → Providers. Supplier registration also verifies a
phone number by SMS, which needs the Phone provider and an SMS gateway with Uganda
coverage (Twilio, MessageBird or Vonage). Until that gateway exists supplier
registration still completes — only the SMS step is inert.

The operations login is seeded by supabase/seed_admin.sql:

    harshit@bubumarket.com  /  12345

That script needs two dashboard settings or the login fails: enable the Email
provider, and set Authentication -> Policies -> Minimum password length to 5
(Supabase defaults to 6, and that password is five characters).

The address supplied, harshit@bubumarket, has no top-level domain and Auth
rejects it as malformed, so .com was added. Change it in the script if you want
another domain.

## 4. Connection

Already filled in for your project:

    window.BUBU_SUPABASE_URL = "https://thnrbkjkpvgbfjeeiwuj.supabase.co";
    window.BUBU_SUPABASE_ANON_KEY = "sb_publishable_pZpel8n9_bQea7eoCptIAA_5pCtZDlm";

The publishable key belongs in the browser; row level security decides what it can
read. Never ship the Secret key. Anything needing it goes in an Edge Function:
payment webhooks, URSB and URA registry lookups, EFRIS fiscalisation, the seven-day
escrow auto-release sweep and the ninety-day call-recording purge.

## How access works

Registration is a pre-authentication flow. The buyer profile form, the supplier
application and the "under review" screen render as full-page overlays outside the
authenticated shell, and none of them is a routable screen — so opening one cannot
sign anyone in or expose a portal.

Buyers register and trade immediately: name, mobile, email, password, business type,
city and buying interests, no verification. Suppliers submit URSB, URA TIN and licence
details with at least one document, then wait for admin approval before sign-in works.

## State of the frontend

All demo data and hardcoded images are removed; every screen renders from the
database. Empty image slots show a placeholder tile so layouts read correctly before
media exists. With empty tables the screens are legitimately empty — insert a supplier
and a few products to watch records flow through.

## Seed data

Run `supabase/seed_full.sql` instead of the older seed files — it replaces seed.sql,
seed_admin.sql and seed_test_logins.sql, and is safe to re-run.

It creates 16 districts, 22 categories, fee rules, five supplier businesses, four
buyers, one operations account, 24 products with specifications and photo records,
eight buyer requirements, seven supplier quotes, six orders across every escrow
state, invoices, conversations with messages, one open dispute and one application
awaiting verification.

### Logins — all password 12345

    harshit@bubumarket.com   admin
    ivan@bubu.market         supplier   Ivan Trading Company Limited
    moses@khd.co.ug          supplier   Kampala Hardware Depot Limited
    denis@nilegrain.co.ug    supplier   Nile Grain and Produce Limited
    peter@namanve.co.ug      supplier   Namanve Construction Supplies Limited
    aisha@medisure.co.ug     supplier   Medisure Wholesale Limited
    ayabare@bubu.market      buyer      Ayabare Construction Limited
    grace@nakawa.co.ug       buyer      Nakawa Trading Co. Limited
    peter@nsambya.co.ug      buyer      Nsambya Hospital Supplies Limited
    irene@seeta.co.ug        buyer      Seeta Housing Developments Limited

Set Authentication -> Policies -> Minimum password length to 5, or these are refused.

### Product photos

Upload the contents of `media-upload/products/` to the `media` storage bucket under
a `products/` folder. The seed's photo records point at those exact filenames, so
every product picks up its image. Products without a file show a placeholder tile.
