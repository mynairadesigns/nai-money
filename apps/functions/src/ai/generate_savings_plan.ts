import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildSavingsPlanPrompt,
  type DiscretionaryCategory,
  type SavingsPlanContext,
} from '../prompts/generate_savings_plan';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const HISTORY_MONTHS = 3;
const DAY_MS = 24 * 60 * 60 * 1000;

interface SavingsPlanInput {
  goalId: string;
}

interface SavingsSuggestion {
  categoryName: string;
  currentMonthlySpend: number;
  suggestedCut: number;
  monthlySavingsImpact: number;
}

/**
 * Callable: AI Savings Coach — PRD §7.10.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate. Server reads the target goal, recent net savings, and
 * top discretionary categories; the model proposes a per-month
 * contribution + concrete spending cuts.
 */
export const generateSavingsPlan = onCall(
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
      key: 'generateSavingsPlan',
      windowSeconds: 60,
      maxCalls: 3,
    });
    await checkAndIncrementQuota({ uid, field: 'savingsPlan' });

    const input = _validateInput(request.data);
    const context = await buildSavingsContext(uid, input.goalId);

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : 'gemini-2.5-flash-lite';
    const provider = getProvider(providerName, model);

    const { system, user } = buildSavingsPlanPrompt(context);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('generateSavingsPlan: provider error', e);
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const requiredPerMonth = r.requiredPerMonth;
    const onTrack = r.onTrack;
    const suggestionsRaw = r.suggestions;
    const summary = r.summary;
    const timelineWeeks = r.timelineWeeks;
    if (
      typeof requiredPerMonth !== 'number' ||
      typeof onTrack !== 'boolean' ||
      !Array.isArray(suggestionsRaw) ||
      typeof summary !== 'string' ||
      typeof timelineWeeks !== 'number'
    ) {
      throw new HttpsError('internal', 'AI response missing required fields');
    }

    const suggestions: SavingsSuggestion[] = [];
    for (const s of suggestionsRaw) {
      if (typeof s !== 'object' || s === null) continue;
      const row = s as Record<string, unknown>;
      const categoryName = row.categoryName;
      const currentMonthlySpend = row.currentMonthlySpend;
      const suggestedCut = row.suggestedCut;
      const monthlySavingsImpact = row.monthlySavingsImpact;
      if (
        typeof categoryName === 'string' &&
        typeof currentMonthlySpend === 'number' &&
        typeof suggestedCut === 'number' &&
        typeof monthlySavingsImpact === 'number'
      ) {
        suggestions.push({
          categoryName,
          currentMonthlySpend: Math.max(0, currentMonthlySpend),
          suggestedCut: Math.max(0, suggestedCut),
          monthlySavingsImpact: Math.max(0, monthlySavingsImpact),
        });
      }
    }

    return {
      requiredPerMonth,
      onTrack,
      suggestions,
      summary,
      timelineWeeks,
    };
  },
);

