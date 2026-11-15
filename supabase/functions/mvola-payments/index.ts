// Smart Akademia School — MVola Merchant Pay (monthly student subscriptions).
// Deploy with Supabase Edge Functions; never expose MVOLA_* secrets to the browser.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = (origin: string | null) => {
  const allowed = Deno.env.get('APP_ORIGIN');
  const headers: Record<string, string> = {
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
  if (origin && allowed && origin === allowed) headers['Access-Control-Allow-Origin'] = origin;
  return headers;
};

const json = (body: unknown, status: number, headers: HeadersInit) =>
  new Response(JSON.stringify(body), { status, headers: { ...headers, 'Content-Type': 'application/json' } });

const normalizeMsisdn = (raw: unknown) => {
  const digits = String(raw ?? '').replace(/[^0-9]/g, '');
  const local = digits.startsWith('261') ? `0${digits.slice(3)}` : digits;
  if (!/^0(32|33|34|38|39)[0-9]{7}$/.test(local)) throw new Error('Numéro MVola invalide. Utilisez 034XXXXXXX ou +26134XXXXXXX.');
  return local;
};

const parseJson = async (response: Response) => {
  const text = await response.text();
  let body: Record<string, unknown> = {};
  try { body = text ? JSON.parse(text) : {}; } catch { /* provider may return plain text */ }
  if (!response.ok) {
    const detail = typeof body.message === 'string' ? body.message : `Réponse MVola HTTP ${response.status}`;
    throw new Error(detail);
  }
  return body;
};

const requiredEnv = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Configuration serveur manquante : ${name}`);
  return value;
};

async function getMvolaToken() {
  const base = (Deno.env.get('MVOLA_API_BASE_URL') || 'https://devapi.mvola.mg').replace(/\/$/, '');
  const tokenPath = Deno.env.get('MVOLA_TOKEN_PATH') || '/token';
  const credentials = btoa(`${requiredEnv('MVOLA_CONSUMER_KEY')}:${requiredEnv('MVOLA_CONSUMER_SECRET')}`);
  const response = await fetch(`${base}${tokenPath}`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${credentials}`,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cache-Control': 'no-cache',
    },
    body: new URLSearchParams({ grant_type: 'client_credentials', scope: 'EXT_INT_MVOLA_SCOPE' }),
  });
  const data = await parseJson(response);
  if (typeof data.access_token !== 'string') throw new Error('MVola n’a pas fourni de jeton OAuth valide.');
  return { token: data.access_token, base };
}

const correlationId = () => crypto.randomUUID();

