-- BUBU.Market · clear seed data only
--
-- Removes every seeded row and every auth user, but leaves the schema, RLS policies
-- and functions in place. Run this before re-running seed_full.sql.
--
-- Order matters: children before parents.

-- trade activity
delete from messages;
delete from conversations;
delete from dispute_evidence;
delete from disputes;
delete from invoices;
delete from payments;
delete from order_lines;
delete from orders;
delete from quote_attachments;
delete from quotes;
delete from requirements;

-- catalogue
delete from product_specs;
delete from media;
delete from products;

-- account attachments
delete from documents;
delete from notification_prefs;
delete from lead_preferences;
delete from contact_reveals;
delete from lead_credits;
delete from subscriptions;
delete from handsets;
delete from payout_methods;
delete from addresses;
delete from account_categories;
delete from applications;
delete from account_users;
delete from account_registration;
delete from accounts;

-- reference data (seed_full.sql re-inserts these)
delete from fee_rules;
delete from categories;
delete from districts;

-- every login, so seed_full.sql can recreate them cleanly
delete from auth.users;

-- restart the order reference counter
alter sequence if exists order_ref_seq restart with 1;

-- Expect all zeros:
--   select
--     (select count(*) from accounts)     as accounts,
--     (select count(*) from products)     as products,
--     (select count(*) from orders)       as orders,
--     (select count(*) from auth.users)   as users;
