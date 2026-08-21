-- BUBU.Market · pre-fed test logins
--
-- Creates one approved supplier and one buyer so you can sign in and exercise the
-- platform before any real registrations exist.
--
--   Supplier   ivan@bubu.market      / 12345
--   Buyer      ayabare@bubu.market   / 12345
--
-- Run AFTER 0001_schema.sql, 0002_rls.sql, 0003_functions.sql and seed.sql.
-- Safe to run repeatedly: it updates instead of duplicating.
--
-- Two dashboard settings this needs, or sign-in fails:
--   Authentication → Providers → Email: enabled, "Confirm email" OFF.
--   Authentication → Policies → Minimum password length: 5.

create extension if not exists "pgcrypto";

do $$
declare
  r          record;
  v_uid      uuid;
  v_acct     uuid;
  v_password text := '12345';
begin
  for r in
    select * from (values
      -- email,                role,       company,                              trade,              initials, person,          title,                phone,            district,  biztype,        tier,              ursb,             tin,          licence
      ('ivan@bubu.market',     'supplier', 'Ivan Trading Company Limited',        'Ivan Trading',     'IT',     'Ivan Ssekandi', 'Managing director',  '+256772100201',  'kampala', 'trader',       'star_supplier',   '80020007712045', '1005512340', 'KCCA/TL/2026/07721'),
      ('ayabare@bubu.market',  'buyer',    'Ayabare Construction Limited',        'Ayabare',          'AC',     'Grace Ayabare', 'Procurement lead',   '+256772100202',  'wakiso',  null,           'free',            '80020007712046', '1005512341', 'WDC/TL/2026/03318')
    ) as t(email, role, company, trade, initials, person, title, phone, district, biztype, tier, ursb, tin, licence)
  loop
    -- ── auth user ──────────────────────────────────────────────────────────
    select id into v_uid from auth.users where lower(email) = lower(r.email);

    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users (
        id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
      ) values (
        v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        r.email, crypt(v_password, gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', r.person, 'role', r.role),
        now(), now()
      );
      raise notice 'Created auth user %', r.email;
    else
      update auth.users
         set encrypted_password = crypt(v_password, gen_salt('bf')),
             email_confirmed_at = coalesce(email_confirmed_at, now()),
             updated_at = now()
       where id = v_uid;
      raise notice 'Reset password for %', r.email;
    end if;

    -- ── account row (phone is unique, so match before inserting) ───────────
    select id into v_acct from accounts
     where auth_user_id = v_uid or phone = r.phone or lower(email) = lower(r.email)
     limit 1;

    if v_acct is null then
      insert into accounts (
        auth_user_id, role, business_type, tier, company, trade_name, initials,
        phone, email, address, district_id, incorporated_on,
        about, coverage, nature_of_business
      ) values (
        v_uid, r.role::account_role, r.biztype::business_type, r.tier::membership_tier,
        r.company, r.trade, r.initials,
        r.phone, r.email,
        case when r.role = 'supplier' then 'Plot 24, Sixth Street, Industrial Area'
             else 'Plot 8, Kira Road' end,
        r.district, date '2019-06-01',
        case when r.role = 'supplier'
             then 'Wholesale supply of building materials and hardware across central Uganda.'
             else null end,
        case when r.role = 'supplier' then 'Kampala, Wakiso and Mukono' else null end,
        case when r.role = 'supplier' then 'Wholesale of construction materials' else null end
      ) returning id into v_acct;
      raise notice 'Created % account %', r.role, v_acct;
    else
      update accounts
         set auth_user_id  = v_uid,
             role          = r.role::account_role,
             business_type = r.biztype::business_type,
             tier          = r.tier::membership_tier,
             company       = r.company,
             trade_name    = r.trade,
             initials      = r.initials,
             email         = r.email,
             district_id   = r.district,
             updated_at    = now()
       where id = v_acct;
      raise notice 'Updated existing account % for %', v_acct, r.email;
    end if;

    -- ── staff login, so the app greets a person ────────────────────────────
    if not exists (select 1 from account_users where auth_user_id = v_uid) then
      insert into account_users (
        account_id, auth_user_id, full_name, role_title, phone,
        can_post, can_accept, can_release, can_billing
      ) values (v_acct, v_uid, r.person, r.title, r.phone, true, true, true, true);
    end if;

    -- ── registration record: verified, so the supplier can trade at once ───
    if not exists (select 1 from account_registration where account_id = v_acct) then
      insert into account_registration (
        account_id, ursb_number, tin, trading_licence, licence_authority,
        licence_expires_on, director_nin,
        overall_state, ursb_state, tin_state, licence_state, nin_state, verified_at
      ) values (
        v_acct, r.ursb, r.tin, r.licence,
        case when r.district = 'kampala' then 'KCCA' else 'Wakiso DLG' end,
        date '2026-12-31',
        case when r.role = 'supplier' then 'CM88041192WQ7H' else 'CF90210458PQ3K' end,
        'verified', 'verified', 'verified', 'verified', 'verified', now()
      );
    else
      update account_registration
         set overall_state = 'verified', verified_at = coalesce(verified_at, now())
       where account_id = v_acct;
    end if;

    -- ── categories ────────────────────────────────────────────────────────
    insert into account_categories (account_id, category_id)
    select v_acct, c
      from (values ('building-construction'), ('hardware-tools')) as x(c)
     where exists (select 1 from categories where id = x.c)
    on conflict do nothing;

    -- ── supplier extras: lead credits and lead preferences ────────────────
    if r.role = 'supplier' then
      insert into lead_credits (account_id, granted, expires_on)
      select v_acct, 18, current_date + interval '1 year'
       where not exists (select 1 from lead_credits where account_id = v_acct);

      insert into lead_preferences (account_id, districts, radius_km)
      values (v_acct, array[r.district], 60)
      on conflict (account_id) do nothing;
    end if;

    -- ── notification defaults ─────────────────────────────────────────────
    insert into notification_prefs (account_id, topic, email, sms, app, whatsapp)
    select v_acct, t.topic, t.email, t.sms, true, t.whatsapp
      from (values ('enquiries', true, false, true), ('replies', true, false, false),
                   ('followups', true, false, false), ('missed_calls', false, true, true),
                   ('lead_alerts', true, true, false), ('tenders', false, false, false),
                   ('payouts', true, true, true), ('offers', false, false, false)
           ) as t(topic, email, sms, whatsapp)
    on conflict do nothing;
  end loop;
end $$;

-- Confirm both logins exist:
--   select a.role, a.company, a.email, r.overall_state, u.email_confirmed_at is not null as confirmed
--     from accounts a
--     join auth.users u on u.id = a.auth_user_id
--     left join account_registration r on r.account_id = a.id
--    where a.email in ('ivan@bubu.market','ayabare@bubu.market');
