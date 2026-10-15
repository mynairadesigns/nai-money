import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildBudgetPlanPrompt,
  type BudgetCategoryRef,
  type BudgetPlanContext,
} from '../prompts/generate_budget_plan';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const HISTORY_MONTHS = 3;

interface BudgetPlanInput {
  monthlyIncome?: number;
  currency?: string;
}

interface BudgetSuggestion {
  categoryId: string;
  categoryName: string;
  suggestedAmount: number;
  reasoning: string;
}

/**
 * Callable: AI budget generator — PRD §7.9.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate. Server reads the user's last 3 months of transactions,
 * current active budgets, and category list; the model proposes amounts.
 *
 * Output suggestions are filtered to those whose `categoryId` matches a
 * real category for the user — the model can't invent new categories.
 */
export const generateBudgetPlan = onCall(
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
      key: 'generateBudgetPlan',
      windowSeconds: 60,
      maxCalls: 3,
    });
    await checkAndIncrementQuota({ uid, field: 'budgetPlan' });

    const input = _validateInput(request.data);
    const context = await buildBudgetContext(uid, input);

    if (context.expenseCategories.length === 0) {
      throw new HttpsError(
        'failed-precondition',
        'No expense categories found — set up categories first',
      );
    }
    if (context.monthlyIncome <= 0) {
      throw new HttpsError(
        'failed-precondition',
        'Monthly income is missing — pass monthlyIncome or set it in your profile',
      );
    }

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : 'gemini-2.5-flash-lite';
    const provider = getProvider(providerName, model);

    const { system, user } = buildBudgetPlanPrompt(context);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('generateBudgetPlan: provider error', e);
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const suggestionsRaw = r.suggestions;
    const totalSuggested = r.totalSuggested;
    const notes = r.notes;
    if (
      !Array.isArray(suggestionsRaw) ||
      typeof totalSuggested !== 'number' ||
      typeof notes !== 'string'
    ) {
      throw new HttpsError('internal', 'AI response missing required fields');
    }

    const validIds = new Set(context.expenseCategories.map((c) => c.id));
    const suggestions: BudgetSuggestion[] = [];
    for (const s of suggestionsRaw) {
      if (typeof s !== 'object' || s === null) continue;
      const row = s as Record<string, unknown>;
      const categoryId = row.categoryId;
      const categoryName = row.categoryName;
      const suggestedAmount = row.suggestedAmount;
      const reasoning = row.reasoning;
      if (
        typeof categoryId === 'string' &&
        validIds.has(categoryId) &&
        typeof categoryName === 'string' &&
        typeof suggestedAmount === 'number' &&
        suggestedAmount >= 0 &&
        typeof reasoning === 'string'
      ) {
        suggestions.push({
          categoryId,
          categoryName,
          suggestedAmount,
          reasoning,
        });
      }
    }

    const totalFromValid = suggestions.reduce(
      (a, s) => a + s.suggestedAmount,
      0,
    );

    return {
      suggestions,
      totalSuggested: totalFromValid,
      notes,
    };
  },
);

function _validateInput(data: unknown): BudgetPlanInput {
  if (data == null) return {};
  if (typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const monthlyIncome = d.monthlyIncome;
  const currency = d.currency;
  if (
    monthlyIncome !== undefined &&
    monthlyIncome !== null &&
    (typeof monthlyIncome !== 'number' || !Number.isFinite(monthlyIncome) || monthlyIncome < 0)
  ) {
    throw new HttpsError(
      'invalid-argument',
      'monthlyIncome must be a non-negative number',
    );
  }
  if (currency !== undefined && currency !== null && typeof currency !== 'string') {
    throw new HttpsError('invalid-argument', 'currency must be a string');
  }
  return {
    monthlyIncome: typeof monthlyIncome === 'number' ? monthlyIncome : undefined,
    currency: typeof currency === 'string' ? currency : undefined,
  };
}

async function buildBudgetContext(
  uid: string,
  input: BudgetPlanInput,
): Promise<BudgetPlanContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const now = new Date();
  const historyStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - HISTORY_MONTHS, 1),
  );

  const [userSnap, txSnap, categoriesSnap, budgetsSnap] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('generateBudgetPlan: user fetch failed', e);
      return null;
    }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(historyStart))
      .get()
      .catch((e) => {
        console.warn('generateBudgetPlan: tx fetch failed', e);
        return null;
      }),
    userRef
      .collection('categories')
      .get()
      .catch((e) => {
        console.warn('generateBudgetPlan: categories fetch failed', e);
        return null;
      }),
    userRef
      .collection('budgets')
      .get()
      .catch((e) => {
        console.warn('generateBudgetPlan: budgets fetch failed', e);
        return null;
      }),
  ]);

  const userData = userSnap?.data() ?? {};
  const currency =
    input.currency ?? _str(userData.defaultCurrency, 'NGN');
  const monthlyIncome =
    input.monthlyIncome ?? _num(userData.monthlyIncome, 0);

  // Sum expense spend per categoryId across the history window.
  const expenseSumByCat = new Map<string, number>();
  let totalExpense = 0;
  for (const d of txSnap?.docs ?? []) {
    const t = d.data();
    if (_str(t.type, '') !== 'expense') continue;
    const catId = _str(t.categoryId, '');
    if (!catId) continue;
    const amount = _num(t.amount, 0);
    expenseSumByCat.set(catId, (expenseSumByCat.get(catId) ?? 0) + amount);
    totalExpense += amount;
  }

  // Current active budget amount per categoryId.
  const nowIso = now.toISOString();
  const currentBudgetByCat = new Map<string, number>();
  for (const d of budgetsSnap?.docs ?? []) {
    const b = d.data();
    const catId = _str(b.categoryId, '');
    if (!catId) continue;
    const start = _str(b.startDate, '');
    const end = _str(b.endDate, '');
    const startsOk = !start || start <= nowIso;
    const endsOk = !end || end >= nowIso;
    if (!startsOk || !endsOk) continue;
    currentBudgetByCat.set(catId, _num(b.amount, _num(b.total, 0)));
  }

  // Filter to expense categories.
  const expenseCategories: BudgetCategoryRef[] = [];
  categoriesSnap?.forEach((d) => {
    const c = d.data();
    const type = _str(c.type, '');
    if (type !== 'expense') return;
    const id = d.id;
    const name = _str(c.name, '');
    if (!name) return;
    const totalForCat = expenseSumByCat.get(id) ?? 0;
    expenseCategories.push({
      id,
      name,
      averageMonthlySpend: totalForCat / HISTORY_MONTHS,
      currentBudgetAmount: currentBudgetByCat.get(id),
    });
  });

  return {
    currency,
    monthlyIncome,
    expenseCategories,
    recentMonthlyExpenseAvg: totalExpense / HISTORY_MONTHS,
  };
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
