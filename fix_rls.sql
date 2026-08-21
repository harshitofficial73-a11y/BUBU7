-- BUBU.Market · fix recursive row level security on accounts
--
-- Symptom: sign-in succeeds, but the app shows "No business linked" and drops
-- every role into the buyer portal. Reads of `accounts` return 401 or an
-- "infinite recursion detected in policy for relation accounts" error.
--
-- Cause: the accounts policy called current_account_id(), which itself selects
-- from accounts. Postgres re-enters the same policy while evaluating it and
-- aborts. The fix is to compare auth.uid() to accounts.auth_user_id directly,
-- so the policy never queries the table it guards.
--
-- Safe to run repeatedly.

-- ── helpers that do not touch accounts recursively ──────────────────────────

create or replace function current_account_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from accounts where auth_user_id = auth.uid()
  union all
  select account_id from account_users where auth_user_id = auth.uid()
  limit 1;
$$;

-- is_admin must not read accounts through a policy, so it bypasses RLS
create or replace function is_admin() returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v boolean;
begin
  select exists (
    select 1 from accounts a
     where a.auth_user_id = auth.uid() and a.role = 'admin'
  ) into v;
  return coalesce(v, false);
end $$;

create or replace function current_role_name() returns account_role
language plpgsql stable security definer set search_path = public as $$
declare v account_role;
begin
  select a.role into v from accounts a where a.auth_user_id = auth.uid() limit 1;
  return v;
end $$;

-- ── accounts: the policy now matches on auth_user_id, no self-query ─────────

drop policy if exists accounts_self        on accounts;
drop policy if exists accounts_update_self on accounts;
drop policy if exists accounts_admin_all   on accounts;

-- own row, always readable
create policy accounts_own_read on accounts for select
  using (auth_user_id = auth.uid());

-- staff read their employer's row
create policy accounts_staff_read on accounts for select
  using (exists (select 1 from account_users u
                  where u.account_id = accounts.id and u.auth_user_id = auth.uid()));

-- verified suppliers are public, so buyers can browse storefronts
create policy accounts_public_suppliers on accounts for select
  using (role = 'supplier' and exists (
           select 1 from account_registration r
            where r.account_id = accounts.id and r.overall_state = 'verified'));

-- admins see everything
create policy accounts_admin_read on accounts for select using (is_admin());

create policy accounts_own_update on accounts for update
  using (auth_user_id = auth.uid()) with check (auth_user_id = auth.uid());

create policy accounts_admin_write on accounts for all using (is_admin()) with check (is_admin());

-- ── account_registration: same treatment ───────────────────────────────────

drop policy if exists registration_self       on account_registration;
drop policy if exists registration_write_self on account_registration;
drop policy if exists registration_admin      on account_registration;

create policy registration_own on account_registration for select
  using (exists (select 1 from accounts a
                  where a.id = account_registration.account_id
                    and (a.auth_user_id = auth.uid()
                         or exists (select 1 from account_users u
                                     where u.account_id = a.id and u.auth_user_id = auth.uid()))));

create policy registration_public on account_registration for select
  using (overall_state = 'verified');

create policy registration_admin_all on account_registration for all
  using (is_admin()) with check (is_admin());

create policy registration_own_update on account_registration for update
  using (exists (select 1 from accounts a
                  where a.id = account_registration.account_id and a.auth_user_id = auth.uid()))
  with check (true);

-- ── account_users: needed by the helpers above ─────────────────────────────

drop policy if exists account_users_own on account_users;

create policy account_users_self on account_users for select
  using (auth_user_id = auth.uid()
         or exists (select 1 from accounts a
                     where a.id = account_users.account_id and a.auth_user_id = auth.uid())
         or is_admin());

create policy account_users_manage on account_users for all
  using (exists (select 1 from accounts a
                  where a.id = account_users.account_id and a.auth_user_id = auth.uid()) or is_admin())
  with check (exists (select 1 from accounts a
                       where a.id = account_users.account_id and a.auth_user_id = auth.uid()) or is_admin());

-- ── confirm ───────────────────────────────────────────────────────────────
-- Signed in as any user, this must return exactly one row:
--   select id, role, company from accounts where auth_user_id = auth.uid();
--
-- And this lists the live policies:
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename in ('accounts','account_registration','account_users')
--    order by tablename, policyname;
