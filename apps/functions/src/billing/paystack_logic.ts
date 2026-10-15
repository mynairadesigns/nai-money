import * as crypto from 'crypto';

/**
 * Pure helpers for the Paystack web-billing flow. No Firebase imports so
 * they can be unit-tested in isolation (see `paystack_logic.test.ts`).
 */

export type PaystackPlanKey = 'monthly' | 'yearly' | 'lifetime';

export const PAYSTACK_PLAN_KEYS: readonly PaystackPlanKey[] = [
  'monthly',
  'yearly',
  'lifetime',
];

const DAY_MS = 24 * 60 * 60 * 1000;

/** Lifetime purchases are stored as "~100 years out", same as RevenueCat. */
export const LIFETIME_MS = 100 * 365 * DAY_MS;

/**
 * Extra days granted on top of each billing period so a renewal that lands
 * a few hours late (Paystack retries failed card charges) doesn't flicker
 * the user back to free.
 */
export const RENEWAL_GRACE_MS = 3 * DAY_MS;

export function isPlanKey(v: unknown): v is PaystackPlanKey {
  return typeof v === 'string' && (PAYSTACK_PLAN_KEYS as string[]).includes(v);
}

/**
 * Paystack signs every webhook with HMAC-SHA512 of the raw request body,
 * keyed by your secret key, in the `x-paystack-signature` header.
 * Constant-time compare to avoid timing leaks.
 */
export function verifyPaystackSignature(
  rawBody: Buffer | string,
  signature: string | undefined,
  secretKey: string,
): boolean {
  if (!signature || !secretKey) return false;
  const expected = crypto
    .createHmac('sha512', secretKey)
    .update(rawBody)
    .digest('hex');
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(signature, 'utf8');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * New expiry after a successful charge for [plan]. Renewals stack on top of
 * any remaining time, so paying early never loses days.
 */
export function computeNewExpiryMs(args: {
  plan: PaystackPlanKey;
  currentExpiryMs: number | null;
  nowMs: number;
}): number {
  const { plan, currentExpiryMs, nowMs } = args;
  if (plan === 'lifetime') return nowMs + LIFETIME_MS;
  const base =
    currentExpiryMs != null && currentExpiryMs > nowMs ? currentExpiryMs : nowMs;
  const period = plan === 'monthly' ? addMonths(base, 1) : addMonths(base, 12);
  return period + RENEWAL_GRACE_MS;
}

/** Calendar-month add in UTC, clamping to the last day (Jan 31 → Feb 28). */
export function addMonths(ms: number, months: number): number {
  const d = new Date(ms);
  const day = d.getUTCDate();
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + months);
  const lastDay = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0),
  ).getUTCDate();
  d.setUTCDate(Math.min(day, lastDay));
  return d.getTime();
}

/**
 * Works out which of our plans a Paystack charge paid for. Initial
 * checkouts carry our own `metadata.plan`; subscription renewals do NOT
 * carry metadata, so we fall back to matching the Paystack plan code.
 */
export function resolvePlanFromCharge(args: {
  metadataPlan: unknown;
  planCode: string | null | undefined;
  planCodes: { monthly: string; yearly: string };
}): PaystackPlanKey | null {
  const { metadataPlan, planCode, planCodes } = args;
  if (planCode) {
    if (planCode === planCodes.monthly) return 'monthly';
    if (planCode === planCodes.yearly) return 'yearly';
  }
  if (isPlanKey(metadataPlan)) return metadataPlan;
  return null;
}

/**
 * Guard used by the RevenueCat paths: a "you're free now" signal from
 * RevenueCat must not wipe out an active entitlement the user bought on
 * the web through Paystack.
 */
export function hasActivePaystackEntitlement(
  userData: Record<string, unknown> | undefined,
  nowMs: number,
): boolean {
  if (!userData) return false;
  if (userData.premiumSource !== 'paystack') return false;
  if (userData.premiumStatus !== 'premium') return false;
  const exp = userData.premiumExpiry as { toMillis?: () => number } | null;
  if (exp == null) return true;
  return typeof exp.toMillis === 'function' && exp.toMillis() > nowMs;
}

/**
 * Only allow redirect targets on origins the buyer has whitelisted, so the
 * checkout callable can't be used as an open redirect.
 */
export function isAllowedCallbackUrl(url: string, allowedOrigins: string[]): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  const isLocal =
    parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
  if (parsed.protocol !== 'https:' && !isLocal) return false;
  if (allowedOrigins.length === 0) return isLocal;
  return allowedOrigins.some((o) => o.replace(/\/+$/, '') === parsed.origin);
}