function _validateInput(data: unknown): SavingsPlanInput {
  if (typeof data !== 'object' || data === null) {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const goalId = d.goalId;
  if (typeof goalId !== 'string' || goalId.trim() === '') {
    throw new HttpsError('invalid-argument', 'goalId must be a non-empty string');
  }
  return { goalId: goalId.trim() };
}

async function buildSavingsContext(
  uid: string,
  goalId: string,
): Promise<SavingsPlanContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const now = new Date();
  const historyStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - HISTORY_MONTHS, 1),
  );

  const goalRef = userRef.collection('goals').doc(goalId);

  const [userSnap, goalSnap, txSnap, categoriesSnap] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('generateSavingsPlan: user fetch failed', e);
      return null;
    }),
    goalRef.get().catch((e) => {
      console.warn('generateSavingsPlan: goal fetch failed', e);
      return null;
    }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(historyStart))
      .get()
      .catch((e) => {
        console.warn('generateSavingsPlan: tx fetch failed', e);
        return null;
      }),
    userRef
      .collection('categories')
      .get()
      .catch((e) => {
        console.warn('generateSavingsPlan: categories fetch failed', e);
        return null;
      }),
  ]);

  if (!goalSnap || !goalSnap.exists) {
    throw new HttpsError('not-found', 'Goal not found');
  }
  const goal = goalSnap.data() ?? {};

  const currency =
    _str(goal.currency, _str(userSnap?.data()?.defaultCurrency, 'USD'));

  const target = _num(goal.targetAmount, _num(goal.target, 0));
  const current = _num(goal.currentAmount, _num(goal.current, 0));
  const deadlineIso = _str(goal.deadline, _str(goal.targetDate, '')) || null;

  let daysRemaining: number | null = null;
  if (deadlineIso) {
    const deadline = new Date(deadlineIso);
    if (Number.isFinite(deadline.getTime())) {
      daysRemaining = Math.max(
        0,
        Math.ceil((deadline.getTime() - now.getTime()) / DAY_MS),
      );
    }
  }

  // Compute monthly net savings (income - expense) per month, averaged.
  const monthlyIncome = new Map<string, number>();
  const monthlyExpense = new Map<string, number>();
  // Discretionary category short list — categories whose name suggests they're
  // discretionary. We additionally include the top 5 by spend regardless,
  // so we always have suggestions to make.
  const discretionaryKeywords = [
    'dining',
    'eat',
    'restaurant',
    'food delivery',
    'entertainment',
    'shopping',
    'subscription',
    'coffee',
    'snack',
    'travel',
    'leisure',
    'hobby',
  ];

  const categoryNames = new Map<string, string>();
  categoriesSnap?.forEach((d) => {
    const name = _str(d.data().name, '');
    if (name) categoryNames.set(d.id, name);
  });

  const catSpend = new Map<string, number>();

  for (const d of txSnap?.docs ?? []) {
    const t = d.data();
    const dateIso = _str(t.date, '');
    if (dateIso.length < 7) continue;
    const label = dateIso.substring(0, 7);
    const amount = _num(t.amount, 0);
    const type = _str(t.type, '');
    if (type === 'income') {
      monthlyIncome.set(label, (monthlyIncome.get(label) ?? 0) + amount);
    } else if (type === 'expense') {
      monthlyExpense.set(label, (monthlyExpense.get(label) ?? 0) + amount);
      const catId = _str(t.categoryId, '');
      const catName = categoryNames.get(catId) ?? catId ?? '(uncategorized)';
      catSpend.set(catName, (catSpend.get(catName) ?? 0) + amount);
    }
  }

  const monthsSeen = new Set<string>([
    ...monthlyIncome.keys(),
    ...monthlyExpense.keys(),
  ]);
  let netTotal = 0;
  for (const label of monthsSeen) {
    netTotal +=
      (monthlyIncome.get(label) ?? 0) - (monthlyExpense.get(label) ?? 0);
  }
  const monthlyNetSavings =
    monthsSeen.size > 0 ? netTotal / monthsSeen.size : 0;

  // Build discretionary list: any category that matches a keyword first,
  // then padded with top-spenders.
  const allCategoriesSorted = Array.from(catSpend.entries()).sort(
    (a, b) => b[1] - a[1],
  );
  const keywordMatches = allCategoriesSorted.filter(([name]) => {
    const lower = name.toLowerCase();
    return discretionaryKeywords.some((kw) => lower.includes(kw));
  });
  const merged = new Map<string, number>();
  for (const [name, total] of keywordMatches) merged.set(name, total);
  for (const [name, total] of allCategoriesSorted) {
    if (merged.size >= 6) break;
    merged.set(name, total);
  }
  const topDiscretionary: DiscretionaryCategory[] = Array.from(
    merged.entries(),
  )
    .slice(0, 6)
    .map(([categoryName, total]) => ({
      categoryName,
      averageMonthlySpend: total / HISTORY_MONTHS,
    }));

  return {
    currency,
    goalName: _str(goal.name, 'Goal'),
    targetAmount: target,
    currentAmount: current,
    deadlineIso,
    daysRemaining,
    monthlyNetSavings,
    topDiscretionary,
  };
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
