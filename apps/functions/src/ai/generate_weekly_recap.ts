import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildWeeklyRecapPrompt,
  type RecapCategoryTotal,
  type RecapGoalDelta,
  type WeeklyRecapContext,
} from '../prompts/generate_weekly_recap';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const DAY_MS = 24 * 60 * 60 * 1000;

interface WeeklyRecapInput {
  weekStart?: string;
}

/**
 * Callable: weekly recap — PRD §7.8.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate. Server gathers week totals + prior-week comparison + goal
 * deltas; the model writes a friendly narrative.
 */
export const generateWeeklyRecap = onCall(
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
      key: 'generateWeeklyRecap',
      windowSeconds: 60,
      maxCalls: 3,
    });
    await checkAndIncrementQuota({ uid, field: 'recap' });

    const input = _validateInput(request.data);
    const weekStart = _resolveWeekStart(input.weekStart);
    const weekEnd = new Date(weekStart.getTime() + 7 * DAY_MS);
    const priorWeekStart = new Date(weekStart.getTime() - 7 * DAY_MS);

    const context = await buildRecapContext(uid, priorWeekStart, weekStart, weekEnd);

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : 'gemini-2.5-flash-lite';
    const provider = getProvider(providerName, model);

    const { system, user } = buildWeeklyRecapPrompt(context);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('generateWeeklyRecap: provider error', e);
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const title = r.title;
    const highlightsRaw = r.highlights;
    const biggestSpendRaw = r.biggestSpend;
    const savingsThisWeek = r.savingsThisWeek;
    const insight = r.insight;
    if (
      typeof title !== 'string' ||
      !Array.isArray(highlightsRaw) ||
      typeof biggestSpendRaw !== 'object' ||
      biggestSpendRaw === null ||
      typeof savingsThisWeek !== 'number' ||
      typeof insight !== 'string'
    ) {
      throw new HttpsError('internal', 'AI response missing required fields');
    }

    const bs = biggestSpendRaw as Record<string, unknown>;
    if (
      typeof bs.categoryName !== 'string' ||
      typeof bs.amount !== 'number' ||
      typeof bs.currency !== 'string'
    ) {
      throw new HttpsError('internal', 'AI response: biggestSpend malformed');
    }

    const highlights: string[] = [];
    for (const h of highlightsRaw) {
      if (typeof h === 'string' && h.trim() !== '') highlights.push(h);
    }

    return {
      title,
      highlights,
      biggestSpend: {
        categoryName: bs.categoryName,
        amount: bs.amount,
        currency: bs.currency,
      },
      savingsThisWeek,
      insight,
    };
  },
);

