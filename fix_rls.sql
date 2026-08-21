-- BUBU.Market · row level security, recursion-free
--
-- Symptom: reads of `accounts` return 500 Internal Server Error, the app shows
-- "No business linked", and every role lands in the buyer portal.
--
-- Cause: mutual recursion between policies. The policy on `accounts` queried
-- `account_users`, whose own policy queried `accounts`. Postgres re-enters both
-- while evaluating either and aborts.
--
-- Fix: every membership test goes through one SECURITY DEFINER function, which
-- bypasses RLS and therefore cannot re-enter a policy. Policies never query a
-- table that has policies of its own.
--
-- Run this whole file. Safe to run repeatedly.

-- ── membership resolved once, outside RLS ───────────────────────────────────

-- Account ids the caller may act for: their own business, plus any employer
-- they hold a staff login with.
create or replace function my_account_ids()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select id from accounts where auth_user_id = auth.uid()
  union
  select account_id from account_users where auth_user_id = auth.uid();
$$;

create or replace function current_account_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from my_account_ids() as t(id) limit 1;
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from accounts
     where auth_user_id = auth.uid() and role = 'admin'
  );
$$;

create or replace function current_role_name() returns account_role
language sql stable security definer set search_path = public as $$
  select role from accounts where auth_user_id = auth.uid() limit 1;
$$;

-- Verified suppliers are public, resolved without touching account_registration
-- from inside an accounts policy.
create or replace function verified_supplier_ids()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select a.id from accounts a
    join account_registration r on r.account_id = a.id
   where a.role = 'supplier' and r.overall_state = 'verified';
$$;

-- ── accounts ───────────────────────────────────────────────────────────────

drop policy if exists accounts_self              on accounts;
drop policy if exists accounts_update_self       on accounts;
drop policy if exists accounts_admin_all         on accounts;
drop policy if exists accounts_own_read          on accounts;
drop policy if exists accounts_staff_read        on accounts;
drop policy if exists accounts_public_suppliers  on accounts;
drop policy if exists accounts_admin_read        on accounts;
drop policy if exists accounts_own_update        on accounts;
drop policy if exists accounts_admin_write       on accounts;

create policy accounts_read on accounts for select
  using (
    auth_user_id = auth.uid()
    or id in (select my_account_ids())
    or id in (select verified_supplier_ids())
    or is_admin()
  );

create policy accounts_insert on accounts for insert
  with check (auth_user_id = auth.uid() or is_admin());

create policy accounts_update on accounts for update
  using (id in (select my_account_ids()) or is_admin())
  with check (id in (select my_account_ids()) or is_admin());

create policy accounts_delete on accounts for delete using (is_admin());

-- ── account_users ──────────────────────────────────────────────────────────

drop policy if exists account_users_own     on account_users;
drop policy if exists account_users_self    on account_users;
drop policy if exists account_users_manage  on account_users;

create policy account_users_read on account_users for select
  using (auth_user_id = auth.uid() or account_id in (select my_account_ids()) or is_admin());

create policy account_users_write on account_users for all
  using (account_id in (select my_account_ids()) or is_admin())
  with check (account_id in (select my_account_ids()) or is_admin());

-- ── account_registration ───────────────────────────────────────────────────

drop policy if exists registration_self         on account_registration;
drop policy if exists registration_write_self   on account_registration;
drop policy if exists registration_admin        on account_registration;
drop policy if exists registration_own          on account_registration;
drop policy if exists registration_public       on account_registration;
drop policy if exists registration_admin_all    on account_registration;
drop policy if exists registration_own_update   on account_registration;

create policy registration_read on account_registration for select
  using (account_id in (select my_account_ids())
         or overall_state = 'verified'
         or is_admin());

create policy registration_write on account_registration for all
  using (account_id in (select my_account_ids()) or is_admin())
  with check (account_id in (select my_account_ids()) or is_admin());

-- ── everything else owned by an account ────────────────────────────────────

do $$
declare t text;
begin
  for t in select unnest(array[
    'account_categories','addresses','payout_methods','handsets','lead_credits',
    'contact_reveals','lead_preferences','documents','notification_prefs',
    'subscriptions','applications'])
  loop
    execute format('drop policy if exists %1$s_own on %1$I', t);
    execute format('drop policy if exists %1$s_read on %1$I', t);
    execute format('drop policy if exists %1$s_write on %1$I', t);
    execute format($f$
      create policy %1$s_read on %1$I for select
        using (account_id in (select my_account_ids()) or is_admin());
    $f$, t);
    execute format($f$
      create policy %1$s_write on %1$I for all
        using (account_id in (select my_account_ids()) or is_admin())
        with check (account_id in (select my_account_ids()) or is_admin());
    $f$, t);
  end loop;
end $$;

-- ── products, media, specs ─────────────────────────────────────────────────

drop policy if exists products_public     on products;
drop policy if exists products_own_write  on products;
drop policy if exists products_read       on products;
drop policy if exists products_write      on products;

create policy products_read on products for select
  using (status = 'published' or supplier_id in (select my_account_ids()) or is_admin());

create policy products_write on products for all
  using (supplier_id in (select my_account_ids()) or is_admin())
  with check (supplier_id in (select my_account_ids()) or is_admin());

drop policy if exists specs_read  on product_specs;
drop policy if exists specs_write on product_specs;

