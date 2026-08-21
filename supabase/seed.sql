-- BUBU.Market · seed data mirroring the eleven demo accounts in the frontend.
-- Passwords are not stored here: create the auth users first (Supabase Auth phone
-- sign-in), then link each account row via auth_user_id.

insert into districts (id, name, region, lat, lng) values
  ('kampala','Kampala','Central',0.3476,32.5825),
  ('wakiso','Wakiso','Central',0.4044,32.4594),
  ('mukono','Mukono','Central',0.3533,32.7553),
  ('jinja','Jinja','Eastern',0.4244,33.2042),
  ('mbale','Mbale','Eastern',1.0644,34.1797),
  ('lira','Lira','Northern',2.2350,32.9097),
  ('gulu','Gulu','Northern',2.7746,32.2990),
  ('masindi','Masindi','Western',1.6744,31.7150),
  ('mbarara','Mbarara','Western',-0.6072,30.6545),
  ('kiryandongo','Kiryandongo','Western',1.8700,32.0700)
on conflict (id) do nothing;

insert into categories (id, name, sort) values
  ('building-construction','Building & construction',1),
  ('agriculture-produce','Agriculture & produce',2),
  ('food-beverage','Food & beverage wholesale',3),
  ('hardware-tools','Hardware & tools',4),
  ('packaging','Packaging',5),
  ('chemicals-industrial','Chemicals & industrial',6),
  ('medical-supplies','Medical supplies',7),
  ('electronics','Electronics',8),
  ('auto-parts','Auto parts',9)
on conflict (id) do nothing;

insert into fee_rules (name, applies_to, rate, minimum, payer, note) values
  ('Standard escrow commission','all_orders',0.0150,5000,'supplier','1.5% of order value'),
  ('Export order commission','export',0.0320,12000,'supplier','Cross-border, includes documentation desk'),
  ('Industry leader listing','tier',null,null,'supplier','UGX 1,200,000 per year, 40 lead credits'),
  ('Star supplier listing','tier',null,null,'supplier','UGX 640,000 per year, 18 lead credits'),
  ('Buy lead credit','all_orders',null,12000,'supplier','Per contact revealed')
on conflict do nothing;

-- Suppliers ────────────────────────────────────────────────
with s as (
  insert into accounts (role, business_type, tier, company, trade_name, initials, phone, alt_phone,
                        email, address, district_id, incorporated_on, about, coverage, nature_of_business,
                        staff_count, turnover, brands)
  values
   ('supplier','trader','industry_leader','Kampala Hardware Depot Limited','KH Depot','KH','+256772415908','+256752118340',
    'moses@khd.co.ug','Plot 44, Sixth Street, Industrial Area','kampala','2019-03-11',
    'Wholesale distributor of cement, steel reinforcement, roofing and hardware across central Uganda.',
    'Kampala, Wakiso, Mukono · 6 trucks','Wholesale of cement, steel reinforcement, roofing and hardware',
    '34 permanent, 12 casual','UGX 8.4bn, financial year 2025','Tororo Cement, Roofings Group, Steel and Tube'),
   ('supplier','trader','star_supplier','Kisekka Tools and Hardware Limited','Kisekka Tools','KT','+256772660214','+256703118442',
    'sarah@kisekkatools.co.ug','Shop 118, Kisekka Market','kampala','2016-07-04',
    'Power tools, hand tools and fasteners for contractors and retailers.','Kampala and central region',
    'Retail and wholesale of tools','12 permanent','UGX 2.1bn, financial year 2025','Bosch, Total Tools, Ingco'),
   ('supplier','manufacturer','industry_leader','Nile Grain and Produce Limited','Nile Grain','NG','+256774552013','+256758441260',
    'denis@nilegrain.co.ug','Plot 9, Aputi Road, Lira Industrial Area','lira','2018-01-22',
    'Grain aggregation, cleaning and milling. Own stores in Lira and Kiryandongo.',
    'Northern and central Uganda · 9 trucks','Grain aggregation, cleaning and edible oil pressing',
    '48 permanent, 60 seasonal','UGX 9.6bn, financial year 2025','Nile Grain own brand'),
   ('supplier','manufacturer','industry_leader','Namanve Construction Supplies Limited','Namanve Construction','NC','+256776812340','+256752907118',
    'peter@namanveconstruction.co.ug','Plot 210, Namanve Industrial Park','mukono','2015-05-09',
    'Aggregates, ready-mix concrete, blocks and formwork for contractors.',
    'Kampala, Wakiso, Mukono, Jinja · 14 tippers and 4 mixers',
    'Quarrying, ready-mix concrete production and supply','62 permanent, 40 casual',
    'UGX 11.8bn, financial year 2025','Own quarry output, Tororo Cement'),
   ('supplier','trader','star_supplier','Medisure Wholesale Limited','Medisure Wholesale','MS','+256772884110','+256758220447',
    'aisha@medisure.co.ug','Plot 7, Kigowa Road, Ntinda','kampala','2017-08-18',
    'Wholesale of examination gloves, protective equipment and clinical consumables.',
    'Nationwide · courier to regional referral hospitals','Wholesale of medical and protective equipment',
    '19 permanent, 6 casual','UGX 5.1bn, financial year 2025','Medisure own brand, Hartmann, Ansell')
  returning id, phone
)
insert into account_registration (account_id, ursb_number, tin, trading_licence, licence_authority,
                                  director_nin, overall_state, ursb_state, tin_state, licence_state, nin_state)
