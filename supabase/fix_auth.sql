-- BUBU.Market · repair manually inserted auth users
--
-- Run this if sign-in fails with "Database error querying schema" and a 500 on
-- /auth/v1/token?grant_type=password.
--
-- Cause: GoTrue (Supabase Auth) reads several auth.users columns into non-nullable
-- Go strings. A user created by SQL rather than through the Auth API leaves them
-- NULL, and the scan fails on every sign-in attempt. It also needs a row in
-- auth.identities to resolve an email login.
--
-- Safe to run repeatedly. No data is lost.

update auth.users set
  confirmation_token         = coalesce(confirmation_token, ''),
  recovery_token             = coalesce(recovery_token, ''),
  email_change_token_new     = coalesce(email_change_token_new, ''),
  email_change               = coalesce(email_change, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change               = coalesce(phone_change, ''),
  phone_change_token         = coalesce(phone_change_token, ''),
  reauthentication_token     = coalesce(reauthentication_token, ''),
  email_confirmed_at         = coalesce(email_confirmed_at, now());

insert into auth.identities (id, user_id, identity_data, provider, provider_id,
                             last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', u.email, now(), now(), now()
  from auth.users u
 where not exists (select 1 from auth.identities i
                    where i.user_id = u.id and i.provider = 'email');

-- Confirm: every row should show ok = true
--   select email,
--          (confirmation_token is not null and recovery_token is not null
--           and email_change is not null) as columns_ok,
--          exists (select 1 from auth.identities i where i.user_id = u.id) as identity_ok
--     from auth.users u order by email;
