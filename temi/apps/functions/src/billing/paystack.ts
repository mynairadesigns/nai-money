import * as admin from 'firebase-admin';
import { defineInt, defineSecret, defineString } from 'firebase-functions/params';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';

import { REGION } from '../utils/region';
import {
  computeNewExpiryMs,
  isAllowedCallbackUrl,
  isPlanKey,
  PaystackPlanKey,
  resolvePlanFromCharge,
  verifyPaystackSignature,
} from './paystack_logic';

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Paystack web billing — the web counterpart to RevenueCat.
 *
 * Writes the SAME `users/{uid}.premiumStatus` + `premiumExpiry` fields the
 * RevenueCat webhook writes, so the server-side AI quota bypass, the admin
 * panel and the app's `isPremiumProvider` all work unchanged. It also sets
 * `premiumSource: 'paystack'` so the RevenueCat paths know not to downgrade
 * a web subscriber.
 *
 * Model: monthly + yearly are Paystack *Plans* (Paystack auto-charges the
 * card each period); lifetime is a one-off charge. Every successful charge
 * extends `premiumExpiry` by one period (+3 days grace). If the user cancels
 * or the card fails, no new charge arrives and premium simply runs out at
 * the end of the paid period — no revoke event needed.
 *
 * Setup (see WEB_SETUP.md):
 *   firebase functions:secrets:set PAYSTACK_SECRET_KEY
 *   apps/functions/.env  →  PAYSTACK_PLAN_MONTHLY, PAYSTACK_PLAN_YEARLY,
 *                           PAYSTACK_LIFETIME_AMOUNT, PAYSTACK_CURRENCY,
 *                           PAYSTACK_ALLOWED_ORIGINS
 *   Paystack dashboard → Settings → API Keys & Webhooks → Webhook URL =
 *     the deployed `handlePaystackWebhook` URL.
 */

const PAYSTACK_SECRET_KEY = defineSecret('PAYSTACK_SECRET_KEY');
const PAYSTACK_PLAN_MONTHLY = defineString('PAYSTACK_PLAN_MONTHLY', {
  default: '',
  description: 'Paystack plan code (PLN_...) for the monthly Premium plan',
});
const PAYSTACK_PLAN_YEARLY = defineString('PAYSTACK_PLAN_YEARLY', {
  default: '',
  description: 'Paystack plan code (PLN_...) for the yearly Premium plan',
});
const PAYSTACK_LIFETIME_AMOUNT = defineInt('PAYSTACK_LIFETIME_AMOUNT', {
  default: 0,
  description:
    'Lifetime Premium price in the smallest currency unit (kobo for NGN). 0 = lifetime disabled.',
});
const PAYSTACK_CURRENCY = defineString('PAYSTACK_CURRENCY', {
  default: 'NGN',
  description: 'Currency for the lifetime one-off charge (plans carry their own)',
});
const PAYSTACK_ALLOWED_ORIGINS = defineString('PAYSTACK_ALLOWED_ORIGINS', {
  default: '',
  description:
    'Comma-separated origins allowed as checkout return URLs, e.g. https://app.example.com',
});

const API = 'https://api.paystack.co';
const db = () => admin.firestore();

// ---------------------------------------------------------------------------
// Paystack REST helper
// ---------------------------------------------------------------------------

interface PaystackEnvelope<T> {
  status: boolean;
  message: string;
  data: T;
}

