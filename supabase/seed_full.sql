-- BUBU.Market · full seed data
--
-- Everything needed to exercise the platform: districts, 22 categories, five
-- supplier businesses, four buyers, one operations account, product catalogues with
-- photos, buyer requirements, quotes, orders with escrow, conversations, a dispute,
-- an application awaiting verification, invoices and fee rules.
--
-- Run AFTER 0001_schema.sql, 0002_rls.sql and 0003_functions.sql.
-- Replaces seed.sql, seed_admin.sql and seed_test_logins.sql — run this one instead.
-- Safe to re-run: every insert is keyed and upserts.
--
-- ── Logins (all password Bubu@2026) ────────────────────────────────────────
--   harshit@bubumarket.com   admin
--   ivan@bubu.market         supplier   Ivan Trading Company Limited
--   moses@khd.co.ug          supplier   Kampala Hardware Depot Limited
--   denis@nilegrain.co.ug    supplier   Nile Grain and Produce Limited
--   peter@namanve.co.ug      supplier   Namanve Construction Supplies Limited
--   aisha@medisure.co.ug     supplier   Medisure Wholesale Limited
--   ayabare@bubu.market      buyer      Ayabare Construction Limited
--   grace@nakawa.co.ug       buyer      Nakawa Trading Co. Limited
--   peter@nsambya.co.ug      buyer      Nsambya Hospital Supplies Limited
--   irene@seeta.co.ug        buyer      Seeta Housing Developments Limited
--
-- Two dashboard settings or sign-in fails:
--   Authentication → Providers → Email: enabled, "Confirm email" OFF
--   Authentication → Policies → Minimum password length: 6 (the default is fine)
--
-- Product photos: this seed stores paths under the `media` bucket, e.g.
-- products/cement-32-5n.png. Upload your images to those paths, or replace the
-- storage_path values with any public URL — the app renders a placeholder tile
-- until a file exists, so nothing breaks in the meantime.

create extension if not exists "pgcrypto";

-- ═══════════════════════════════════════════════════════ reference data

insert into districts (id, name, region, lat, lng) values
  ('kampala','Kampala','Central',0.34760,32.58250),
  ('wakiso','Wakiso','Central',0.40440,32.45940),
  ('mukono','Mukono','Central',0.35330,32.75530),
  ('entebbe','Entebbe','Central',0.05120,32.46330),
  ('jinja','Jinja','Eastern',0.42440,33.20420),
  ('mbale','Mbale','Eastern',1.06440,34.17970),
  ('soroti','Soroti','Eastern',1.71460,33.61110),
  ('lira','Lira','Northern',2.23500,32.90970),
  ('gulu','Gulu','Northern',2.77460,32.29900),
  ('arua','Arua','Northern',3.02010,30.91100),
  ('masindi','Masindi','Western',1.67440,31.71500),
  ('mbarara','Mbarara','Western',-0.60720,30.65450),
  ('fort-portal','Fort Portal','Western',0.65400,30.27500),
  ('kasese','Kasese','Western',0.18330,30.08810),
  ('kabale','Kabale','Western',-1.24830,29.98990),
  ('kiryandongo','Kiryandongo','Western',1.87000,32.07000)
on conflict (id) do update set name = excluded.name, region = excluded.region;

insert into categories (id, name, sort) values
  ('building-construction','Building & construction',1),
  ('cement-aggregates','Cement & aggregates',2),
  ('steel-metal','Steel & metal',3),
  ('roofing-ceilings','Roofing & ceilings',4),
  ('hardware-tools','Hardware & tools',5),
  ('electrical-lighting','Electrical & lighting',6),
  ('plumbing-sanitary','Plumbing & sanitary',7),
  ('paints-finishes','Paints & finishes',8),
  ('agriculture-produce','Agriculture & produce',9),
  ('agro-inputs-seeds','Agro inputs & seeds',10),
  ('livestock-feeds','Livestock & feeds',11),
  ('food-beverage','Food & beverage wholesale',12),
  ('packaging','Packaging',13),
  ('chemicals-industrial','Chemicals & industrial',14),
  ('medical-supplies','Medical supplies',15),
  ('electronics','Electronics',16),
  ('solar-power','Solar & power',17),
  ('auto-parts','Auto parts',18),
  ('furniture-fittings','Furniture & fittings',19),
  ('textiles-apparel','Textiles & apparel',20),
  ('stationery-printing','Stationery & printing',21),
  ('cleaning-hygiene','Cleaning & hygiene',22)
on conflict (id) do update set name = excluded.name, sort = excluded.sort;

insert into fee_rules (name, applies_to, rate, minimum, payer, note) values
  ('Standard escrow commission','all_orders',0.0150,5000,'supplier','1.5% of order value'),
  ('Export order commission','export',0.0320,12000,'supplier','Cross-border, includes documentation desk'),
  ('Industry leader listing','tier',null,null,'supplier','UGX 1,200,000 per year, 40 lead credits'),
  ('Star supplier listing','tier',null,null,'supplier','UGX 640,000 per year, 18 lead credits'),
  ('Buy lead credit','all_orders',null,12000,'supplier','Per contact revealed')
