-- Submit a supplier application in one database transaction.
-- The caller must already have an authenticated Supabase session (after email OTP).

create or replace function submit_supplier_application(
  p_company text,
  p_trade_name text,
  p_phone text,
  p_email text,
  p_business_type business_type,
  p_ursb_number text,
  p_tin text,
  p_trading_licence text,
  p_vat_number text default null,
  p_address text default null,
  p_district_id text default null
) returns applications
language plpgsql security definer set search_path = public as $$
declare
  v_account accounts;
  v_application applications;
begin
  if auth.uid() is null then
    raise exception 'sign in before submitting an application';
  end if;
  if coalesce(trim(p_company), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'company name and phone number are required';
  end if;

  insert into accounts (
    auth_user_id, role, business_type, company, trade_name, initials,
    phone, email, address, district_id
  ) values (
    auth.uid(), 'supplier', p_business_type, trim(p_company), nullif(trim(p_trade_name), ''),
    upper(left(trim(p_company), 1)), trim(p_phone), nullif(trim(p_email), ''),
    nullif(trim(p_address), ''), nullif(trim(p_district_id), '')
  )
  on conflict (auth_user_id) do update set
    business_type = excluded.business_type, company = excluded.company,
    trade_name = excluded.trade_name, phone = excluded.phone, email = excluded.email,
    address = excluded.address, district_id = excluded.district_id, updated_at = now()
  returning * into v_account;

  insert into account_registration (
    account_id, ursb_number, tin, trading_licence, vat_number,
    ursb_state, tin_state, licence_state, vat_state, overall_state
  ) values (
    v_account.id, nullif(trim(p_ursb_number), ''), nullif(trim(p_tin), ''),
    nullif(trim(p_trading_licence), ''), nullif(trim(p_vat_number), ''),
    'pending', 'pending', 'pending', case when nullif(trim(p_vat_number), '') is null then 'unverified' else 'pending' end,
    'pending'
  )
  on conflict (account_id) do update set
    ursb_number = excluded.ursb_number, tin = excluded.tin,
    trading_licence = excluded.trading_licence, vat_number = excluded.vat_number,
    ursb_state = 'pending', tin_state = 'pending', licence_state = 'pending',
    vat_state = excluded.vat_state, overall_state = 'pending',
    verified_at = null, verified_by = null;

  delete from applications where account_id = v_account.id and state = 'pending';
  insert into applications (account_id, state, registry_ursb, registry_ura, licence_check, sanctions)
  values (v_account.id, 'pending', 'pending', 'pending', 'pending', 'pending')
  returning * into v_application;

  return v_application;
end $$;

grant execute on function submit_supplier_application(text, text, text, text, business_type, text, text, text, text, text, text) to authenticated;