async function initiateAtMvola(order: Record<string, unknown>, payer: string) {
  const { token, base } = await getMvolaToken();
  const requestId = correlationId();
  const requestDate = new Date().toISOString();
  const endpoint = Deno.env.get('MVOLA_PAYMENT_PATH') || '/merchantpay/1.0.0/transactions/type/merchantpay';
  const merchantMsisdn = normalizeMsisdn(requiredEnv('MVOLA_PARTNER_MSISDN'));
  const payload = {
    amount: String(order.amount_ar),
    currency: 'Ar',
    descriptionText: `Smart Akademia - abonnement mensuel ${String(order.external_reference)}`,
    requestDate,
    debitParty: [{ key: 'msisdn', value: payer }],
    creditParty: [{ key: 'msisdn', value: merchantMsisdn }],
    metadata: [{ key: 'partnerName', value: requiredEnv('MVOLA_PARTNER_NAME') }],
    requestingOrganisationTransactionReference: String(order.external_reference),
    originalTransactionReference: String(order.external_reference),
  };
  const response = await fetch(`${base}${endpoint}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'X-CorrelationID': requestId,
      UserLanguage: 'fr',
      UserAccountIdentifier: `msisdn;${merchantMsisdn}`,
      PartnerName: requiredEnv('MVOLA_PARTNER_NAME'),
    },
    body: JSON.stringify(payload),
  });
  const result = await parseJson(response);
  const serverId = result.serverCorrelationId ?? result.serverCorrelationID ?? result.transactionId;
  if (typeof serverId !== 'string' || !serverId) throw new Error('MVola n’a pas renvoyé d’identifiant de transaction serveur.');
  return { serverId, providerStatus: String(result.status ?? 'PENDING') };
}

function findText(data: Record<string, unknown>, ...keys: string[]) {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return null;
}

async function pollAtMvola(serverId: string) {
  const { token, base } = await getMvolaToken();
  const pathTemplate = Deno.env.get('MVOLA_STATUS_PATH') || '/merchantpay/1.0.0/transactions/{id}';
  const path = pathTemplate.replace('{id}', encodeURIComponent(serverId));
  const response = await fetch(`${base}${path}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      'X-CorrelationID': correlationId(),
      UserLanguage: 'fr',
      PartnerName: requiredEnv('MVOLA_PARTNER_NAME'),
      'Cache-Control': 'no-cache',
    },
  });
  return await parseJson(response);
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  const headers = corsHeaders(origin);
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({ error: 'Méthode non autorisée.' }, 405, headers);
  const allowedOrigin = Deno.env.get('APP_ORIGIN');
  if (allowedOrigin && origin !== allowedOrigin) return json({ error: 'Origine non autorisée.' }, 403, headers);

  try {
    const authorization = req.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer ')) return json({ error: 'Connexion requise.' }, 401, headers);
    const url = requiredEnv('SUPABASE_URL');
    const anonKey = requiredEnv('SUPABASE_ANON_KEY');
    const serviceKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
    const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return json({ error: 'Session invalide ou expirée.' }, 401, headers);
    const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await adminClient
      .from('profiles').select('id,role,registration_status,full_name,series').eq('id', user.id).maybeSingle();
    if (profileError || !profile || profile.role !== 'student' || profile.registration_status !== 'approved') {
      return json({ error: 'Cette intégration est réservée aux élèves approuvés.' }, 403, headers);
    }

    const input = await req.json();
    if (input.action === 'initiate') {
      const idempotencyKey = String(input.idempotencyKey ?? '');
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotencyKey)) {
        return json({ error: 'Clé idempotence UUID invalide.' }, 400, headers);
      }
      const payer = normalizeMsisdn(input.payerMsisdn);
      const externalReference = `AKD-${crypto.randomUUID()}`;
      const { data: prior } = await adminClient.from('mvola_payment_orders').select('*')
        .eq('user_id', user.id).eq('idempotency_key', idempotencyKey).maybeSingle();
      if (prior) return json({ paymentId: prior.id, status: prior.status, serverCorrelationId: prior.server_correlation_id }, 200, headers);

      const { data: order, error: insertError } = await adminClient.from('mvola_payment_orders').insert({
        user_id: user.id, idempotency_key: idempotencyKey, plan_code: 'monthly', amount_ar: 15000,
        currency: 'Ar', payer_msisdn: payer, external_reference: externalReference, status: 'created',
      }).select('*').single();
      if (insertError || !order) throw new Error(insertError?.message || 'Impossible de créer la demande de paiement.');

      try {
        const initiated = await initiateAtMvola(order, payer);
        const { error: updateError } = await adminClient.from('mvola_payment_orders').update({
          status: 'pending', server_correlation_id: initiated.serverId, provider_status: initiated.providerStatus,
          updated_at: new Date().toISOString(),
        }).eq('id', order.id);
        if (updateError) throw updateError;
        return json({ paymentId: order.id, status: 'pending', amountAr: 15000, currency: 'Ar',
          externalReference: order.external_reference, serverCorrelationId: initiated.serverId,
          message: 'Demande MVola envoyée. Confirmez-la sur votre téléphone puis vérifiez son statut.' }, 200, headers);
      } catch (error) {
        await adminClient.from('mvola_payment_orders').update({ status: 'failed', provider_status: 'INITIATION_ERROR', updated_at: new Date().toISOString() }).eq('id', order.id);
        throw error;
      }
    }

    if (input.action === 'status') {
      const paymentId = String(input.paymentId ?? '');
      const { data: order, error: orderError } = await adminClient.from('mvola_payment_orders').select('*')
        .eq('id', paymentId).eq('user_id', user.id).maybeSingle();
      if (orderError || !order) return json({ error: 'Demande de paiement introuvable.' }, 404, headers);
      if (order.status === 'paid' || order.status === 'failed' || order.status === 'cancelled') {
        return json({ paymentId, status: order.status, subscriptionId: order.subscription_id }, 200, headers);
      }
      if (!order.server_correlation_id) return json({ paymentId, status: order.status }, 200, headers);

      const provider = await pollAtMvola(order.server_correlation_id);
      const providerStatus = (findText(provider, 'status', 'transactionStatus') || 'PENDING').toUpperCase();
      if (providerStatus === 'SUCCESSFUL' || providerStatus === 'SUCCESS') {
        const amountText = findText(provider, 'amount');
        const currency = findText(provider, 'currency');
        const externalRef = findText(provider, 'externalId', 'requestingOrganisationTransactionReference', 'originalTransactionReference');
        const financialId = findText(provider, 'financialTransactionId', 'transactionReference', 'transactionId');
        if (!amountText || !currency || externalRef !== order.external_reference || Number(amountText) !== order.amount_ar || currency !== order.currency || !financialId) {
          throw new Error('Confirmation MVola incomplète ou incohérente. Le paiement reste en attente de vérification.');
        }
        const { data: subscriptionId, error: settleError } = await adminClient.rpc('settle_akademia_mvola_subscription', {
          p_payment_id: order.id, p_financial_transaction_id: financialId,
          p_confirmed_amount: Number(amountText), p_confirmed_currency: currency,
          p_external_reference: externalRef,
        });
        if (settleError) throw settleError;
        return json({ paymentId, status: 'paid', subscriptionId,
          message: 'Paiement MVola confirmé et abonnement mensuel activé.' }, 200, headers);
      }
      if (['FAILED', 'REJECTED', 'CANCELLED', 'EXPIRED'].includes(providerStatus)) {
        await adminClient.from('mvola_payment_orders').update({ status: providerStatus === 'CANCELLED' ? 'cancelled' : 'failed', provider_status: providerStatus, updated_at: new Date().toISOString() }).eq('id', order.id);
        return json({ paymentId, status: providerStatus === 'CANCELLED' ? 'cancelled' : 'failed' }, 200, headers);
      }
      await adminClient.from('mvola_payment_orders').update({ status: 'pending', provider_status: providerStatus, updated_at: new Date().toISOString() }).eq('id', order.id);
      return json({ paymentId, status: 'pending', providerStatus, message: 'Transaction toujours en cours chez MVola.' }, 200, headers);
    }

    return json({ error: 'Action inconnue. Utilisez initiate ou status.' }, 400, headers);
  } catch (error) {
    console.error('MVola payment error:', error);
    return json({ error: error instanceof Error ? error.message : 'Erreur du service de paiement.' }, 502, headers);
  }
});