async function paystack<T>(
  path: string,
  init: { method?: 'GET' | 'POST'; body?: unknown } = {},
): Promise<T> {
  const key = process.env.PAYSTACK_SECRET_KEY ?? '';
  if (!key) {
    throw new HttpsError('failed-precondition', 'Paystack is not configured');
  }
  const resp = await fetch(`${API}${path}`, {
    method: init.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  let json: PaystackEnvelope<T> | null = null;
  try {
    json = (await resp.json()) as PaystackEnvelope<T>;
  } catch {
    json = null;
  }
  if (!resp.ok || !json?.status) {
    console.error(`Paystack ${path} failed`, resp.status, json?.message);
    throw new HttpsError(
      'internal',
      `Paystack error: ${json?.message ?? resp.status}`,
    );
  }
  return json.data;
}

function planCodes() {
  return {
    monthly: PAYSTACK_PLAN_MONTHLY.value(),
    yearly: PAYSTACK_PLAN_YEARLY.value(),
  };
}

// ---------------------------------------------------------------------------
// getPaystackPrices — display prices for the web paywall
// ---------------------------------------------------------------------------

interface PlanPrice {
  amount: number; // smallest unit (kobo)
  currency: string;
}

interface PricesResponse {
  monthly: PlanPrice | null;
  yearly: PlanPrice | null;
  lifetime: PlanPrice | null;
}

let pricesCache: { at: number; value: PricesResponse } | null = null;
const PRICES_TTL_MS = 10 * 60 * 1000;

/**
 * Prices come straight from the Paystack plans (single source of truth —
 * change the price in the Paystack dashboard and the paywall follows).
 */
export const getPaystackPrices = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 20, secrets: [PAYSTACK_SECRET_KEY] },
  async (request): Promise<PricesResponse> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
    if (pricesCache && Date.now() - pricesCache.at < PRICES_TTL_MS) {
      return pricesCache.value;
    }
    const codes = planCodes();
    const fetchPlan = async (code: string): Promise<PlanPrice | null> => {
      if (!code) return null;
      try {
        const p = await paystack<{ amount: number; currency: string }>(
          `/plan/${encodeURIComponent(code)}`,
        );
        return { amount: p.amount, currency: p.currency };
      } catch (e) {
        // Usually a key/plan mismatch (other business, or Test vs Live).
        // Hide that plan rather than failing the whole paywall.
        console.error(`getPaystackPrices: plan ${code} unavailable`, e);
        return null;
      }
    };
    const [monthly, yearly] = await Promise.all([
      fetchPlan(codes.monthly),
      fetchPlan(codes.yearly),
    ]);
    const lifetimeAmount = PAYSTACK_LIFETIME_AMOUNT.value();
    const value: PricesResponse = {
      monthly,
      yearly,
      lifetime:
        lifetimeAmount > 0
          ? { amount: lifetimeAmount, currency: PAYSTACK_CURRENCY.value() }
          : null,
    };
    pricesCache = { at: Date.now(), value };
    return value;
  },
);

// ---------------------------------------------------------------------------
// startPaystackCheckout — returns a Paystack hosted-checkout URL
// ---------------------------------------------------------------------------

export const startPaystackCheckout = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 30, secrets: [PAYSTACK_SECRET_KEY] },
  async (request): Promise<{ authorizationUrl: string; reference: string }> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
    const uid = request.auth.uid;
    const data = (request.data ?? {}) as { plan?: unknown; callbackUrl?: unknown };

    if (!isPlanKey(data.plan)) {
      throw new HttpsError('invalid-argument', 'plan must be monthly, yearly or lifetime');
    }
    const plan: PaystackPlanKey = data.plan;
    const callbackUrl = typeof data.callbackUrl === 'string' ? data.callbackUrl : '';
    const allowed = PAYSTACK_ALLOWED_ORIGINS.value()
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    if (!isAllowedCallbackUrl(callbackUrl, allowed)) {
      throw new HttpsError(
        'invalid-argument',
        'callbackUrl origin is not in PAYSTACK_ALLOWED_ORIGINS',
      );
    }

    // Paystack requires an email for every transaction.
    const userSnap = await db().doc(`users/${uid}`).get();
    const userData = userSnap.data() ?? {};
    const email =
      (request.auth.token.email as string | undefined) ||
      (typeof userData.email === 'string' ? userData.email : '');
    if (!email) {
      throw new HttpsError(
        'failed-precondition',
        'Your account needs an email address to pay with Paystack',
      );
    }

    // Don't let an active subscriber start a second auto-renewing plan.
    const expiry = userData.premiumExpiry as admin.firestore.Timestamp | null | undefined;
    const isActive =
      userData.premiumStatus === 'premium' &&
      (expiry == null || expiry.toMillis() > Date.now());
    if (isActive && plan !== 'lifetime') {
      throw new HttpsError('already-exists', 'You already have Premium');
    }

    const codes = planCodes();
    let body: Record<string, unknown>;
    if (plan === 'lifetime') {
      const amount = PAYSTACK_LIFETIME_AMOUNT.value();
      if (amount <= 0) throw new HttpsError('failed-precondition', 'Lifetime plan is not available');
      body = { amount, currency: PAYSTACK_CURRENCY.value() };
    } else {
      const code = plan === 'monthly' ? codes.monthly : codes.yearly;
      if (!code) throw new HttpsError('failed-precondition', `${plan} plan is not configured`);
      const p = await paystack<{ amount: number; currency: string }>(
        `/plan/${encodeURIComponent(code)}`,
      );
      // With `plan` set, Paystack charges the plan amount and creates the
      // subscription after the first successful payment.
      body = { amount: p.amount, currency: p.currency, plan: code };
    }

    const init = await paystack<{ authorization_url: string; reference: string }>(
      '/transaction/initialize',
      {
        method: 'POST',
        body: {
          ...body,
          email,
          callback_url: callbackUrl,
          metadata: { uid, plan, cancel_action: callbackUrl },
        },
      },
    );

    await db().doc(`paystackTransactions/${init.reference}`).set({
      uid,
      plan,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { authorizationUrl: init.authorization_url, reference: init.reference };
  },
);