function _validateInput(data: unknown): WeeklyRecapInput {
  if (data == null) return {};
  if (typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const weekStart = d.weekStart;
  if (weekStart !== undefined && weekStart !== null && typeof weekStart !== 'string') {
    throw new HttpsError('invalid-argument', 'weekStart must be an ISO date string');
  }
  return { weekStart: typeof weekStart === 'string' ? weekStart : undefined };
}

function _resolveWeekStart(input?: string): Date {
  if (input) {
    const parsed = new Date(input);
    if (Number.isFinite(parsed.getTime())) {
      // Normalize to midnight UTC.
      return new Date(
        Date.UTC(parsed.getUTCFullYear(), parsed.getUTCMonth(), parsed.getUTCDate()),
      );
    }
    throw new HttpsError('invalid-argument', 'weekStart must parse as a date');
  }
  // Default: last Monday (UTC).
  const now = new Date();
  const day = now.getUTCDay(); // 0=Sun, 1=Mon, ...
  const daysSinceMonday = (day + 6) % 7; // Mon=0, Tue=1, ..., Sun=6
  const monday = new Date(now.getTime() - daysSinceMonday * DAY_MS);
  return new Date(
    Date.UTC(
      monday.getUTCFullYear(),
      monday.getUTCMonth(),
      monday.getUTCDate(),
    ),
  );
}

async function buildRecapContext(
  uid: string,
  priorWeekStart: Date,
  weekStart: Date,
  weekEnd: Date,
): Promise<WeeklyRecapContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);

  const [userSnap, txSnap, categoriesSnap, goalsSnap] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('generateWeeklyRecap: user fetch failed', e);
      return null;
    }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(priorWeekStart))
      .where('date', '<', admin.firestore.Timestamp.fromDate(weekEnd))
      .get()
      .catch((e) => {
        console.warn('generateWeeklyRecap: tx fetch failed', e);
        return null;
      }),
    userRef
      .collection('categories')
      .get()
      .catch((e) => {
        console.warn('generateWeeklyRecap: categories fetch failed', e);
        return null;
      }),
    userRef
      .collection('goals')
      .get()
      .catch((e) => {
        console.warn('generateWeeklyRecap: goals fetch failed', e);
        return null;
      }),
  ]);

  const currency = _str(userSnap?.data()?.defaultCurrency, 'NGN');

  const categoryNames = new Map<string, string>();
  categoriesSnap?.forEach((d) => {
    const name = _str(d.data().name, '');
    if (name) categoryNames.set(d.id, name);
  });

  let weekIncome = 0;
  let weekExpenses = 0;
  let priorWeekIncome = 0;
  let priorWeekExpenses = 0;
  const categorySpend = new Map<string, number>();
  let largestExpense: {
    categoryName: string;
    amount: number;
    note: string;
  } | null = null;

  for (const d of txSnap?.docs ?? []) {
    const t = d.data();
    const amount = _num(t.amount, 0);
    const type = _str(t.type, '');
    const dateIso = _str(t.date, '');
    const date = new Date(dateIso);
    if (!Number.isFinite(date.getTime())) continue;
    const inCurrentWeek =
      date.getTime() >= weekStart.getTime() && date.getTime() < weekEnd.getTime();
    if (inCurrentWeek) {
      if (type === 'income') weekIncome += amount;
      else if (type === 'expense') {
        weekExpenses += amount;
        const catId = _str(t.categoryId, '');
        const catName = categoryNames.get(catId) ?? catId ?? '(uncategorized)';
        categorySpend.set(
          catName,
          (categorySpend.get(catName) ?? 0) + amount,
        );
        if (!largestExpense || amount > largestExpense.amount) {
          largestExpense = {
            categoryName: catName,
            amount,
            note: _str(t.note, ''),
          };
        }
      }
    } else {
      // Prior week.
      if (type === 'income') priorWeekIncome += amount;
      else if (type === 'expense') priorWeekExpenses += amount;
    }
  }

  const topCategories: RecapCategoryTotal[] = Array.from(
    categorySpend.entries(),
  )
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([categoryName, amount]) => ({ categoryName, amount }));

  const goalDeltas: RecapGoalDelta[] = (goalsSnap?.docs ?? [])
    .map((d) => d.data())
    .filter((g) => g.completedAt == null)
    .slice(0, 5)
    .map((g) => {
      const current = _num(g.currentAmount, _num(g.current, 0));
      const target = _num(g.targetAmount, _num(g.target, 0));
      return {
        name: _str(g.name, 'Goal'),
        // We don't track historical snapshots — approximate "before" as current,
        // so the delta is 0 unless a future iteration adds snapshotting.
        currentBefore: current,
        currentAfter: current,
        target,
      };
    });

  return {
    currency,
    weekStart: weekStart.toISOString().substring(0, 10),
    weekEnd: weekEnd.toISOString().substring(0, 10),
    weekIncome,
    weekExpenses,
    weekNet: weekIncome - weekExpenses,
    priorWeekIncome,
    priorWeekExpenses,
    priorWeekNet: priorWeekIncome - priorWeekExpenses,
    topCategories,
    largestExpense,
    goalDeltas,
  };
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
