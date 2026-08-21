-- BUBU.Market · Supabase schema
-- Run in order: 0001_schema.sql, 0002_rls.sql, 0003_functions.sql, then seed.sql
-- Money is stored in integer UGX minor-free units (no decimals). Dates are timestamptz.

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────── enums

create type account_role      as enum ('buyer','supplier','admin');
create type business_type     as enum ('trader','manufacturer');
create type membership_tier   as enum ('free','star_supplier','industry_leader');
create type verification_state as enum ('unverified','pending','verified','rejected');
create type listing_status    as enum ('draft','published','archived');
create type requirement_state as enum ('open','quoted','awarded','withdrawn','expired');
create type quote_state       as enum ('draft','sent','accepted','rejected','expired');
create type order_state       as enum ('pending_payment','funded','dispatch','in_transit','delivered','closed','refunded');
create type escrow_state      as enum ('none','held','released','refunded');
create type payment_method    as enum ('mtn_momo','airtel_money','bank_transfer','credit_terms');
create type payment_state     as enum ('prompt_sent','success','failed','timeout');
create type dispute_state     as enum ('open','under_review','resolved');
create type dispute_outcome   as enum ('refund_buyer','release_supplier','split');
create type message_channel   as enum ('app','whatsapp','sms','call');
create type message_direction as enum ('in','out');
create type document_kind     as enum ('certificate_of_incorporation','ura_tin_certificate','trading_licence',
                                        'vat_certificate','national_id','bank_confirmation','unbs_certificate','other');

-- ─────────────────────────────────────────── geography

create table districts (
  id            text primary key,              -- 'kampala'
  name          text not null,
  region        text not null,                 -- Central | Eastern | Northern | Western
  lat           numeric(8,5) not null,
  lng           numeric(8,5) not null
);

-- ─────────────────────────────────────────── catalogue taxonomy

create table categories (
  id        text primary key,                  -- 'building-construction'
  name      text not null,
  parent_id text references categories,
  sort      integer default 0
);

-- ─────────────────────────────────────────── accounts

