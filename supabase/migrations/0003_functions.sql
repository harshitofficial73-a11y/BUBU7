-- BUBU.Market · functions, triggers and views

-- keep updated_at honest
create or replace function touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger accounts_touch before update on accounts for each row execute function touch_updated_at();
create trigger products_touch before update on products for each row execute function touch_updated_at();

-- order reference: BM-YYYY-NNNN
create sequence if not exists order_ref_seq;
create or replace function next_order_reference() returns text language sql as $$
  select 'BM-' || to_char(now(),'YYYY') || '-' || lpad(nextval('order_ref_seq')::text, 4, '0');
$$;

-- VAT and total are computed, never trusted from the client
create or replace function compute_order_totals() returns trigger language plpgsql as $$
begin
  new.subtotal := coalesce((select sum(line_total) from order_lines where order_id = new.id), new.subtotal);
  new.vat      := round(new.subtotal * new.vat_rate);
  new.total    := new.subtotal + new.vat + coalesce(new.delivery_fee, 0);
  return new;
end $$;
create trigger orders_totals before insert or update on orders
  for each row execute function compute_order_totals();

-- escrow transitions, the only sanctioned path
create or replace function fund_order(p_order uuid, p_method payment_method, p_phone text)
returns payments language plpgsql security definer as $$
declare p payments;
begin
  insert into payments (order_id, method, payer_phone, amount, state)
  select p_order, p_method, p_phone, total, 'prompt_sent' from orders where id = p_order
  returning * into p;
  update orders set state = 'funded', escrow_state = 'held', funded_at = now() where id = p_order;
  return p;
end $$;

create or replace function confirm_delivery(p_order uuid)
returns orders language plpgsql security definer as $$
declare o orders;
begin
  update orders set state = 'delivered', delivered_at = now(),
    auto_release_at = now() + interval '7 days'
  where id = p_order returning * into o;
  return o;
end $$;

create or replace function release_escrow(p_order uuid)
returns orders language plpgsql security definer as $$
declare o orders;
begin
  update orders set escrow_state = 'released', released_at = now(), state = 'closed'
  where id = p_order and not exists (
    select 1 from disputes d where d.order_id = p_order and d.state <> 'resolved')
  returning * into o;
  return o;
end $$;

create or replace function resolve_dispute(p_dispute uuid, p_outcome dispute_outcome, p_note text)
returns disputes language plpgsql security definer as $$
declare d disputes;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update disputes set state = 'resolved', outcome = p_outcome, resolution_note = p_note,
    decided_by = current_account_id(), decided_at = now()
  where id = p_dispute returning * into d;
  update orders set escrow_state = case when p_outcome = 'refund_buyer' then 'refunded' else 'released' end,
    state = case when p_outcome = 'refund_buyer' then 'refunded' else 'closed' end,
    released_at = now()
  where id = d.order_id;
  return d;
end $$;

-- verification decisions
create or replace function approve_application(p_app uuid)
returns applications language plpgsql security definer as $$
declare a applications;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update applications set state = 'verified', decided_by = current_account_id(), decided_at = now()
  where id = p_app returning * into a;
  update account_registration set overall_state = 'verified', verified_at = now(),
    verified_by = current_account_id() where account_id = a.account_id;
  return a;
end $$;

create or replace function reject_application(p_app uuid, p_reason text)
returns applications language plpgsql security definer as $$
declare a applications;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update applications set state = 'rejected', reason = p_reason,
    decided_by = current_account_id(), decided_at = now()
  where id = p_app returning * into a;
  update account_registration set overall_state = 'rejected' where account_id = a.account_id;
  return a;
end $$;

-- revealing a contact spends one lead credit, atomically
create or replace function reveal_contact(p_requirement uuid, p_product uuid)
returns text language plpgsql security definer as $$
declare acct uuid := current_account_id(); remaining int; target text;
begin
  select sum(granted - used) into remaining from lead_credits
   where account_id = acct and (expires_on is null or expires_on >= current_date);
  if coalesce(remaining, 0) < 1 then raise exception 'no lead credits remaining'; end if;

  insert into contact_reveals (account_id, requirement_id, product_id)
  values (acct, p_requirement, p_product) on conflict do nothing;

  update lead_credits set used = used + 1
   where id = (select id from lead_credits where account_id = acct
               and granted > used and (expires_on is null or expires_on >= current_date)
               order by expires_on nulls last limit 1);

  if p_requirement is not null then
    select a.phone into target from requirements r join accounts a on a.id = r.buyer_id where r.id = p_requirement;
  else
    select a.phone into target from products p join accounts a on a.id = p.supplier_id where p.id = p_product;
  end if;
  return target;
end $$;

-- distance in km between two districts, for buy-lead radius filtering
create or replace function district_km(a text, b text) returns numeric
language sql stable as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(d2.lat - d1.lat) / 2), 2) +
    cos(radians(d1.lat)) * cos(radians(d2.lat)) *
    power(sin(radians(d2.lng - d1.lng) / 2), 2)))
  from districts d1, districts d2 where d1.id = a and d2.id = b;
$$;

-- buy leads for the calling supplier, honouring its own preferences
create or replace function my_buy_leads()
returns setof requirements language sql stable security definer as $$
  with pref as (select * from lead_preferences where account_id = current_account_id()),
       mine as (select category_id from account_categories where account_id = current_account_id())
  select r.* from requirements r, pref
  where r.state = 'open'
    and r.buyer_id <> current_account_id()
    and (r.category_id is null or r.category_id in (select category_id from mine))
    and (pref.min_value is null or coalesce(r.estimated_value, 0) >= pref.min_value)
    and (pref.nationwide
         or r.district_id = any (pref.districts)
         or exists (select 1 from unnest(pref.districts) d
                    where district_km(d, r.district_id) <= pref.radius_km))
  order by r.created_at desc;
$$;

-- public storefront view: safe columns only, verified suppliers only
create or replace view public_suppliers as
select a.id, a.company, a.trade_name, a.initials, a.business_type, a.tier, a.district_id,
       a.about, a.coverage, a.nature_of_business, a.brands, a.incorporated_on,
       r.overall_state as verification_state
from accounts a join account_registration r on r.account_id = a.id
where a.role = 'supplier' and r.overall_state = 'verified';

-- offers per product: what the marketplace product page lists
create or replace view product_offers as
select p.id as product_id, p.name, a.id as supplier_id, a.company as supplier,
       a.district_id, p.price, p.moq, p.unit, p.rating,
       (r.overall_state = 'verified') as verified,
       extract(year from age(now(), a.created_at))::int as years_on_platform
from products p
join accounts a on a.id = p.supplier_id
join account_registration r on r.account_id = a.id
where p.status = 'published';

-- catalogue analytics the supplier dashboard reads
create or replace view supplier_catalog_stats as
select p.supplier_id, count(*) as listings, sum(p.view_count) as views,
       sum(p.order_count) as orders,
       count(*) filter (where p.status = 'published') as active,
       count(*) filter (where p.status <> 'published') as inactive
from products p group by p.supplier_id;
