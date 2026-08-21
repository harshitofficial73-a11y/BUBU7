-- BUBU.Market · reset the database to empty
--
-- ⚠ DESTRUCTIVE. This drops every BUBU table, type, function and view, and deletes
-- every auth user. Only run it on a project you are happy to wipe. There is no undo.
--
-- Run this, then re-run in order:
--   0001_schema.sql, 0002_rls.sql, 0003_functions.sql, seed.sql, seed_admin.sql

-- ── 1. tables (dependency order handled by CASCADE) ──────────────────────────
drop table if exists audit_log              cascade;
drop table if exists notification_prefs     cascade;
drop table if exists applications           cascade;
drop table if exists messages               cascade;
drop table if exists conversations          cascade;
drop table if exists dispute_evidence       cascade;
drop table if exists disputes               cascade;
drop table if exists fee_rules              cascade;
drop table if exists subscriptions          cascade;
drop table if exists invoices               cascade;
drop table if exists payments               cascade;
drop table if exists order_lines            cascade;
drop table if exists orders                 cascade;
drop table if exists lead_preferences       cascade;
drop table if exists contact_reveals        cascade;
drop table if exists lead_credits           cascade;
drop table if exists quote_attachments      cascade;
drop table if exists quotes                 cascade;
drop table if exists requirements           cascade;
drop table if exists documents              cascade;
drop table if exists media                  cascade;
drop table if exists product_specs          cascade;
drop table if exists products               cascade;
drop table if exists handsets               cascade;
drop table if exists payout_methods         cascade;
drop table if exists addresses              cascade;
drop table if exists account_users          cascade;
drop table if exists account_categories     cascade;
drop table if exists account_registration   cascade;
drop table if exists accounts               cascade;
drop table if exists categories             cascade;
drop table if exists districts              cascade;

-- ── 2. views ─────────────────────────────────────────────────────────────────
drop view if exists supplier_catalog_stats cascade;
drop view if exists product_offers         cascade;
drop view if exists public_suppliers       cascade;

-- ── 3. functions ─────────────────────────────────────────────────────────────
drop function if exists my_buy_leads()                                cascade;
drop function if exists district_km(text, text)                       cascade;
drop function if exists reveal_contact(uuid, uuid)                    cascade;
drop function if exists reject_application(uuid, text)                cascade;
drop function if exists approve_application(uuid)                     cascade;
drop function if exists resolve_dispute(uuid, dispute_outcome, text)  cascade;
drop function if exists release_escrow(uuid)                          cascade;
drop function if exists confirm_delivery(uuid)                        cascade;
drop function if exists fund_order(uuid, payment_method, text)        cascade;
drop function if exists compute_order_totals()                        cascade;
drop function if exists next_order_reference()                        cascade;
drop function if exists touch_updated_at()                            cascade;
drop function if exists is_admin()                                    cascade;
drop function if exists current_role_name()                           cascade;
drop function if exists current_account_id()                          cascade;

drop sequence if exists order_ref_seq cascade;

-- ── 4. enum types ────────────────────────────────────────────────────────────
drop type if exists document_kind      cascade;
drop type if exists message_direction  cascade;
drop type if exists message_channel    cascade;
drop type if exists dispute_outcome    cascade;
drop type if exists dispute_state      cascade;
drop type if exists payment_state      cascade;
drop type if exists payment_method     cascade;
drop type if exists escrow_state       cascade;
drop type if exists order_state        cascade;
drop type if exists quote_state        cascade;
drop type if exists requirement_state  cascade;
drop type if exists listing_status     cascade;
drop type if exists verification_state cascade;
drop type if exists membership_tier    cascade;
drop type if exists business_type      cascade;
drop type if exists account_role       cascade;

-- ── 5. auth users ────────────────────────────────────────────────────────────
-- Removes every registered user, including your admin. seed_admin.sql recreates it.
-- Child rows in auth.identities and auth.sessions cascade automatically.
delete from auth.users;

-- ── 6. storage objects (optional) ────────────────────────────────────────────
-- Uncomment to clear uploaded photos and documents as well.
-- delete from storage.objects where bucket_id = 'media';
-- delete from storage.buckets where id = 'media';

-- ── confirm it is clean ──────────────────────────────────────────────────────
-- Expect zero rows:
--   select table_name from information_schema.tables
--    where table_schema = 'public' and table_name in ('accounts','products','orders');
--   select count(*) from auth.users;