create table accounts (
  id                  uuid primary key default uuid_generate_v4(),
  auth_user_id        uuid unique references auth.users on delete set null,
  role                account_role not null,
  business_type       business_type,           -- null for buyers and admins
  tier                membership_tier not null default 'free',
  company             text not null,
  trade_name          text,
  initials            text,
  phone               text not null unique,    -- E.164, +2567XXXXXXXX
  alt_phone           text,
  whatsapp_phone      text,
  email               text,
  address             text,
  district_id         text references districts,
  incorporated_on     date,
  spend_12m           bigint default 0,
  supplier_count      integer default 0,
  about               text,
  coverage            text,
  nature_of_business  text,
  staff_count         text,
  turnover            text,
  brands              text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index on accounts (role);
create index on accounts (district_id);

-- registration records are separated so admin can verify each field independently
create table account_registration (
  account_id          uuid primary key references accounts on delete cascade,
  ursb_number         text,
  ursb_state          verification_state not null default 'unverified',
  tin                 text,
  tin_state           verification_state not null default 'unverified',
  trading_licence     text,
  licence_authority   text,                    -- 'KCCA', 'Mukono MC', district
  licence_expires_on  date,
  licence_state       verification_state not null default 'unverified',
  vat_number          text,
  vat_state           verification_state not null default 'unverified',
  director_nin        text,
  nin_state           verification_state not null default 'unverified',
  overall_state       verification_state not null default 'unverified',
  verified_at         timestamptz,
  verified_by         uuid references accounts
);

create table account_categories (
  account_id   uuid references accounts on delete cascade,
  category_id  text references categories,
  primary key (account_id, category_id)
);

create table account_users (            -- staff logins under one business
  id           uuid primary key default uuid_generate_v4(),
  account_id   uuid not null references accounts on delete cascade,
  auth_user_id uuid references auth.users on delete cascade,
  full_name    text not null,
  role_title   text,
  phone        text,
  can_post     boolean default true,
  can_accept   boolean default false,
  can_release  boolean default false,
  can_billing  boolean default false,
  created_at   timestamptz not null default now()
);

create table addresses (
  id          uuid primary key default uuid_generate_v4(),
  account_id  uuid not null references accounts on delete cascade,
  label       text not null,
  street      text not null,
  district_id text references districts,
  contact     text,
  phone       text,
  is_default  boolean default false
);

create table payout_methods (
  id          uuid primary key default uuid_generate_v4(),
  account_id  uuid not null references accounts on delete cascade,
  method      payment_method not null,
  detail      text not null,                  -- phone or masked account
  state       verification_state not null default 'unverified',
  is_default  boolean default false
);

create table handsets (                        -- the BUBU virtual-number ring list
  id           uuid primary key default uuid_generate_v4(),
  account_id   uuid not null references accounts on delete cascade,
  phone        text not null,
  owner_label  text,
  office_hours boolean default true,
  after_hours  boolean default false,
  verified_at  timestamptz,
  constraint handsets_max_five check (true)    -- enforced in application/trigger
);

-- ─────────────────────────────────────────── catalogue

create table products (
  id           uuid primary key default uuid_generate_v4(),
  supplier_id  uuid not null references accounts on delete cascade,
  name         text not null,
  category_id  text references categories,
  family       text,                           -- 'Aggregates', 'Grain and pulses'
  description  text,
  price        bigint not null,                -- UGX per unit
  unit         text not null,                  -- bag, tonne, kg, unit, set
  moq          integer not null default 1,
  brand        text,
  status       listing_status not null default 'draft',
  rating       numeric(2,1),
  order_count  integer default 0,
  view_count   integer default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on products (supplier_id);
create index on products (category_id);
create index on products using gin (to_tsvector('english', name || ' ' || coalesce(description,'')));

create table product_specs (
  id          uuid primary key default uuid_generate_v4(),
  product_id  uuid not null references products on delete cascade,
  key         text not null,
  value       text not null,
  sort        integer default 0
);

create table media (
  id          uuid primary key default uuid_generate_v4(),
  account_id  uuid not null references accounts on delete cascade,
  product_id  uuid references products on delete cascade,
  kind        text not null default 'product', -- product | company | certificate | premises
  storage_path text not null,                  -- Supabase Storage object path
  caption     text,
  approved    boolean default false,
  created_at  timestamptz not null default now()
);

create table documents (
  id           uuid primary key default uuid_generate_v4(),
  account_id   uuid not null references accounts on delete cascade,
  kind         document_kind not null,
  issuer       text,
  reference    text,
  issued_on    date,
  expires_on   date,
  storage_path text,
  state        verification_state not null default 'pending',
  created_at   timestamptz not null default now()
);

-- ─────────────────────────────────────────── demand side

create table requirements (                    -- buyer RFQ; suppliers see these as buy leads
  id           uuid primary key default uuid_generate_v4(),
  buyer_id     uuid not null references accounts on delete cascade,
  title        text not null,
  category_id  text references categories,
  quantity     numeric(14,2) not null,
  quantity_unit text not null,
  specification text,
  purpose      text,                            -- Business use | Resale | Tender
  deliver_to   text,
  district_id  text references districts,
  needed_by    date,
  estimated_value bigint,
  payment_method payment_method,
  state        requirement_state not null default 'open',
  created_at   timestamptz not null default now(),
  expires_at   timestamptz
);
create index on requirements (state, district_id, category_id);
create index on requirements (created_at desc);

create table quotes (
  id             uuid primary key default uuid_generate_v4(),
  requirement_id uuid not null references requirements on delete cascade,
  supplier_id    uuid not null references accounts on delete cascade,
  unit_price     bigint not null,
  quantity       text,
  lead_time      text,
  delivery_terms text,                          -- Delivered | Buyer collects | Ex works
  validity_days  integer default 10,
  message        text,
  state          quote_state not null default 'draft',
  created_at     timestamptz not null default now(),
  unique (requirement_id, supplier_id)
);

create table quote_attachments (
  id           uuid primary key default uuid_generate_v4(),
  quote_id     uuid not null references quotes on delete cascade,
  storage_path text not null,
  label        text
);

-- lead credits: revealing a buyer's number costs one
create table lead_credits (
  id          uuid primary key default uuid_generate_v4(),
  account_id  uuid not null references accounts on delete cascade,
  granted     integer not null,
  used        integer not null default 0,
  expires_on  date
);

create table contact_reveals (
  id             uuid primary key default uuid_generate_v4(),
  account_id     uuid not null references accounts on delete cascade,
  requirement_id uuid references requirements on delete cascade,
  product_id     uuid references products on delete cascade,
  revealed_at    timestamptz not null default now(),
  unique (account_id, requirement_id, product_id)
);

create table lead_preferences (
  account_id   uuid primary key references accounts on delete cascade,
  districts    text[] not null default '{}',
  radius_km    integer not null default 60,
  nationwide   boolean not null default false,
  min_value    bigint,
  verified_only boolean not null default false
);

-- ─────────────────────────────────────────── orders, escrow, money

create table orders (
  id             uuid primary key default uuid_generate_v4(),
  reference      text not null unique,          -- BM-2026-0418
  buyer_id       uuid not null references accounts,
  supplier_id    uuid not null references accounts,
  requirement_id uuid references requirements,
  quote_id       uuid references quotes,
  subtotal       bigint not null,
  vat_rate       numeric(4,3) not null default 0.180,
  vat            bigint not null default 0,
  delivery_fee   bigint not null default 0,
  total          bigint not null,
  deliver_to     text,
  district_id    text references districts,
  state          order_state not null default 'pending_payment',
  escrow_state   escrow_state not null default 'none',
  funded_at      timestamptz,
  dispatched_at  timestamptz,
  delivered_at   timestamptz,
  released_at    timestamptz,
  auto_release_at timestamptz,                  -- delivered_at + 7 days
  created_at     timestamptz not null default now()
);
create index on orders (buyer_id);
create index on orders (supplier_id);
create index on orders (state);

create table order_lines (
  id          uuid primary key default uuid_generate_v4(),
  order_id    uuid not null references orders on delete cascade,
  product_id  uuid references products,
  name        text not null,
  quantity    numeric(14,2) not null,
  unit        text not null,
  unit_price  bigint not null,
  line_total  bigint not null
);

create table payments (
  id          uuid primary key default uuid_generate_v4(),
  order_id    uuid not null references orders on delete cascade,
  method      payment_method not null,
  payer_phone text,
  amount      bigint not null,
  provider_ref text,
  state       payment_state not null default 'prompt_sent',
  raw_callback jsonb,
  created_at  timestamptz not null default now(),
  settled_at  timestamptz
);

create table invoices (
  id            uuid primary key default uuid_generate_v4(),
  account_id    uuid not null references accounts on delete cascade,
  order_id      uuid references orders on delete cascade,
  number        text not null unique,           -- BUBU-INV-2026-0431
  kind          text not null default 'tax',    -- tax | proforma | service
  subtotal      bigint not null,
  vat           bigint not null,
  total         bigint not null,
  issued_on     date not null default current_date,
  efris_fdn     text,                           -- EFRIS fiscal document number
  storage_path  text
);

create table subscriptions (                    -- supplier programme membership
  id          uuid primary key default uuid_generate_v4(),
  account_id  uuid not null references accounts on delete cascade,
  tier        membership_tier not null,
  price       bigint not null,
  lead_credits integer not null default 0,
  starts_on   date not null,
  ends_on     date not null,
  invoice_id  uuid references invoices
);

create table fee_rules (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null,
  applies_to  text not null,                    -- all_orders | export | tier
  rate        numeric(5,4),
  flat_amount bigint,
  minimum     bigint,
  payer       account_role not null,
  note        text,
  active      boolean default true
);

-- ─────────────────────────────────────────── disputes

create table disputes (
  id            uuid primary key default uuid_generate_v4(),
  order_id      uuid not null references orders on delete cascade,
  raised_by     uuid not null references accounts,
  claim         text not null,
  amount_held   bigint not null,
  state         dispute_state not null default 'open',
  outcome       dispute_outcome,
  decided_by    uuid references accounts,
  decided_at    timestamptz,
  resolution_note text,
  created_at    timestamptz not null default now()
);

create table dispute_evidence (
  id           uuid primary key default uuid_generate_v4(),
  dispute_id   uuid not null references disputes on delete cascade,
  storage_path text not null,
  caption      text
);

-- ─────────────────────────────────────────── conversations

create table conversations (
  id             uuid primary key default uuid_generate_v4(),
  supplier_id    uuid not null references accounts on delete cascade,
  buyer_id       uuid not null references accounts on delete cascade,
  requirement_id uuid references requirements on delete set null,
  labels         text[] default '{}',
  last_message_at timestamptz,
  created_at     timestamptz not null default now(),
  unique (supplier_id, buyer_id, requirement_id)
);

create table messages (
  id              uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references conversations on delete cascade,
  sender_id       uuid references accounts,
  direction       message_direction not null,
  channel         message_channel not null default 'app',
  body            text,
  call_seconds    integer,
  call_missed     boolean,
  recording_path  text,                          -- retained 90 days (DPPA 2019)
  sent_at         timestamptz not null default now(),
  read_at         timestamptz
);
create index on messages (conversation_id, sent_at);

-- ─────────────────────────────────────────── verification queue

create table applications (
  id           uuid primary key default uuid_generate_v4(),
  account_id   uuid not null references accounts on delete cascade,
  submitted_at timestamptz not null default now(),
  state        verification_state not null default 'pending',
  registry_ursb text,                            -- match | no_match | pending
  registry_ura  text,
  licence_check text,
  sanctions     text,
  decided_by   uuid references accounts,
  decided_at   timestamptz,
  reason       text
);
create index on applications (state, submitted_at);

-- ─────────────────────────────────────────── notifications

create table notification_prefs (
  account_id uuid not null references accounts on delete cascade,
  topic      text not null,                      -- enquiries | replies | followups | missed_calls | lead_alerts | tenders | payouts | offers
  email      boolean default false,
  sms        boolean default false,
  app        boolean default true,
  whatsapp   boolean default false,
  primary key (account_id, topic)
);

create table audit_log (
  id         bigserial primary key,
  actor_id   uuid references accounts,
  action     text not null,
  entity     text not null,
  entity_id  uuid,
  before     jsonb,
  after      jsonb,
  created_at timestamptz not null default now()
);