// ---------------------------------------------------------------------------
// verifyPaystackPayment — called by the web app on return from checkout
// ---------------------------------------------------------------------------

interface PaystackCharge {
  reference: string;
  status: string;
  amount: number;
  currency: string;
  metadata?: unknown;
  plan?: { plan_code?: string } | string | null;
  customer?: { customer_code?: string; email?: string };
}

export const verifyPaystackPayment = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 30, secrets: [PAYSTACK_SECRET_KEY] },
  async (request): Promise<{ isPremium: boolean; expiryMs: number | null }> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
    const reference = String((request.data as { reference?: unknown })?.reference ?? '');
    if (!/^[A-Za-z0-9_.=-]{4,100}$/.test(reference)) {
      throw new HttpsError('invalid-argument', 'Invalid reference');
    }
    const charge = await paystack<PaystackCharge>(
      `/transaction/verify/${encodeURIComponent(reference)}`,
    );
    if (charge.status !== 'success') {
      return { isPremium: false, expiryMs: null };
    }
    const result = await applySuccessfulCharge(charge, request.auth.uid);
    return result;
  },
);

// ---------------------------------------------------------------------------
// getPaystackManageLink — Paystack-hosted page to cancel / update card
// ---------------------------------------------------------------------------

export const getPaystackManageLink = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 20, secrets: [PAYSTACK_SECRET_KEY] },
  async (request): Promise<{ link: string | null }> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required');
    const snap = await db().doc(`users/${request.auth.uid}`).get();
    const code = snap.data()?.paystackSubscriptionCode as string | undefined;
    if (!code) return { link: null };
    const d = await paystack<{ link: string }>(
      `/subscription/${encodeURIComponent(code)}/manage/link`,
    );
    return { link: d.link };
  },
);

// ---------------------------------------------------------------------------
// handlePaystackWebhook — authoritative path (renewals arrive only here)
// ---------------------------------------------------------------------------

export const handlePaystackWebhook = onRequest(
  { region: REGION, memory: '256MiB', timeoutSeconds: 30, secrets: [PAYSTACK_SECRET_KEY] },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('method not allowed');
      return;
    }
    const sig = req.header('x-paystack-signature');
    if (!verifyPaystackSignature(req.rawBody, sig, process.env.PAYSTACK_SECRET_KEY ?? '')) {
      console.warn('Paystack webhook: bad signature');
      res.status(401).send('unauthorized');
      return;
    }

    const event = String((req.body as { event?: unknown })?.event ?? '');
    const data = ((req.body as { data?: unknown })?.data ?? {}) as Record<string, unknown>;

    try {
      if (event === 'charge.success') {
        await applySuccessfulCharge(data as unknown as PaystackCharge, null);
      } else if (event === 'subscription.create') {
        await recordSubscription(data, 'active');
      } else if (event === 'subscription.not_renew' || event === 'subscription.disable') {
        // Cancelled / ended. Premium is NOT revoked here — it runs out at
        // the end of the period the user already paid for.
        await recordSubscription(data, event === 'subscription.disable' ? 'disabled' : 'non-renewing');
      } else {
        console.log(`Paystack webhook: ignoring ${event}`);
      }
    } catch (e) {
      console.error(`Paystack webhook: ${event} failed`, e);
      res.status(500).send('internal'); // Paystack retries non-200s
      return;
    }
    res.status(200).send('ok');
  },
);

// ---------------------------------------------------------------------------
// Shared entitlement writer
// ---------------------------------------------------------------------------

function parseMetadata(raw: unknown): Record<string, unknown> {
  if (raw && typeof raw === 'object') return raw as Record<string, unknown>;
  if (typeof raw === 'string' && raw) {
    try {
      const v = JSON.parse(raw);
      if (v && typeof v === 'object') return v as Record<string, unknown>;
    } catch {
      /* not JSON */
    }
  }
  return {};
}

async function uidForCustomer(customerCode: string | undefined): Promise<string | null> {
  if (!customerCode) return null;
  const snap = await db().doc(`paystackCustomers/${customerCode}`).get();
  const uid = snap.data()?.uid;
  return typeof uid === 'string' && uid ? uid : null;
}

