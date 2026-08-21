// BUBU.Market · Supabase data adapter
//
// This is the ONLY file that needs to change to move the frontend off seed data.
// Each function returns exactly the shape the UI already renders, so no screen
// markup or render logic changes. Drop the seed constants in the DC logic class
// and call these instead.
//
// Loaded as a normal browser script — no ES modules. Everything is published on
// window.BUBU_API.
//
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script>
//     window.BUBU_SUPABASE_URL = "https://wiltfiunyftyyqmwrrdt.supabase.co";
//     window.BUBU_SUPABASE_ANON_KEY = "sb_publishable_5rGM-0LeMsOVdw827u006A_fer0Ltqi";
//   </script>
//   <script src="./supabase-adapter.js"></script>
//
// The publishable key is intended for browser use. Never place a secret /
// service_role key in this file.

(function () {

  const SUPABASE_URL = window.BUBU_SUPABASE_URL || '';
  const SUPABASE_ANON_KEY = window.BUBU_SUPABASE_ANON_KEY || '';

  const sb = window.supabase && SUPABASE_URL
    ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    : null;

  if (!sb) {
    console.error(
      '[BUBU] Supabase client not initialised.\n' +
      (!window.supabase
        ? '  supabase-js did not load. Include it BEFORE this file:\n' +
          '  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>'
        : '  BUBU_SUPABASE_URL or BUBU_SUPABASE_ANON_KEY is empty. Set both before this file loads.')
    );
  }

  const money = (n) => 'UGX ' + Number(n || 0).toLocaleString('en-UG');
  const mediaUrl = (path) => path && sb
    ? sb.storage.from('media').getPublicUrl(path).data.publicUrl
    : path;

  const auth = {
    // Uganda phone sign-in: +2567XXXXXXXX
    async requestOtp(phone) {
      return sb.auth.signInWithOtp({ phone });
    },
    async verifyOtp(phone, token) {
      const { data, error } = await sb.auth.verifyOtp({ phone, token, type: 'sms' });
      if (error) throw error;
      return data;
    },
    async signOut() { return sb.auth.signOut(); },
    async session() { return (await sb.auth.getSession()).data.session; }
  };

  // ── account: feeds the profile card, storefront, settings and documents
  async function loadAccount() {
    const { data, error } = await sb
      .from('accounts')
      .select(`*, account_registration(*), account_categories(category_id),
               addresses(*), payout_methods(*), handsets(*), account_users(*),
               documents(*), lead_preferences(*), subscriptions(*)`)
      .single();
    if (error) throw error;
    const r = data.account_registration || {};
    return {
      id: data.id,
      role: data.role,
      bizType: data.business_type === 'manufacturer' ? 'Manufacturer' : 'Trader',
      tier: data.tier === 'industry_leader' ? 'Industry leader'
          : data.tier === 'star_supplier' ? 'Star supplier' : '',
      company: data.company, trade: data.trade_name, initials: data.initials,
      person: (data.account_users?.[0]?.full_name) || '',
      roleTitle: (data.account_users?.[0]?.role_title) || '',
      id_phone: data.phone, alt: data.alt_phone, email: data.email,
      addr: data.address, district: data.district_id,
      ursb: r.ursb_number, tin: r.tin, licence: r.trading_licence, nin: r.director_nin,
      vatNumber: r.vat_number, verificationState: r.overall_state,
      cats: (data.account_categories || []).map(c => c.category_id),
      about: data.about, coverage: data.coverage, nature: data.nature_of_business,
      staffCount: data.staff_count, turnover: data.turnover, brands: data.brands,
      spend: money(data.spend_12m), suppliers: String(data.supplier_count || 0)
    };
  }

  // ── marketplace search: replaces PRODUCTS
  async function searchProducts({ query = '', category = null, limit = 40 } = {}) {
    let q = sb.from('products')
      .select('*, accounts!inner(company, district_id), media(storage_path)')
      .eq('status', 'published').limit(limit);
    if (query) q = q.ilike('name', '%' + query + '%');
    if (category) q = q.eq('category_id', category);
    const { data, error } = await q;
    if (error) throw error;
    return (data || []).map(p => ({
      id: p.id, name: p.name, cat: p.category_id, price: p.price, unit: p.unit,
      moq: p.moq, rating: p.rating, orders: p.order_count,
      supplier: p.accounts.company, loc: p.accounts.district_id,
      photo: mediaUrl(p.media?.[0]?.storage_path)
    }));
  }

  // ── offers on one product: replaces OFFERS[id]
  async function offersFor(productId) {
    const { data, error } = await sb.from('product_offers').select('*').eq('product_id', productId);
    if (error) throw error;
    return (data || []).map(o => ([
      o.supplier, o.district_id, o.price, o.moq + ' ' + o.unit + 's',
      null,                       // phone stays masked until revealContact()
      o.verified, o.years_on_platform
    ]));
  }

  async function revealContact({ requirementId = null, productId = null }) {
    const { data, error } = await sb.rpc('reveal_contact',
      { p_requirement: requirementId, p_product: productId });
    if (error) throw error;      // 'no lead credits remaining'
    return data;                 // the phone number
  }

  // ── supplier buy leads: replaces INDUSTRY[acct].leadTitles, honours saved preferences
  async function myBuyLeads() {
    const { data, error } = await sb.rpc('my_buy_leads');
    if (error) throw error;
    return (data || []).map(r => ({
      id: r.id, title: r.title, cat: r.category_id,
      qty: r.quantity + ' ' + r.quantity_unit,
      loc: r.district_id, neededBy: r.needed_by,
      value: money(r.estimated_value), spec: r.specification
    }));
  }

  // ── buyer requirement
  async function postRequirement(body) {
    const { data, error } = await sb.from('requirements').insert(body).select().single();
    if (error) throw error;
    return data;
  }

  async function sendQuote(body) {
    const { data, error } = await sb.from('quotes').insert({ ...body, state: 'sent' }).select().single();
    if (error) throw error;
    return data;
  }

  // ── orders: feeds the buyer Quotes screen and supplier Orders
  async function loadOrders() {
    const { data, error } = await sb.from('orders')
      .select('*, order_lines(*), buyer:buyer_id(company), supplier:supplier_id(company)')
      .order('created_at', { ascending: false });
    if (error) throw error;
    return (data || []).map(o => ([
      o.reference,
      (o.order_lines || []).map(l => l.name + ' × ' + l.quantity + ' ' + l.unit).join(', '),
      o.supplier?.company || o.buyer?.company,
      money(o.total),
      new Date(o.created_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }),
      ({ pending_payment: 'Awaiting payment', funded: 'Funded', dispatch: 'Dispatch',
         in_transit: 'In transit', delivered: 'Delivered', closed: 'Delivered',
         refunded: 'Refunded' })[o.state] || o.state
    ]));
  }

  const escrow = {
    fund: (orderId, method, phone) => sb.rpc('fund_order', { p_order: orderId, p_method: method, p_phone: phone }),
    confirmDelivery: (orderId) => sb.rpc('confirm_delivery', { p_order: orderId }),
    release: (orderId) => sb.rpc('release_escrow', { p_order: orderId })
  };

  // ── conversations: feeds the lead manager
  async function loadConversations() {
    const { data, error } = await sb.from('conversations')
      .select('*, buyer:buyer_id(company, phone, district_id), supplier:supplier_id(company, phone, district_id), requirement:requirement_id(title), messages(*)')
      .order('last_message_at', { ascending: false });
    if (error) throw error;
    return (data || []).map(c => ([
      c.buyer?.company, '', c.buyer?.district_id || '', c.buyer?.phone,
      c.messages?.[c.messages.length - 1]?.body || '',
      c.requirement?.title || '',
      c.last_message_at ? new Date(c.last_message_at).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' }) : ''
    ]));
  }

  async function sendMessage(conversationId, body) {
    const { data, error } = await sb.from('messages')
      .insert({ conversation_id: conversationId, direction: 'out', channel: 'app', body })
      .select().single();
    if (error) throw error;
    return data;
  }

  // ── admin
  const admin = {
    async applications() {
      const { data, error } = await sb.from('applications')
        .select('*, accounts(company, role, district_id), accounts!inner(account_registration(*))')
        .eq('state', 'pending').order('submitted_at');
      if (error) throw error;
      return data;
    },
    approve: (id) => sb.rpc('approve_application', { p_app: id }),
    reject: (id, reason) => sb.rpc('reject_application', { p_app: id, p_reason: reason }),
    disputes: () => sb.from('disputes').select('*, orders(reference, buyer_id, supplier_id, total)'),
    resolveDispute: (id, outcome, note) =>
      sb.rpc('resolve_dispute', { p_dispute: id, p_outcome: outcome, p_note: note })
  };

  async function uploadMedia(file, { productId = null, kind = 'product' } = {}) {
    const path = crypto.randomUUID() + '-' + file.name.replace(/[^a-zA-Z0-9.]/g, '-');
    const { error } = await sb.storage.from('media').upload(path, file);
    if (error) throw error;
    const { data } = await sb.from('media')
      .insert({ storage_path: path, product_id: productId, kind }).select().single();
    return { ...data, url: mediaUrl(path) };
  }

  window.BUBU_API = { auth, loadAccount, searchProducts, offersFor, revealContact, myBuyLeads,
    postRequirement, sendQuote, loadOrders, escrow, loadConversations, sendMessage, admin, uploadMedia };

})();
