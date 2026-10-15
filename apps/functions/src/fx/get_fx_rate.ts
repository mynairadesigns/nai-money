import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION } from '../utils/region';

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * `getFxRate` — auth-gated callable that returns a foreign-exchange rate for
 * the given ISO-4217 currency pair. Backs the cross-currency transfer flow
 * in PRD §6.2 (every transfer records `fxRate` at transaction time).
 *
 * Shape follows CLAUDE.md §7 (auth → quota → provider). Rate-limit step is
 * intentionally skipped here because FX calls are cheap and the provider
 * already gives us a generous quota; the per-user monthly counter caps abuse.
 *
 * 2nd-gen `onCall` is used (not 1st-gen) because firebase-functions v7 gives
 * us a cleaner secrets API via `defineSecret(...)` + the `secrets` option.
 *
 * Secret setup (run once per Firebase project):
 *   firebase functions:secrets:set EXCHANGERATE_API_KEY
 */

const EXCHANGERATE_API_KEY = defineSecret('EXCHANGERATE_API_KEY');

const CACHE_TTL_MS = 12 * 60 * 60 * 1000; // 12 hours
const MONTHLY_QUOTA_LIMIT = 1000;
const CURRENCY_CODE_RE = /^[A-Za-z]{3}$/;

interface GetFxRateRequest {
  from?: unknown;
  to?: unknown;
}

interface GetFxRateResponse {
  rate: number;
  asOf: string;
}

interface ExchangeRateApiResponse {
  result?: string;
  conversion_rate?: number;
  'error-type'?: string;
}

interface CachedFxRate {
  rate: number;
  from: string;
  to: string;
  fetchedAt?: FirebaseFirestore.Timestamp;
}

export const getFxRate = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    secrets: [EXCHANGERATE_API_KEY],
  },
  async (request): Promise<GetFxRateResponse> => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign-in required to fetch FX rates.');
    }
    const uid = request.auth.uid;

    const data = (request.data ?? {}) as GetFxRateRequest;
    const rawFrom = typeof data.from === 'string' ? data.from : '';
    const rawTo = typeof data.to === 'string' ? data.to : '';

    if (!CURRENCY_CODE_RE.test(rawFrom) || !CURRENCY_CODE_RE.test(rawTo)) {
      throw new HttpsError(
        'invalid-argument',
        '`from` and `to` must be 3-letter ISO currency codes.',
      );
    }

    const from = rawFrom.toUpperCase();
    const to = rawTo.toUpperCase();

    // Identity pair — short-circuit before any I/O.
    if (from === to) {
      return { rate: 1, asOf: new Date().toISOString() };
    }

    const db = admin.firestore();
    const pairId = `${from}-${to}`;
    const cacheRef = db.doc(`fxRates/${pairId}`);
    const now = Date.now();

    // 1) Cache hit (fresh).
    const cacheSnap = await cacheRef.get();
    if (cacheSnap.exists) {
      const cached = cacheSnap.data() as CachedFxRate | undefined;
      const fetchedAt = cached?.fetchedAt;
      if (
        cached &&
        typeof cached.rate === 'number' &&
        fetchedAt &&
        now - fetchedAt.toMillis() < CACHE_TTL_MS
      ) {
        return { rate: cached.rate, asOf: fetchedAt.toDate().toISOString() };
      }
    }

    // 2) Quota check — only counts when we actually hit the provider.
    const yearMonth = formatYearMonth(new Date());
    const quotaRef = db.doc(`users/${uid}/aiUsage/${yearMonth}`);
    const quotaSnap = await quotaRef.get();
    const currentFxCount =
      (quotaSnap.exists && (quotaSnap.data()?.fx as number | undefined)) || 0;
    if (currentFxCount + 1 > MONTHLY_QUOTA_LIMIT) {
      throw new HttpsError(
        'resource-exhausted',
        `Monthly FX quota (${MONTHLY_QUOTA_LIMIT}) reached.`,
      );
    }

    // 3) Provider call. Fall back to stale cache on any failure.
    let providerRate: number | null = null;
    let providerError: unknown = null;
    try {
      const apiKey = EXCHANGERATE_API_KEY.value();
      const url = `https://v6.exchangerate-api.com/v6/${apiKey}/pair/${from}/${to}`;
      const res = await fetch(url);
      if (!res.ok) {
        throw new Error(`Provider HTTP ${res.status}`);
      }
      const body = (await res.json()) as ExchangeRateApiResponse;
      if (body.result !== 'success' || typeof body.conversion_rate !== 'number') {
        throw new Error(`Provider error: ${body['error-type'] ?? 'unknown'}`);
      }
      providerRate = body.conversion_rate;
    } catch (err) {
      providerError = err;
    }

    if (providerRate === null) {
      // Fallback: any cached value, regardless of freshness.
      if (cacheSnap.exists) {
        const cached = cacheSnap.data() as CachedFxRate | undefined;
        const fetchedAt = cached?.fetchedAt;
        if (cached && typeof cached.rate === 'number' && fetchedAt) {
          return { rate: cached.rate, asOf: fetchedAt.toDate().toISOString() };
        }
      }
      throw new HttpsError(
        'internal',
        `Failed to fetch FX rate: ${
          providerError instanceof Error ? providerError.message : 'unknown error'
        }`,
      );
    }

    // 4) Persist new cache entry + bump quota.
    const fetchedAtDate = new Date();
    await cacheRef.set(
      {
        rate: providerRate,
        from,
        to,
        fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await quotaRef.set(
      { fx: admin.firestore.FieldValue.increment(1) },
      { merge: true },
    );

    return { rate: providerRate, asOf: fetchedAtDate.toISOString() };
  },
);

/** Format a Date as `YYYY-MM` (UTC) for the `aiUsage` doc id. */
function formatYearMonth(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}
