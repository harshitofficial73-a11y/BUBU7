-- BUBU.Market · seed the operations (admin) account
--
-- Run this AFTER 0001_schema.sql, 0002_rls.sql, 0003_functions.sql and seed.sql.
--
-- Two things to set in the dashboard first, or this login will not work:
--
--   1. Authentication → Providers → Email: enable it.
--   2. Authentication → Policies → Minimum password length: set to 5.
--      Supabase defaults to 6, and the password below is 5 characters.
--
-- The email is written as harshit@bubumarket.com. The address you gave,
-- harshit@bubumarket, has no top-level domain and Supabase Auth rejects it as
-- malformed. If you would rather use a different domain, change both places
-- marked ADMIN EMAIL below.

create extension if not exists "pgcrypto";

do $$
declare
  v_email    text := 'harshit@bubumarket.com';   -- ADMIN EMAIL
  v_password text := '12345';
  v_uid      uuid;
  v_acct     uuid;
begin
  -- ── auth user ────────────────────────────────────────────────────────────
  select id into v_uid from auth.users where email = v_email;

  if v_uid is null then
    v_uid := gen_random_uuid();
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) values (
      v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
      v_email, crypt(v_password, gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Harshit","role":"admin"}'::jsonb,
      now(), now()
    );
    raise notice 'Created auth user % (%)', v_email, v_uid;
  else
    update auth.users
       set encrypted_password = crypt(v_password, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_uid;
    raise notice 'Reset password for existing auth user %', v_email;
  end if;

  -- ── platform account row ─────────────────────────────────────────────────
  -- seed.sql already inserts an operations business on +256800218400, so attach to
  -- that row if it exists rather than inserting a second one (phone is unique).
  select id into v_acct from accounts where auth_user_id = v_uid;

  if v_acct is null then
    select id into v_acct from accounts
     where phone = '+256800218400' or lower(email) = lower(v_email) or role = 'admin'
     order by (role = 'admin') desc limit 1;

    if v_acct is not null then
      update accounts
         set auth_user_id = v_uid, role = 'admin', email = v_email, updated_at = now()
       where id = v_acct;
      raise notice 'Linked auth user to existing admin account %', v_acct;
    end if;
  end if;

  if v_acct is null then
    insert into accounts (
      auth_user_id, role, tier, company, trade_name, initials,
      phone, email, address, district_id
    ) values (
      v_uid, 'admin', 'free',
      'BUBU.Market Uganda Limited', 'Platform operations', 'BA',
      '+256800218400', v_email,
      'Level 4, Acacia Place, Kololo', 'kampala'
    ) returning id into v_acct;
    raise notice 'Created admin account row %', v_acct;
  else
    raise notice 'Admin account row already exists (%)', v_acct;
  end if;

  -- staff login beneath the business, so the console greets a person
  if not exists (select 1 from account_users where auth_user_id = v_uid) then
    insert into account_users (
      account_id, auth_user_id, full_name, role_title, phone,
      can_post, can_accept, can_release, can_billing
    ) values (
      v_acct, v_uid, 'Harshit', 'Verification lead', '+256800218400',
      true, true, true, true
    );
  end if;

  -- registration record: the operator itself is verified by definition
  if not exists (select 1 from account_registration where account_id = v_acct) then
    insert into account_registration (
      account_id, ursb_number, tin, trading_licence, licence_authority,
      overall_state, ursb_state, tin_state, licence_state, verified_at
    ) values (
      v_acct, '80020000000001', '1000000001', 'KCCA/TL/2026/00001', 'KCCA',
      'verified', 'verified', 'verified', 'verified', now()
    );
  end if;
end $$;

-- Confirm it landed:
--   select a.role, a.company, a.email, u.email_confirmed_at
--     from accounts a join auth.users u on u.id = a.auth_user_id
--    where a.role = 'admin';