on conflict do nothing;

-- ═══════════════════════════════════════════════════════ accounts

do $$
declare
  r      record;
  v_uid  uuid;
  v_acct uuid;
  v_pw   text := 'Bubu@2026';
begin
  for r in
    select * from (values
      -- email, role, biztype, tier, company, trade, initials, person, title, phone, district, ursb, tin, licence, about, coverage, nature, staff, turnover, brands
      ('harshit@bubumarket.com','admin',null,'free','BUBU.Market Uganda Limited','Platform operations','BA','Harshit','Verification lead','+256800218400','kampala','80020000000001','1000000001','KCCA/TL/2026/00001',null,null,null,null,null,null),

      ('ivan@bubu.market','supplier','trader','star_supplier','Ivan Trading Company Limited','Ivan Trading','IT','Ivan Ssekandi','Managing director','+256772100201','kampala','80020007712045','1005512340','KCCA/TL/2026/07721',
       'Wholesale supply of building materials, hardware and fasteners across central Uganda.','Kampala, Wakiso and Mukono · 4 trucks','Wholesale of construction materials and hardware','18 permanent, 8 casual','UGX 3.2bn, financial year 2025','Tororo Cement, Roofings Group'),

      ('moses@khd.co.ug','supplier','trader','industry_leader','Kampala Hardware Depot Limited','KH Depot','KH','Moses Kagimu','Director','+256772415908','kampala','80020003456789','1002938475','KCCA/TL/2026/44120',
       'Wholesale distributor of cement, steel reinforcement, roofing and hardware.','Kampala, Wakiso, Mukono · 6 trucks','Wholesale of cement, steel reinforcement and roofing','34 permanent, 12 casual','UGX 8.4bn, financial year 2025','Tororo Cement, Roofings Group, Steel and Tube'),

      ('denis@nilegrain.co.ug','supplier','manufacturer','industry_leader','Nile Grain and Produce Limited','Nile Grain','NG','Denis Okot','General manager','+256774552013','lira','80020004417755','1003882140','LMC/TL/2026/00921',
       'Grain aggregation, cleaning and milling with own stores in Lira and Kiryandongo.','Northern and central Uganda · 9 trucks','Grain aggregation, cleaning and edible oil pressing','48 permanent, 60 seasonal','UGX 9.6bn, financial year 2025','Nile Grain own brand'),

      ('peter@namanve.co.ug','supplier','manufacturer','industry_leader','Namanve Construction Supplies Limited','Namanve Construction','NC','Peter Ssemakula','Operations director','+256776812340','mukono','80020008841207','1007244810','MMC/TL/2026/01184',
       'Aggregates, ready-mix concrete, blocks and formwork for contractors.','Kampala, Wakiso, Mukono, Jinja · 14 tippers and 4 mixers','Quarrying and ready-mix concrete production','62 permanent, 40 casual','UGX 11.8bn, financial year 2025','Own quarry output, Tororo Cement'),

      ('aisha@medisure.co.ug','supplier','trader','star_supplier','Medisure Wholesale Limited','Medisure Wholesale','MS','Aisha Nakiwala','Pharmacy director','+256772884110','kampala','80020011552308','1009446721','NDA/WHS/2026/00612',
       'Wholesale of examination gloves, protective equipment and clinical consumables.','Nationwide · courier to regional referral hospitals','Wholesale of medical and protective equipment','19 permanent, 6 casual','UGX 5.1bn, financial year 2025','Medisure own brand, Hartmann, Ansell'),

      ('ayabare@bubu.market','buyer',null,'free','Ayabare Construction Limited','Ayabare','AC','Grace Ayabare','Procurement lead','+256772100202','wakiso','80020007712046','1005512341','WDC/TL/2026/03318',null,null,null,null,null,null),
      ('grace@nakawa.co.ug','buyer',null,'free','Nakawa Trading Co. Limited','Nakawa Trading','NT','Grace Nakato','Procurement lead','+256772903445','kampala','80020002884411','1002664201','KCCA/TL/2026/33017',null,null,null,null,null,null),
      ('peter@nsambya.co.ug','buyer',null,'free','Nsambya Hospital Supplies Limited','Nsambya Hospital','NH','Peter Wasswa','Procurement officer','+256752664209','kampala','80020012288417','1010773204','KCCA/TL/2026/61204',null,null,null,null,null,null),
      ('irene@seeta.co.ug','buyer',null,'free','Seeta Housing Developments Limited','Seeta Housing','SH','Irene Amongi','Project procurement manager','+256788314076','mukono','80020009917744','1006612094','MMC/TL/2026/00884',null,null,null,null,null,null)
    ) as t(email, role, biztype, tier, company, trade, initials, person, title, phone, district,
           ursb, tin, licence, about, coverage, nature, staff, turnover, brands)
  loop
    select id into v_uid from auth.users where lower(email) = lower(r.email);
    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
      values (v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        r.email, crypt(v_pw, gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', r.person, 'role', r.role), now(), now());
    else
      update auth.users set encrypted_password = crypt(v_pw, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
       where id = v_uid;
    end if;

    select id into v_acct from accounts
     where auth_user_id = v_uid or phone = r.phone or lower(email) = lower(r.email) limit 1;

    if v_acct is null then
      insert into accounts (auth_user_id, role, business_type, tier, company, trade_name, initials,
        phone, email, address, district_id, incorporated_on, about, coverage, nature_of_business,
        staff_count, turnover, brands, spend_12m, supplier_count)
      values (v_uid, r.role::account_role, r.biztype::business_type, r.tier::membership_tier,
        r.company, r.trade, r.initials, r.phone, r.email,
        case r.district when 'kampala' then 'Plot 24, Sixth Street, Industrial Area'
                        when 'lira' then 'Plot 9, Aputi Road, Lira Industrial Area'
                        when 'mukono' then 'Plot 210, Namanve Industrial Park'
                        else 'Plot 8, Kira Road' end,
        r.district, date '2019-06-01', r.about, r.coverage, r.nature,
        r.staff, r.turnover, r.brands,
        case when r.role = 'buyer' then 214000000 else 0 end,
        case when r.role = 'buyer' then 12 else 0 end)
      returning id into v_acct;
    else
      update accounts set auth_user_id = v_uid, role = r.role::account_role,
        business_type = r.biztype::business_type, tier = r.tier::membership_tier,
        company = r.company, trade_name = r.trade, initials = r.initials, email = r.email,
        district_id = r.district, about = r.about, coverage = r.coverage,
        nature_of_business = r.nature, staff_count = r.staff, turnover = r.turnover,
        brands = r.brands, updated_at = now()
       where id = v_acct;
    end if;

    if not exists (select 1 from account_users where auth_user_id = v_uid) then
      insert into account_users (account_id, auth_user_id, full_name, role_title, phone,
        can_post, can_accept, can_release, can_billing)
      values (v_acct, v_uid, r.person, r.title, r.phone, true, true, true, true);
    end if;

    insert into account_registration (account_id, ursb_number, tin, trading_licence,
      licence_authority, licence_expires_on, director_nin,
      overall_state, ursb_state, tin_state, licence_state, nin_state, verified_at)
    values (v_acct, r.ursb, r.tin, r.licence,
      case r.district when 'kampala' then 'KCCA' when 'mukono' then 'Mukono MC'
                      when 'lira' then 'Lira MC' else 'Wakiso DLG' end,
      date '2026-12-31',
      'CM' || lpad((random() * 89999999 + 10000000)::int::text, 8, '0') || 'AB1C',
      'verified','verified','verified','verified','verified', now())
    on conflict (account_id) do update set overall_state = 'verified', verified_at = now();

    if r.role = 'supplier' then
      insert into lead_credits (account_id, granted, expires_on)
      select v_acct, case r.tier when 'industry_leader' then 40 else 18 end, current_date + interval '1 year'
       where not exists (select 1 from lead_credits where account_id = v_acct);

      insert into lead_preferences (account_id, districts, radius_km)
      values (v_acct, array[r.district], 60) on conflict (account_id) do nothing;

      insert into subscriptions (account_id, tier, price, lead_credits, starts_on, ends_on)
      select v_acct, r.tier::membership_tier,
        case r.tier when 'industry_leader' then 1200000 else 640000 end,
        case r.tier when 'industry_leader' then 40 else 18 end,
        current_date - interval '3 months', current_date + interval '9 months'
       where not exists (select 1 from subscriptions where account_id = v_acct);
    end if;

    insert into notification_prefs (account_id, topic, email, sms, app, whatsapp)
    select v_acct, t.topic, t.email, t.sms, true, t.whatsapp
      from (values ('enquiries',true,false,true),('replies',true,false,false),
                   ('followups',true,false,false),('missed_calls',false,true,true),
                   ('lead_alerts',true,true,false),('tenders',false,false,false),
                   ('payouts',true,true,true),('offers',false,false,false)
           ) as t(topic,email,sms,whatsapp)
    on conflict do nothing;
  end loop;
end $$;

-- categories per business
insert into account_categories (account_id, category_id)
select a.id, c.cat from accounts a
join (values
  ('ivan@bubu.market','building-construction'),('ivan@bubu.market','hardware-tools'),
  ('moses@khd.co.ug','building-construction'),('moses@khd.co.ug','cement-aggregates'),
  ('moses@khd.co.ug','steel-metal'),('moses@khd.co.ug','roofing-ceilings'),
  ('denis@nilegrain.co.ug','agriculture-produce'),('denis@nilegrain.co.ug','food-beverage'),
  ('denis@nilegrain.co.ug','packaging'),
  ('peter@namanve.co.ug','cement-aggregates'),('peter@namanve.co.ug','building-construction'),
  ('aisha@medisure.co.ug','medical-supplies'),('aisha@medisure.co.ug','cleaning-hygiene'),
  ('ayabare@bubu.market','building-construction'),('ayabare@bubu.market','cement-aggregates'),
  ('grace@nakawa.co.ug','building-construction'),('grace@nakawa.co.ug','steel-metal'),
  ('peter@nsambya.co.ug','medical-supplies'),
  ('irene@seeta.co.ug','building-construction'),('irene@seeta.co.ug','roofing-ceilings')
) as c(email, cat) on lower(a.email) = c.email
on conflict do nothing;

-- delivery addresses for buyers
insert into addresses (account_id, label, street, district_id, contact, phone, is_default)
select a.id, x.label, x.street, x.district, a.company, a.phone, x.def
  from accounts a
  join (values
    ('grace@nakawa.co.ug','Head office and main store','Plot 12, Ntinda Industrial Area','kampala',true),
    ('grace@nakawa.co.ug','Kyanja site store','Kyanja Ring Road','wakiso',false),
    ('ayabare@bubu.market','Site office','Plot 8, Kira Road','wakiso',true),
    ('peter@nsambya.co.ug','Central stores','Nsambya Hill, Makindye','kampala',true),
    ('irene@seeta.co.ug','Seeta phase two site','Seeta, Mukono municipality','mukono',true)
  ) as x(email, label, street, district, def) on lower(a.email) = x.email
on conflict do nothing;

-- payout methods for suppliers
insert into payout_methods (account_id, method, detail, state, is_default)
select a.id, x.m::payment_method, x.detail, 'verified', x.def
  from accounts a
  join (values
    ('ivan@bubu.market','mtn_momo','+256 772 100 201',true),
    ('moses@khd.co.ug','mtn_momo','+256 772 415 908',true),
    ('moses@khd.co.ug','bank_transfer','Stanbic ••4417',false),
    ('denis@nilegrain.co.ug','airtel_money','+256 774 552 013',true),
    ('peter@namanve.co.ug','bank_transfer','Centenary ••8820',true),
    ('aisha@medisure.co.ug','mtn_momo','+256 772 884 110',true)
  ) as x(email, m, detail, def) on lower(a.email) = x.email
on conflict do nothing;

-- linked handsets on the BUBU virtual number
insert into handsets (account_id, phone, owner_label, office_hours, after_hours, verified_at)
select a.id, a.phone, u.full_name || ', ' || coalesce(u.role_title,'contact'), true, true, now()
  from accounts a join account_users u on u.account_id = a.id
 where a.role = 'supplier'
on conflict do nothing;

-- ═══════════════════════════════════════════════════════ products

insert into products (supplier_id, name, category_id, family, description, price, unit, moq,
                      brand, status, rating, order_count, view_count)
select a.id, p.name, p.cat, p.family, p.descr, p.price, p.unit, p.moq, p.brand, 'published',
       p.rating, p.orders, p.views
  from accounts a
  join (values
    -- Kampala Hardware Depot
    ('moses@khd.co.ug','Tororo Portland Cement 32.5N, 50kg','cement-aggregates','Bagged cement',
     'Ordinary Portland cement, strength class 32.5N, 50kg paper sack, delivered palletised. Certified to US EAS 18-1.',
     33500,'bag',50,'Tororo Cement',4.7,412,1284),
    ('moses@khd.co.ug','Deformed steel bar Y12, 12m','steel-metal','Reinforcement',
     'High yield deformed reinforcement bar, 12mm diameter, 12 metre lengths, rolled to BS 4449 grade 500. Mill certificates on request.',
     62000,'bar',25,'Steel and Tube',4.6,268,842),
    ('moses@khd.co.ug','Pre-painted roofing sheet, 30 gauge','roofing-ceilings','Roofing',
     'Pre-painted galvanised iron sheet, 30 gauge, 2m to 4m lengths cut to order.',
     48500,'sheet',20,'Roofings Group',4.5,174,596),
    ('moses@khd.co.ug','Binding wire 16 gauge','steel-metal','Reinforcement',
     'Soft annealed binding wire, 16 gauge, supplied in 20kg coils.',
     9200,'kg',50,'Steel and Tube',4.4,92,281),
    -- Ivan Trading
    ('ivan@bubu.market','Cordless impact drill 18V, two batteries','hardware-tools','Power tools',
     'Brushless cordless impact drill supplied with two 4.0Ah batteries, charger and carry case. One year warranty.',
     385000,'unit',5,'Ingco',4.6,196,712),
    ('ivan@bubu.market','Angle grinder 900W','hardware-tools','Power tools',
     'Angle grinder, 900W, 115mm disc, side handle and guard included.',
     185000,'unit',5,'Total Tools',4.4,142,468),
    ('ivan@bubu.market','Drill bit set, 19 pieces','hardware-tools','Accessories',
     'HSS twist drill bit set, 1mm to 10mm, 19 pieces in a metal index case.',
     46000,'set',10,'Bosch',4.5,118,332),
    ('ivan@bubu.market','Galvanised roofing nails 3 inch','hardware-tools','Fasteners',
     'Galvanised roofing nails with rubber washer, 3 inch, supplied in 25kg boxes.',
     14500,'kg',25,null,4.3,86,214),
    -- Nile Grain
    ('denis@nilegrain.co.ug','White maize grain, grade 1','agriculture-produce','Grain and pulses',
     'Grade 1 white maize, 13.5% moisture, machine cleaned and aflatoxin tested. Packed in 100kg woven bags.',
     1450,'kg',1000,'Nile Grain',4.6,442,1102),
    ('denis@nilegrain.co.ug','Refined sunflower oil, 20L jerrycan','food-beverage','Edible oils',
     'Double refined sunflower cooking oil in 20 litre food grade jerrycans, UNBS certified.',
     138000,'jerrycan',10,'Nile Grain',4.7,318,864),
    ('denis@nilegrain.co.ug','Sesame seed, hulled','agriculture-produce','Oilseeds',
     'Hulled white sesame, 99% purity, machine cleaned, export grade.',
     5900,'kg',500,'Nile Grain',4.5,244,612),
    ('denis@nilegrain.co.ug','Beans, yellow long','agriculture-produce','Grain and pulses',
     'Yellow long beans, hand sorted, 13% moisture, packed in 100kg bags.',
     3700,'kg',500,null,4.4,196,438),
    ('denis@nilegrain.co.ug','Robusta coffee, screen 15','agriculture-produce','Coffee',
     'Washed Robusta, screen 15, moisture 12.5%, UCDA graded for export.',
     9800,'kg',300,'Nile Grain',4.8,128,392),
    ('denis@nilegrain.co.ug','Woven polypropylene bags, 100kg','packaging','Bags and sacks',
     'Woven polypropylene sacks, 100kg capacity, printed to order.',
     1250,'bag',500,null,4.3,142,266),
    -- Namanve Construction
    ('peter@namanve.co.ug','Ready-mix concrete C25','cement-aggregates','Ready-mix',
     'Design mix C25 ready-mix concrete batched at Namanve, delivered by truck mixer with slump test at the gate.',
     465000,'m3',2,null,4.7,164,528),
    ('peter@namanve.co.ug','Aggregate 3/4 inch, crushed stone','cement-aggregates','Aggregates',
     'Washed crushed stone, 3/4 inch nominal, delivered by 10 or 20 tonne tipper.',
     78000,'tonne',10,null,4.6,286,742),
    ('peter@namanve.co.ug','Lake sand, washed','cement-aggregates','Aggregates',
     'Washed lake sand, low silt content, suitable for plaster and screed.',
     62000,'tonne',10,null,4.5,214,596),
    ('peter@namanve.co.ug','Solid concrete block 9 inch','building-construction','Masonry',
     'Solid concrete block, 450 × 225 × 225mm, cured 14 days before dispatch.',
     4300,'block',500,null,4.6,332,818),
    ('peter@namanve.co.ug','Hardcore, quarry run','cement-aggregates','Aggregates',
     'Quarry run hardcore for foundations and hardstanding, delivered by tipper.',
     48000,'tonne',10,null,4.3,148,364),
    ('peter@namanve.co.ug','Steel formwork panel, 1200x600','building-construction','Formwork',
     'Steel formwork panel, 1200 × 600mm, reusable, with pins and wedges.',
     210000,'panel',10,null,4.4,96,248),
    -- Medisure
    ('aisha@medisure.co.ug','Nitrile examination gloves, box of 100','medical-supplies','Gloves',
     'Powder free nitrile examination gloves, box of 100, sizes S to XL. NDA registered.',
     41000,'box',20,'Ansell',4.7,404,1046),
    ('aisha@medisure.co.ug','Face shield, protective isolation','medical-supplies','Protective equipment',
     'Anti-fog polycarbonate face shield with foam brow and elastic strap.',
     6800,'unit',100,'Medisure',4.6,286,714),
    ('aisha@medisure.co.ug','Medical scrubs set, unisex','medical-supplies','Workwear',
     'Unisex scrub top and trouser set, poly-cotton, sizes XS to XXL.',
     62000,'set',20,'Medisure',4.5,232,588),
    ('aisha@medisure.co.ug','Surgical masks 3-ply, box of 50','medical-supplies','Protective equipment',
     'Three ply surgical mask with ear loops, box of 50, bacterial filtration above 95%.',
     12400,'box',50,'Medisure',4.4,188,462)
  ) as p(email, name, cat, family, descr, price, unit, moq, brand, rating, orders, views)
    on lower(a.email) = p.email
where not exists (select 1 from products x where x.supplier_id = a.id and x.name = p.name);

-- Product photos. The filenames below match the img/ folder in the deployment
-- package, so upload that folder's contents to the media bucket under products/
-- and every photo resolves. Any product without a mapping shows a placeholder tile.
insert into media (account_id, product_id, kind, storage_path, caption, approved)
select p.supplier_id, p.id, 'product', 'products/' || m.file, p.name, true
  from products p
  join (values
    ('Tororo Portland Cement 32.5N, 50kg','p1-cement.png'),
    ('Deformed steel bar Y12, 12m','p2-steelbar.png'),
    ('Pre-painted roofing sheet, 30 gauge','x-roofing.png'),
    ('Binding wire 16 gauge','x-wire.png'),
    ('Cordless impact drill 18V, two batteries','t-drill.png'),
    ('Angle grinder 900W','t-grinder.png'),
    ('Drill bit set, 19 pieces','t-drillbits.png'),
    ('Galvanised roofing nails 3 inch','x-nails.png'),
    ('White maize grain, grade 1','a-maize-grain.png'),
    ('Refined sunflower oil, 20L jerrycan','p4-oil.png'),
    ('Sesame seed, hulled','a-sesame-hulled.png'),
    ('Beans, yellow long','a-beans-yellow.png'),
    ('Robusta coffee, screen 15','a-coffee-robusta.png'),
    ('Woven polypropylene bags, 100kg','a-woven-bag.png'),
    ('Ready-mix concrete C25','c-sand.png'),
    ('Aggregate 3/4 inch, crushed stone','c-aggregate.png'),
    ('Lake sand, washed','c-sand.png'),
    ('Solid concrete block 9 inch','c-block.png'),
    ('Hardcore, quarry run','c-hardcore.png'),
    ('Steel formwork panel, 1200x600','c-formwork.png'),
    ('Nitrile examination gloves, box of 100','p7-gloves.png'),
    ('Face shield, protective isolation','m-faceshield.png'),
    ('Medical scrubs set, unisex','m-scrubs.png'),
    ('Surgical masks 3-ply, box of 50','p7-gloves.png')
  ) as m(pname, file) on p.name = m.pname
 where not exists (select 1 from media x where x.product_id = p.id);

-- specifications
insert into product_specs (product_id, key, value, sort)
select p.id, s.k, s.v, s.sort from products p
join (values
  ('Tororo Portland Cement 32.5N, 50kg','Strength class','32.5N',1),
  ('Tororo Portland Cement 32.5N, 50kg','Packaging','50kg paper sack',2),
  ('Tororo Portland Cement 32.5N, 50kg','Standard','US EAS 18-1:2017',3),
  ('Deformed steel bar Y12, 12m','Diameter','12 mm',1),
  ('Deformed steel bar Y12, 12m','Standard','BS 4449 grade 500',2),
  ('White maize grain, grade 1','Moisture','13.5%',1),
  ('White maize grain, grade 1','Grade','Grade 1, machine cleaned',2),
  ('Ready-mix concrete C25','Strength class','C25',1),
  ('Ready-mix concrete C25','Slump','75 ± 25 mm',2),
  ('Nitrile examination gloves, box of 100','Material','Nitrile, powder free',1),
  ('Nitrile examination gloves, box of 100','Sizes','S, M, L, XL',2),
  ('Cordless impact drill 18V, two batteries','Voltage','18V',1),
  ('Cordless impact drill 18V, two batteries','Warranty','12 months',2)
) as s(pname, k, v, sort) on p.name = s.pname
on conflict do nothing;

-- registration documents
insert into documents (account_id, kind, issuer, reference, issued_on, expires_on, storage_path, state)
select a.id, d.kind::document_kind, d.issuer,
       case d.kind when 'certificate_of_incorporation' then r.ursb_number
                   when 'ura_tin_certificate' then r.tin
                   else r.trading_licence end,
       date '2019-06-01',
       case when d.kind = 'trading_licence' then date '2026-12-31' else null end,
       'documents/' || a.id || '-' || d.kind || '.pdf', 'verified'
  from accounts a
  join account_registration r on r.account_id = a.id
  join (values ('certificate_of_incorporation','Uganda Registration Services Bureau'),
               ('ura_tin_certificate','Uganda Revenue Authority'),
               ('trading_licence','District local authority')
       ) as d(kind, issuer) on true
 where not exists (select 1 from documents x where x.account_id = a.id and x.kind = d.kind::document_kind);

-- ═══════════════════════════════════════════════════════ demand and trade

-- buyer requirements, which suppliers see as buy leads
insert into requirements (buyer_id, title, category_id, quantity, quantity_unit, specification,
                          purpose, deliver_to, district_id, needed_by, estimated_value,
                          payment_method, state, expires_at)
select a.id, q.title, q.cat, q.qty, q.unit, q.spec, q.purpose, q.deliver, q.district,
       current_date + q.days, q.value, q.pay::payment_method, 'open', now() + interval '14 days'
  from accounts a
  join (values
    ('grace@nakawa.co.ug','Tororo Portland Cement 32.5N, 50kg','cement-aggregates',500,'bags',
     'Grade 32.5N, palletised, offloading required','Business use','Ntinda Industrial Area','kampala',22,16750000,'mtn_momo'),
    ('grace@nakawa.co.ug','Deformed steel bar Y12, 12m','steel-metal',80,'bars',
     'Y12, 12m lengths, mill certificates required','Business use','Kyanja Ring Road','wakiso',12,4960000,'bank_transfer'),
    ('ayabare@bubu.market','Ready-mix concrete C25','cement-aggregates',40,'m3',
     'C25 design mix, pump required on site','Business use','Plot 8, Kira Road','wakiso',9,18600000,'mtn_momo'),
    ('ayabare@bubu.market','Solid concrete block 9 inch','building-construction',3000,'blocks',
     '450 × 225 × 225mm, cured','Business use','Plot 8, Kira Road','wakiso',18,12900000,'bank_transfer'),
    ('peter@nsambya.co.ug','Nitrile examination gloves, box of 100','medical-supplies',4000,'boxes',
     'Powder free, mixed sizes, NDA registered','Business use','Nsambya Hill','kampala',15,164000000,'bank_transfer'),
    ('peter@nsambya.co.ug','Surgical masks 3-ply, box of 50','medical-supplies',2500,'boxes',
     'BFE above 95%','Business use','Nsambya Hill','kampala',20,31000000,'mtn_momo'),
    ('irene@seeta.co.ug','Pre-painted roofing sheet, 30 gauge','roofing-ceilings',900,'sheets',
     '30 gauge, 3m lengths, charcoal grey','Business use','Seeta, Mukono','mukono',25,43650000,'bank_transfer'),
    ('irene@seeta.co.ug','Aggregate 3/4 inch, crushed stone','cement-aggregates',200,'tonnes',
     'Washed, 3/4 inch nominal','Business use','Seeta, Mukono','mukono',11,15600000,'mtn_momo')
  ) as q(email, title, cat, qty, unit, spec, purpose, deliver, district, days, value, pay)
    on lower(a.email) = q.email
where not exists (select 1 from requirements x where x.buyer_id = a.id and x.title = q.title);

-- supplier quotes against those requirements
insert into quotes (requirement_id, supplier_id, unit_price, quantity, lead_time,
                    delivery_terms, validity_days, message, state)
select rq.id, s.id, x.price, x.qty, '48 hours from order', 'Delivered', 10, x.msg, 'sent'
  from (values
    ('Tororo Portland Cement 32.5N, 50kg','moses@khd.co.ug',33500,'500 bags','We hold this stock and can deliver within 48 hours of a confirmed order.'),
    ('Tororo Portland Cement 32.5N, 50kg','ivan@bubu.market',33800,'500 bags','Price includes offloading at site.'),
    ('Deformed steel bar Y12, 12m','moses@khd.co.ug',62000,'80 bars','Mill certificates supplied with delivery.'),
    ('Ready-mix concrete C25','peter@namanve.co.ug',465000,'40 m3','Pump hire available at UGX 900,000 per day.'),
    ('Nitrile examination gloves, box of 100','aisha@medisure.co.ug',41000,'4000 boxes','NDA release documentation included.'),
    ('Pre-painted roofing sheet, 30 gauge','moses@khd.co.ug',48500,'900 sheets','Cut to length at no extra cost.'),
    ('Aggregate 3/4 inch, crushed stone','peter@namanve.co.ug',78000,'200 tonnes','Delivered by 20 tonne tipper, four loads per day.')
  ) as x(title, supplier, price, qty, msg)
  join requirements rq on rq.title = x.title
  join accounts s on lower(s.email) = x.supplier
where not exists (select 1 from quotes q where q.requirement_id = rq.id and q.supplier_id = s.id);

-- orders with escrow at various stages
do $$
declare
  o_id   uuid;
  b_id   uuid;
  s_id   uuid;
  p_id   uuid;
  r      record;
begin
  for r in
    select * from (values
      ('BM-2026-0418','grace@nakawa.co.ug','moses@khd.co.ug','Tororo Portland Cement 32.5N, 50kg',500,'bag',33500,'delivered','released'),
      ('BM-2026-0431','grace@nakawa.co.ug','moses@khd.co.ug','Deformed steel bar Y12, 12m',80,'bar',62000,'in_transit','held'),
      ('BM-2026-0447','ayabare@bubu.market','peter@namanve.co.ug','Solid concrete block 9 inch',3000,'block',4300,'dispatch','held'),
      ('BM-2026-0455','peter@nsambya.co.ug','aisha@medisure.co.ug','Nitrile examination gloves, box of 100',4000,'box',41000,'delivered','released'),
      ('BM-2026-0462','irene@seeta.co.ug','peter@namanve.co.ug','Aggregate 3/4 inch, crushed stone',200,'tonne',78000,'funded','held'),
      ('BM-2026-0470','ayabare@bubu.market','ivan@bubu.market','Cordless impact drill 18V, two batteries',12,'unit',385000,'pending_payment','none')
    ) as t(ref, buyer, supplier, product, qty, unit, price, state, escrow)
  loop
    if exists (select 1 from orders where reference = r.ref) then continue; end if;

    select id into b_id from accounts where lower(email) = r.buyer;
    select id into s_id from accounts where lower(email) = r.supplier;
    select id into p_id from products where name = r.product and supplier_id = s_id;

    insert into orders (reference, buyer_id, supplier_id, subtotal, vat_rate, vat, total,
      deliver_to, district_id, state, escrow_state, funded_at, dispatched_at, delivered_at, released_at)
    values (r.ref, b_id, s_id, r.qty * r.price, 0.180,
      round(r.qty * r.price * 0.18), round(r.qty * r.price * 1.18),
      (select address from accounts where id = b_id),
      (select district_id from accounts where id = b_id),
      r.state::order_state, r.escrow::escrow_state,
      case when r.escrow <> 'none' then now() - interval '9 days' else null end,
      case when r.state in ('in_transit','delivered','closed') then now() - interval '6 days' else null end,
      case when r.state = 'delivered' then now() - interval '3 days' else null end,
      case when r.escrow = 'released' then now() - interval '1 day' else null end)
    returning id into o_id;

    insert into order_lines (order_id, product_id, name, quantity, unit, unit_price, line_total)
    values (o_id, p_id, r.product, r.qty, r.unit, r.price, r.qty * r.price);

    if r.escrow <> 'none' then
      insert into payments (order_id, method, payer_phone, amount, provider_ref, state, settled_at)
      values (o_id, 'mtn_momo', (select phone from accounts where id = b_id),
        round(r.qty * r.price * 1.18), 'MP260819.' || substr(md5(r.ref), 1, 6),
        'success', now() - interval '9 days');
    end if;

    if r.state = 'delivered' then
      insert into invoices (account_id, order_id, number, kind, subtotal, vat, total, efris_fdn, storage_path)
      values (b_id, o_id, 'BUBU-INV-' || substr(r.ref, 4), 'tax',
        r.qty * r.price, round(r.qty * r.price * 0.18), round(r.qty * r.price * 1.18),
        '0326' || substr(md5(r.ref), 1, 12), 'documents/' || r.ref || '-invoice.pdf');
    end if;
  end loop;
end $$;

-- one open dispute, so the admin console has something to resolve
insert into disputes (order_id, raised_by, claim, amount_held, state)
select o.id, o.buyer_id, 'Short delivery, 40 bags missing against the delivery note',
       round(o.total * 0.08), 'open'
  from orders o
 where o.reference = 'BM-2026-0431'
   and not exists (select 1 from disputes d where d.order_id = o.id);

-- conversations and messages between the trading parties
do $$
declare c_id uuid; r record;
begin
  for r in
    select rq.id as req, rq.buyer_id, q.supplier_id, rq.title
      from requirements rq join quotes q on q.requirement_id = rq.id
  loop
    select id into c_id from conversations
     where supplier_id = r.supplier_id and buyer_id = r.buyer_id and requirement_id = r.req;

    if c_id is null then
      insert into conversations (supplier_id, buyer_id, requirement_id, labels, last_message_at)
      values (r.supplier_id, r.buyer_id, r.req, array['Hot lead'], now() - interval '2 hours')
      returning id into c_id;

      insert into messages (conversation_id, sender_id, direction, channel, body, sent_at, read_at) values
        (c_id, r.buyer_id, 'in', 'app',
         'We need ' || r.title || ' delivered to site. What is your best price and lead time?',
         now() - interval '1 day', now() - interval '23 hours'),
        (c_id, r.supplier_id, 'out', 'app',
         'We hold this stock and can deliver within 48 hours of a confirmed order. Formal quote is on its way through BUBU.',
         now() - interval '22 hours', now() - interval '21 hours'),
        (c_id, r.buyer_id, 'in', 'app',
         'Please send the quote addressed to our procurement lead.',
         now() - interval '2 hours', null);
    end if;
  end loop;
end $$;

-- one application awaiting verification, so the admin queue is not empty
do $$
declare v_uid uuid; v_acct uuid;
begin
  if not exists (select 1 from accounts where lower(email) = 'sales@lugazisteel.co.ug') then
    select id into v_uid from auth.users where lower(email) = 'sales@lugazisteel.co.ug';

    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
      values (v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'sales@lugazisteel.co.ug', crypt('Bubu@2026', gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Sarah Nabbosa","role":"supplier"}'::jsonb, now(), now());
    end if;

    insert into accounts (auth_user_id, role, business_type, tier, company, trade_name, initials,
      phone, email, address, district_id, incorporated_on, nature_of_business)
    values (v_uid, 'supplier', 'manufacturer', 'free',
      'Lugazi Steel Rolling Limited', 'Lugazi Steel', 'LS',
      '+256701558820', 'sales@lugazisteel.co.ug',
      'Plot 3, Lugazi Industrial Road', 'mukono', date '2022-02-14',
      'Rolling and supply of reinforcement bar')
    returning id into v_acct;

    insert into account_users (account_id, auth_user_id, full_name, role_title, phone,
      can_post, can_accept, can_release, can_billing)
    values (v_acct, v_uid, 'Sarah Nabbosa', 'Sales manager', '+256701558820', true, true, false, false);

    insert into account_registration (account_id, ursb_number, tin, trading_licence,
      licence_authority, licence_expires_on, overall_state, ursb_state, tin_state, licence_state)
    values (v_acct, '80020013377421', '1011884320', 'MMC/TL/2026/02207', 'Mukono MC',
      date '2026-12-31', 'pending', 'pending', 'pending', 'pending');

    insert into applications (account_id, submitted_at, state,
      registry_ursb, registry_ura, licence_check, sanctions)
    values (v_acct, now() - interval '3 days', 'pending', 'match', 'match', 'current', 'clear');

    insert into account_categories (account_id, category_id) values (v_acct, 'steel-metal')
    on conflict do nothing;
  end if;
end $$;

-- ═══════════════════════════════════════════════════════ confirm

-- select role, company, email from accounts order by role, company;
-- select count(*) as products from products;
-- select count(*) as requirements from requirements;
-- select reference, state, escrow_state, total from orders order by reference;
-- select count(*) as pending_applications from applications where state = 'pending';
