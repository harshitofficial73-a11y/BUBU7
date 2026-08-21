-- BUBU.Market · row level security
-- Every table is closed by default; a supplier must never read another supplier's
-- leads, orders, conversations or documents.

create or replace function current_account_id() returns uuid
language sql stable security definer as $$
  select id from accounts where auth_user_id = auth.uid()
  union all
  select account_id from account_users where auth_user_id = auth.uid()
  limit 1;
$$;

create or replace function current_role_name() returns account_role
language sql stable security definer as $$
  select role from accounts where id = current_account_id();
$$;

create or replace function is_admin() returns boolean
language sql stable security definer as $$
  select coalesce(current_role_name() = 'admin', false);
$$;

do $$ declare t text;
begin
  for t in select unnest(array['accounts','account_registration','account_categories','account_users','addresses',
    'payout_methods','handsets','products','product_specs','media','documents','requirements','quotes',
    'quote_attachments','lead_credits','contact_reveals','lead_preferences','orders','order_lines','payments',
    'invoices','subscriptions','disputes','dispute_evidence','conversations','messages','applications',
    'notification_prefs','audit_log'])
  loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- reference data is world readable
alter table districts enable row level security;
alter table categories enable row level security;
alter table fee_rules enable row level security;
create policy districts_read  on districts  for select using (true);
create policy categories_read on categories for select using (true);
create policy fee_rules_read  on fee_rules  for select using (active);

-- accounts: own record, plus public columns of verified suppliers
create policy accounts_self on accounts for select
  using (id = current_account_id() or is_admin()
         or (role = 'supplier' and exists (
              select 1 from account_registration r
              where r.account_id = accounts.id and r.overall_state = 'verified')));
create policy accounts_update_self on accounts for update
  using (id = current_account_id()) with check (id = current_account_id());
create policy accounts_admin_all on accounts for all using (is_admin());

create policy registration_self on account_registration for select
  using (account_id = current_account_id() or is_admin());
create policy registration_write_self on account_registration for update
  using (account_id = current_account_id()) with check (account_id = current_account_id());
create policy registration_admin on account_registration for all using (is_admin());

-- owned-row tables: one policy shape, applied per table
do $$ declare t text;
begin
  for t in select unnest(array['account_categories','account_users','addresses','payout_methods','handsets',
    'lead_credits','contact_reveals','lead_preferences','documents','notification_prefs'])
  loop
    execute format($f$
      create policy %1$s_own on %1$I for all
        using (account_id = current_account_id() or is_admin())
        with check (account_id = current_account_id() or is_admin());
    $f$, t);
  end loop;
end $$;

-- products: published listings are public, drafts are the supplier's own
create policy products_public on products for select
  using (status = 'published' or supplier_id = current_account_id() or is_admin());
create policy products_own_write on products for all
  using (supplier_id = current_account_id() or is_admin())
  with check (supplier_id = current_account_id() or is_admin());

create policy specs_read on product_specs for select
  using (exists (select 1 from products p where p.id = product_id
                 and (p.status = 'published' or p.supplier_id = current_account_id() or is_admin())));
create policy specs_write on product_specs for all
  using (exists (select 1 from products p where p.id = product_id and p.supplier_id = current_account_id()) or is_admin())
  with check (exists (select 1 from products p where p.id = product_id and p.supplier_id = current_account_id()) or is_admin());

create policy media_read on media for select
  using (approved or account_id = current_account_id() or is_admin());
create policy media_write on media for all
  using (account_id = current_account_id() or is_admin())
  with check (account_id = current_account_id() or is_admin());

-- requirements: the buyer owns them; suppliers read open ones matching their categories
create policy requirements_buyer on requirements for all
  using (buyer_id = current_account_id() or is_admin())
  with check (buyer_id = current_account_id() or is_admin());
create policy requirements_supplier_read on requirements for select
  using (state = 'open' and current_role_name() = 'supplier'
         and (category_id is null or exists (
              select 1 from account_categories ac
              where ac.account_id = current_account_id() and ac.category_id = requirements.category_id)));

-- quotes: visible to the quoting supplier and the requirement's buyer
create policy quotes_parties on quotes for select
  using (supplier_id = current_account_id() or is_admin()
         or exists (select 1 from requirements r where r.id = requirement_id and r.buyer_id = current_account_id()));
create policy quotes_supplier_write on quotes for all
  using (supplier_id = current_account_id() or is_admin())
  with check (supplier_id = current_account_id() or is_admin());
create policy quote_files on quote_attachments for all
  using (exists (select 1 from quotes q where q.id = quote_id and q.supplier_id = current_account_id()) or is_admin())
  with check (exists (select 1 from quotes q where q.id = quote_id and q.supplier_id = current_account_id()) or is_admin());

-- orders and money: both parties, admin
create policy orders_parties on orders for select
  using (buyer_id = current_account_id() or supplier_id = current_account_id() or is_admin());
create policy orders_buyer_insert on orders for insert
  with check (buyer_id = current_account_id());
create policy orders_parties_update on orders for update
  using (buyer_id = current_account_id() or supplier_id = current_account_id() or is_admin());

create policy lines_parties on order_lines for select
  using (exists (select 1 from orders o where o.id = order_id
                 and (o.buyer_id = current_account_id() or o.supplier_id = current_account_id() or is_admin())));
create policy payments_parties on payments for select
  using (exists (select 1 from orders o where o.id = order_id
                 and (o.buyer_id = current_account_id() or o.supplier_id = current_account_id() or is_admin())));
create policy invoices_own on invoices for select
  using (account_id = current_account_id() or is_admin());
create policy subscriptions_own on subscriptions for select
  using (account_id = current_account_id() or is_admin());

-- disputes: parties may read and raise; only admin may resolve
create policy disputes_parties on disputes for select
  using (is_admin() or exists (select 1 from orders o where o.id = order_id
         and (o.buyer_id = current_account_id() or o.supplier_id = current_account_id())));
create policy disputes_raise on disputes for insert
  with check (raised_by = current_account_id());
create policy disputes_admin_resolve on disputes for update using (is_admin());
create policy evidence_parties on dispute_evidence for all
  using (is_admin() or exists (select 1 from disputes d join orders o on o.id = d.order_id
         where d.id = dispute_id and (o.buyer_id = current_account_id() or o.supplier_id = current_account_id())))
  with check (true);

-- conversations and messages: the two parties only
create policy conversations_parties on conversations for all
  using (supplier_id = current_account_id() or buyer_id = current_account_id() or is_admin())
  with check (supplier_id = current_account_id() or buyer_id = current_account_id());
create policy messages_parties on messages for all
  using (exists (select 1 from conversations c where c.id = conversation_id
                 and (c.supplier_id = current_account_id() or c.buyer_id = current_account_id() or is_admin())))
  with check (exists (select 1 from conversations c where c.id = conversation_id
                 and (c.supplier_id = current_account_id() or c.buyer_id = current_account_id())));

-- applications: own, or any for admin
create policy applications_own on applications for select
  using (account_id = current_account_id() or is_admin());
create policy applications_submit on applications for insert
  with check (account_id = current_account_id());
create policy applications_admin on applications for update using (is_admin());

create policy audit_admin on audit_log for select using (is_admin());
