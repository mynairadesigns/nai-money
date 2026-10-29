import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildForecastSpendingPrompt,
  type ForecastCategoryThisMonth,
  type ForecastContext,
  type ForecastMonthTotal,
} from '../prompts/forecast_spending';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';
import { GEMINI_FAST } from '../providers/models';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const HISTORY_MONTHS = 3;
const DAY_MS = 24 * 60 * 60 * 1000;

interface BreakdownItem {
  categoryName: string;
  projected: number;
  trend: 'up' | 'down' | 'flat';
}

/**
 * Callable: end-of-month spending forecast — PRD §7.6.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate. Server computes the linear projection statistically and
 * the model adds narrative + per-category breakdown.
 */
export const forecastSpending = onCall(
  {
    region: REGION,
    memory: '512MiB',
    timeoutSeconds: 60,
    secrets: [OPENAI_API_KEY, GEMINI_API_KEY],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }
    const uid = request.auth.uid;

    enforceRateLimit({
      uid,
      key: 'forecastSpending',
      windowSeconds: 60,
      maxCalls: 3,
    });
    const quota = await checkAndIncrementQuota({ uid, field: 'forecast' });

    const context = await buildForecastContext(uid);

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : GEMINI_FAST;
    const provider = getProvider(providerName, model);

    const { system, user } = buildForecastSpendingPrompt(context);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('forecastSpending: provider error', e);
      await quota.refund();
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const projectedTotal = r.projectedTotal;
    const confidence = r.confidence;
    const breakdownRaw = r.breakdown;
    const headline = r.headline;
    const reasoning = r.reasoning;
    if (
      typeof projectedTotal !== 'number' ||
      typeof confidence !== 'number' ||
      !Array.isArray(breakdownRaw) ||
      typeof headline !== 'string' ||
      typeof reasoning !== 'string'
    ) {
      throw new HttpsError('internal', 'AI response missing required fields');
    }

    const breakdown: BreakdownItem[] = [];
    for (const b of breakdownRaw) {
      if (typeof b !== 'object' || b === null) continue;
      const row = b as Record<string, unknown>;
      const categoryName = row.categoryName;
      const projected = row.projected;
      const trend = row.trend;
      if (
        typeof categoryName === 'string' &&
        typeof projected === 'number' &&
        (trend === 'up' || trend === 'down' || trend === 'flat')
      ) {
        breakdown.push({ categoryName, projected, trend });
      }
    }

    return { projectedTotal, confidence, breakdown, headline, reasoning };
  },
);

async function buildForecastContext(uid: string): Promise<ForecastContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const now = new Date();

  const monthStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
  );
  const nextMonthStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1),
  );
  const totalDays = Math.round(
    (nextMonthStart.getTime() - monthStart.getTime()) / DAY_MS,
  );
  const dayOfMonth = now.getUTCDate();
  const monthLabel = `${now.getUTCFullYear()}-${_pad(now.getUTCMonth() + 1)}`;

  // Fetch transactions for current month + last HISTORY_MONTHS months.
  const historyStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - HISTORY_MONTHS, 1),
  );

  const [userSnap, txSnap, categoriesSnap] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('forecastSpending: user fetch failed', e);
      return null;
    }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(historyStart))
      .get()
      .catch((e) => {
        console.warn('forecastSpending: transactions fetch failed', e);
        return null;
      }),
    userRef
      .collection('categories')
      .get()
      .catch((e) => {
        console.warn('forecastSpending: categories fetch failed', e);
        return null;
      }),
  ]);

  const currency = _str(userSnap?.data()?.defaultCurrency, 'NGN');

  const categoryNames = new Map<string, string>();
  categoriesSnap?.forEach((d) => {
    const name = _str(d.data().name, '');
    if (name) categoryNames.set(d.id, name);
  });

  const txs = (txSnap?.docs ?? []).map((d) => d.data());

  // Build per-month expense totals + this-month category breakdown.
  const monthlyTotals = new Map<string, number>();
  const currentCategorySpend = new Map<string, number>();
  let currentSpend = 0;

  const monthLabelOf = (iso: string): string => {
    // ISO date string YYYY-MM-DD...; first 7 chars suffice.
    return iso.length >= 7 ? iso.substring(0, 7) : '';
  };

  for (const t of txs) {
    if (_str(t.type, '') !== 'expense') continue;
    const amount = _num(t.amount, 0);
    const dateIso = _str(t.date, '');
    const mLabel = monthLabelOf(dateIso);
    if (!mLabel) continue;
    monthlyTotals.set(mLabel, (monthlyTotals.get(mLabel) ?? 0) + amount);
    if (mLabel === monthLabel) {
      currentSpend += amount;
      const catId = _str(t.categoryId, '');
      const catName = categoryNames.get(catId) ?? catId ?? '(uncategorized)';
      currentCategorySpend.set(
        catName,
        (currentCategorySpend.get(catName) ?? 0) + amount,
      );
    }
  }

  const lastMonths: ForecastMonthTotal[] = [];
  for (let i = HISTORY_MONTHS; i >= 1; i--) {
    const d = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1),
    );
    const label = `${d.getUTCFullYear()}-${_pad(d.getUTCMonth() + 1)}`;
    lastMonths.push({ label, total: monthlyTotals.get(label) ?? 0 });
  }

  const avgDaily = dayOfMonth > 0 ? currentSpend / dayOfMonth : 0;
  const linearProjection = avgDaily * totalDays;

  const currentCategoryBreakdown: ForecastCategoryThisMonth[] = Array.from(
    currentCategorySpend.entries(),
  )
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([categoryName, spent]) => ({ categoryName, spent }));

  return {
    currency,
    monthLabel,
    dayOfMonth,
    totalDays,
    currentSpend,
    avgDaily,
    linearProjection,
    lastMonths,
    currentCategoryBreakdown,
  };
}

function _pad(n: number): string {
  return String(n).padStart(2, '0');
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