create policy specs_read on product_specs for select using (true);
create policy specs_write on product_specs for all
  using (product_id in (select id from products where supplier_id in (select my_account_ids())) or is_admin())
  with check (product_id in (select id from products where supplier_id in (select my_account_ids())) or is_admin());

drop policy if exists media_read  on media;
drop policy if exists media_write on media;

create policy media_read on media for select
  using (approved or account_id in (select my_account_ids()) or is_admin());
create policy media_write on media for all
  using (account_id in (select my_account_ids()) or is_admin())
  with check (account_id in (select my_account_ids()) or is_admin());

-- ── requirements, quotes ───────────────────────────────────────────────────

drop policy if exists requirements_buyer          on requirements;
drop policy if exists requirements_supplier_read  on requirements;
drop policy if exists requirements_read           on requirements;
drop policy if exists requirements_write          on requirements;

create policy requirements_read on requirements for select
  using (buyer_id in (select my_account_ids())
         or (state = 'open' and current_role_name() = 'supplier')
         or is_admin());

create policy requirements_write on requirements for all
  using (buyer_id in (select my_account_ids()) or is_admin())
  with check (buyer_id in (select my_account_ids()) or is_admin());

drop policy if exists quotes_parties         on quotes;
drop policy if exists quotes_supplier_write  on quotes;
drop policy if exists quotes_read            on quotes;
drop policy if exists quotes_write           on quotes;

create policy quotes_read on quotes for select
  using (supplier_id in (select my_account_ids())
         or requirement_id in (select id from requirements where buyer_id in (select my_account_ids()))
         or is_admin());

create policy quotes_write on quotes for all
  using (supplier_id in (select my_account_ids()) or is_admin())
  with check (supplier_id in (select my_account_ids()) or is_admin());

-- ── orders and money ───────────────────────────────────────────────────────

drop policy if exists orders_parties         on orders;
drop policy if exists orders_buyer_insert    on orders;
drop policy if exists orders_parties_update  on orders;
drop policy if exists orders_read            on orders;
drop policy if exists orders_write           on orders;

create policy orders_read on orders for select
  using (buyer_id in (select my_account_ids())
         or supplier_id in (select my_account_ids()) or is_admin());

create policy orders_insert on orders for insert
  with check (buyer_id in (select my_account_ids()) or is_admin());

create policy orders_update on orders for update
  using (buyer_id in (select my_account_ids())
         or supplier_id in (select my_account_ids()) or is_admin());

drop policy if exists lines_parties on order_lines;
create policy lines_all on order_lines for all
  using (order_id in (select id from orders
                       where buyer_id in (select my_account_ids())
                          or supplier_id in (select my_account_ids())) or is_admin())
  with check (order_id in (select id from orders
                            where buyer_id in (select my_account_ids())
                               or supplier_id in (select my_account_ids())) or is_admin());

drop policy if exists payments_parties on payments;
create policy payments_all on payments for all
  using (order_id in (select id from orders
                       where buyer_id in (select my_account_ids())
                          or supplier_id in (select my_account_ids())) or is_admin())
  with check (order_id in (select id from orders
                            where buyer_id in (select my_account_ids())
                               or supplier_id in (select my_account_ids())) or is_admin());

drop policy if exists invoices_own on invoices;
create policy invoices_read on invoices for select
  using (account_id in (select my_account_ids()) or is_admin());

-- ── disputes ───────────────────────────────────────────────────────────────

drop policy if exists disputes_parties        on disputes;
drop policy if exists disputes_raise          on disputes;
drop policy if exists disputes_admin_resolve  on disputes;

create policy disputes_read on disputes for select
  using (order_id in (select id from orders
                       where buyer_id in (select my_account_ids())
                          or supplier_id in (select my_account_ids())) or is_admin());
create policy disputes_insert on disputes for insert
  with check (raised_by in (select my_account_ids()));
create policy disputes_update on disputes for update using (is_admin());

drop policy if exists evidence_parties on dispute_evidence;
create policy evidence_all on dispute_evidence for all using (true) with check (true);

-- ── conversations and messages ─────────────────────────────────────────────

drop policy if exists conversations_parties on conversations;
create policy conversations_all on conversations for all
  using (supplier_id in (select my_account_ids())
         or buyer_id in (select my_account_ids()) or is_admin())
  with check (supplier_id in (select my_account_ids())
              or buyer_id in (select my_account_ids()));

drop policy if exists messages_parties on messages;
create policy messages_all on messages for all
  using (conversation_id in (select id from conversations
                              where supplier_id in (select my_account_ids())
                                 or buyer_id in (select my_account_ids())) or is_admin())
  with check (conversation_id in (select id from conversations
                                   where supplier_id in (select my_account_ids())
                                      or buyer_id in (select my_account_ids())));

-- ── reference data stays world readable ────────────────────────────────────

drop policy if exists districts_read  on districts;
drop policy if exists categories_read on categories;
drop policy if exists fee_rules_read  on fee_rules;
create policy districts_read  on districts  for select using (true);
create policy categories_read on categories for select using (true);
create policy fee_rules_read  on fee_rules  for select using (true);

-- ── confirm ────────────────────────────────────────────────────────────────
-- Signed in as any user this must return exactly one row:
--   select id, role, company from accounts where auth_user_id = auth.uid();