/**
 * Idempotent: the same charge can arrive from both the webhook and the
 * client-side verify call (and Paystack retries webhooks). The
 * `paystackTransactions/{reference}` doc's `processed` flag guarantees the
 * period is only added once.
 *
 * [callerUid] is set when called from the client — the charge must belong
 * to that user.
 */
async function applySuccessfulCharge(
  charge: PaystackCharge,
  callerUid: string | null,
): Promise<{ isPremium: boolean; expiryMs: number | null }> {
  const reference = String(charge.reference ?? '');
  if (!reference) throw new Error('charge has no reference');

  const meta = parseMetadata(charge.metadata);
  const customerCode = charge.customer?.customer_code;
  const planCode =
    typeof charge.plan === 'object' && charge.plan ? charge.plan.plan_code : undefined;

  const txRef = db().doc(`paystackTransactions/${reference}`);
  const pending = (await txRef.get()).data();

  const uid =
    (typeof meta.uid === 'string' && meta.uid) ||
    (typeof pending?.uid === 'string' && pending.uid) ||
    (await uidForCustomer(customerCode));
  if (!uid) {
    console.warn(`Paystack: no uid for charge ${reference} (customer ${customerCode})`);
    return { isPremium: false, expiryMs: null };
  }
  if (callerUid && callerUid !== uid) {
    throw new HttpsError('permission-denied', 'This payment belongs to another account');
  }

  const plan = resolvePlanFromCharge({
    metadataPlan: meta.plan ?? pending?.plan,
    planCode,
    planCodes: planCodes(),
  });
  if (!plan) {
    console.warn(`Paystack: charge ${reference} does not match a Temi Finance plan`);
    return { isPremium: false, expiryMs: null };
  }
  if (plan === 'lifetime') {
    const expected = PAYSTACK_LIFETIME_AMOUNT.value();
    if (charge.amount < expected || charge.currency !== PAYSTACK_CURRENCY.value()) {
      console.warn(`Paystack: lifetime charge ${reference} amount/currency mismatch`);
      return { isPremium: false, expiryMs: null };
    }
  }

  const userRef = db().doc(`users/${uid}`);
  return db().runTransaction(async (t) => {
    const [txSnap, userSnap] = await Promise.all([t.get(txRef), t.get(userRef)]);
    const user = userSnap.data() ?? {};
    const currentExpiry = user.premiumExpiry as admin.firestore.Timestamp | null | undefined;
    const currentExpiryMs =
      user.premiumStatus === 'premium' && currentExpiry ? currentExpiry.toMillis() : null;

    if (txSnap.data()?.processed === true) {
      return { isPremium: user.premiumStatus === 'premium', expiryMs: currentExpiryMs };
    }

    const expiryMs = computeNewExpiryMs({ plan, currentExpiryMs, nowMs: Date.now() });
    const finalExpiryMs = Math.max(expiryMs, currentExpiryMs ?? 0);

    t.set(
      userRef,
      {
        premiumStatus: 'premium',
        premiumExpiry: admin.firestore.Timestamp.fromMillis(finalExpiryMs),
        premiumSource: 'paystack',
        premiumPlan: plan,
        ...(customerCode ? { paystackCustomerCode: customerCode } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    t.set(
      txRef,
      {
        uid,
        plan,
        status: 'success',
        processed: true,
        amount: charge.amount,
        currency: charge.currency,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (customerCode) {
      t.set(db().doc(`paystackCustomers/${customerCode}`), { uid }, { merge: true });
    }
    return { isPremium: true, expiryMs: finalExpiryMs };
  });
}

async function recordSubscription(
  data: Record<string, unknown>,
  status: 'active' | 'non-renewing' | 'disabled',
): Promise<void> {
  const customer = data.customer as { customer_code?: string } | undefined;
  const uid = await uidForCustomer(customer?.customer_code);
  if (!uid) {
    if (status === 'active') {
      // `subscription.create` can occasionally beat `charge.success` (which
      // is what maps the customer to a uid). Throwing → 500 → Paystack
      // retries later, by which time the mapping exists.
      throw new Error(`subscription.create for unmapped customer ${customer?.customer_code}`);
    }
    console.warn('Paystack subscription event for unknown customer', customer?.customer_code);
    return;
  }
  const code = typeof data.subscription_code === 'string' ? data.subscription_code : undefined;
  await db().doc(`users/${uid}`).set(
    {
      ...(code ? { paystackSubscriptionCode: code } : {}),
      paystackSubscriptionStatus: status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}