select id,
  case phone when '+256772415908' then '80020003456789' when '+256772660214' then '80020006611024'
             when '+256774552013' then '80020004417755' when '+256776812340' then '80020008841207'
             else '80020011552308' end,
  case phone when '+256772415908' then '1002938475' when '+256772660214' then '1004471902'
             when '+256774552013' then '1003882140' when '+256776812340' then '1007244810'
             else '1009446721' end,
  case phone when '+256772415908' then 'KCCA/TL/2026/44120' when '+256772660214' then 'KCCA/TL/2026/51188'
             when '+256774552013' then 'LMC/TL/2026/00921' when '+256776812340' then 'MMC/TL/2026/01184'
             else 'NDA/WHS/2026/00612' end,
  case phone when '+256774552013' then 'Lira MC' when '+256776812340' then 'Mukono MC' else 'KCCA' end,
  case phone when '+256772415908' then 'CM90210458PQ2K' when '+256772660214' then 'CF91330871LTR5'
             when '+256774552013' then 'CM87041192WQ8H' when '+256776812340' then 'CM82170634ZNB3'
             else 'CF89250417KMD9' end,
  'verified','verified','verified','verified','verified'
from s;

-- Buyers ──────────────────────────────────────────────────
with b as (
  insert into accounts (role, tier, company, trade_name, initials, phone, alt_phone, email,
                        address, district_id, incorporated_on, spend_12m, supplier_count)
  values
   ('buyer','free','Nakawa Trading Co. Ltd','Nakawa Trading','NT','+256772903445','+256752118077',
    'grace@nakawatrading.co.ug','Plot 12, Ntinda Industrial Area','kampala','2024-03-01',214000000,17),
   ('buyer','free','Nsambya Hospital Supplies Limited','Nsambya Hospital','NH','+256752664209','+256701992118',
    'peter@nsambyasupplies.co.ug','Nsambya Hill, Makindye Division','kampala','2020-01-01',812000000,19),
   ('buyer','free','Seeta Housing Developments Limited','Seeta Housing','SH','+256788314076','+256701447320',
    'irene@seetahousing.co.ug','Seeta, Mukono municipality','mukono','2021-06-01',3060000000,14)
  returning id, phone
)
insert into account_registration (account_id, ursb_number, tin, trading_licence, licence_authority,
                                  director_nin, overall_state, tin_state, nin_state)
select id,
  case phone when '+256772903445' then '80020002884411' when '+256752664209' then '80020012288417' else '80020009917744' end,
  case phone when '+256772903445' then '1002938475' when '+256752664209' then '1010773204' else '1006612094' end,
  case phone when '+256772903445' then 'KCCA/TL/2026/33017' when '+256752664209' then 'KCCA/TL/2026/61204' else 'MMC/TL/2026/00884' end,
  case phone when '+256788314076' then 'Mukono MC' else 'KCCA' end,
  case phone when '+256772903445' then 'CF88031277KJ4A' when '+256752664209' then 'CM86112049TRV7' else 'CF90080513NPX2' end,
  'pending','verified','verified'
from b;

-- Platform operations ─────────────────────────────────────
insert into accounts (role, tier, company, trade_name, initials, phone, email, address, district_id)
values ('admin','free','BUBU.Market Uganda Limited','Platform operations','BA','+256800218400',
        'aisha.n@bubu.market','Level 4, Acacia Place, Kololo','kampala');

-- Default notification preferences for every account
insert into notification_prefs (account_id, topic, email, sms, app, whatsapp)
select a.id, t.topic, t.email, t.sms, true, t.whatsapp
from accounts a,
 (values ('enquiries',true,false,true),('replies',true,false,false),('followups',true,false,false),
         ('missed_calls',false,true,true),('lead_alerts',true,true,false),('tenders',false,false,false),
         ('payouts',true,true,true),('offers',false,false,false)) as t(topic,email,sms,whatsapp)
on conflict do nothing;

-- Lead credits per membership tier
insert into lead_credits (account_id, granted, expires_on)
select id, case tier when 'industry_leader' then 40 when 'star_supplier' then 18 else 0 end,
       current_date + interval '1 year'
from accounts where role = 'supplier';

-- Lead preferences default to the supplier's own district plus 60 km
insert into lead_preferences (account_id, districts, radius_km)
select id, array[district_id], 60 from accounts where role = 'supplier'
on conflict do nothing;
