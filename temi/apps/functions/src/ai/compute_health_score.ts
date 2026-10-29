import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import {
  buildHealthScorePrompt,
  type HealthScoreContext,
} from '../prompts/compute_health_score';
import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import { REGION } from '../utils/region';
import { GEMINI_FAST } from '../providers/models';

if (!admin.apps.length) admin.initializeApp();

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

const WINDOW_DAYS = 30;
const HISTORY_MONTHS = 3;
const DAY_MS = 24 * 60 * 60 * 1000;

interface Factor {
  name: string;
  weight: number;
  value: number;
  explanation: string;
}

/**
 * Callable: financial health score — PRD §7.11.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → RAG fetch → provider →
 * JSON validate. Server computes the seven raw component values; the
 * model weights, clamps, and narrates them.
 */
export const computeHealthScore = onCall(
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
      key: 'computeHealthScore',
      windowSeconds: 60,
      maxCalls: 3,
    });
    const quota = await checkAndIncrementQuota({ uid, field: 'healthScore' });

    const context = await buildHealthScoreContext(uid);

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : GEMINI_FAST;
    const provider = getProvider(providerName, model);

    const { system, user } = buildHealthScorePrompt(context);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('computeHealthScore: provider error', e);
      await quota.refund();
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const score = r.score;
    const label = r.label;
    const factorsRaw = r.factors;
    const actionableTipsRaw = r.actionableTips;
    if (
      typeof score !== 'number' ||
      (label !== 'excellent' &&
        label !== 'good' &&
        label !== 'fair' &&
        label !== 'poor') ||
      !Array.isArray(factorsRaw) ||
      !Array.isArray(actionableTipsRaw)
    ) {
      throw new HttpsError('internal', 'AI response missing required fields');
    }

    const factors: Factor[] = [];
    for (const f of factorsRaw) {
      if (typeof f !== 'object' || f === null) continue;
      const row = f as Record<string, unknown>;
      if (
        typeof row.name === 'string' &&
        typeof row.weight === 'number' &&
        typeof row.value === 'number' &&
        typeof row.explanation === 'string'
      ) {
        factors.push({
          name: row.name,
          weight: row.weight,
          value: row.value,
          explanation: row.explanation,
        });
      }
    }

    const actionableTips: string[] = [];
    for (const t of actionableTipsRaw) {
      if (typeof t === 'string' && t.trim() !== '') actionableTips.push(t);
    }

    return {
      score: Math.max(0, Math.min(100, Math.round(score))),
      label,
      factors,
      actionableTips,
    };
  },
);

async function buildHealthScoreContext(
  uid: string,
): Promise<HealthScoreContext> {
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const now = new Date();
  const windowStart = new Date(now.getTime() - WINDOW_DAYS * DAY_MS);
  const historyStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - HISTORY_MONTHS, 1),
  );

  const [
    userSnap,
    txWindowSnap,
    txHistorySnap,
    budgetsSnap,
    goalsSnap,
    debtsSnap,
  ] = await Promise.all([
    userRef.get().catch((e) => {
      console.warn('computeHealthScore: user fetch failed', e);
      return null;
    }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(windowStart))
      .get()
      .catch((e) => {
        console.warn('computeHealthScore: window tx fetch failed', e);
        return null;
      }),
    userRef
      .collection('transactions')
      .where('date', '>=', admin.firestore.Timestamp.fromDate(historyStart))
      .get()
      .catch((e) => {
        console.warn('computeHealthScore: history tx fetch failed', e);
        return null;
      }),
    userRef
      .collection('budgets')
      .get()
      .catch((e) => {
        console.warn('computeHealthScore: budgets fetch failed', e);
        return null;
      }),
    userRef
      .collection('goals')
      .get()
      .catch((e) => {
        console.warn('computeHealthScore: goals fetch failed', e);
        return null;
      }),
    userRef
      .collection('debts')
      .get()
      .catch((e) => {
        console.warn('computeHealthScore: debts fetch failed', e);
        return null;
      }),
  ]);

  const userData = userSnap?.data() ?? {};
  const currency = _str(userData.defaultCurrency, 'NGN');

  // 30-day income vs expense.
  let monthlyIncome = 0;
  let monthlyExpense = 0;
  for (const d of txWindowSnap?.docs ?? []) {
    const t = d.data();
    const amount = _num(t.amount, 0);
    const type = _str(t.type, '');
    if (type === 'income') monthlyIncome += amount;
    else if (type === 'expense') monthlyExpense += amount;
  }

  // Use stated monthlyIncome as the fallback / floor — many users have
  // irregular income tracking and the user profile field is the most
  // honest signal we have.
  const statedIncome = _num(userData.monthlyIncome, 0);
  if (statedIncome > 0 && monthlyIncome === 0) {
    monthlyIncome = statedIncome;
  }

  const savingsRate =
    monthlyIncome > 0 ? (monthlyIncome - monthlyExpense) / monthlyIncome : 0;

  // Budget adherence: share of active budgets currently under threshold
  // (spent ≤ amount). Active = startDate ≤ now ≤ endDate (or endDate null).
  const nowIso = now.toISOString();
  let activeBudgets = 0;
  let adherentBudgets = 0;
  for (const d of budgetsSnap?.docs ?? []) {
    const b = d.data();
    const start = _str(b.startDate, '');
    const end = _str(b.endDate, '');
    const startsOk = !start || start <= nowIso;
    const endsOk = !end || end >= nowIso;
    if (!startsOk || !endsOk) continue;
    activeBudgets += 1;
    const spent = _num(b.spent, 0);
    const total = _num(b.amount, _num(b.total, 0));
    if (total > 0 && spent <= total) adherentBudgets += 1;
  }
  const budgetAdherencePct =
    activeBudgets > 0 ? adherentBudgets / activeBudgets : 1;

  // Emergency fund coverage: months covered by goals tagged as emergency
  // (name contains "emergency"). Fallback: 0.
  let emergencyCurrent = 0;
  for (const d of goalsSnap?.docs ?? []) {
    const g = d.data();
    const name = _str(g.name, '').toLowerCase();
    if (name.includes('emergency')) {
      emergencyCurrent += _num(g.currentAmount, _num(g.current, 0));
    }
  }
  const emergencyFundMonths =
    monthlyExpense > 0 ? emergencyCurrent / monthlyExpense : 0;

  // Debt-to-income: sum of remaining debt amounts / monthly income.
  let totalDebt = 0;
  for (const d of debtsSnap?.docs ?? []) {
    const debt = d.data();
    if (_str(debt.status, '') === 'settled') continue;
    totalDebt += _num(debt.remainingAmount, 0);
  }
  const debtToIncomeRatio = monthlyIncome > 0 ? totalDebt / monthlyIncome : 0;

  // Spending consistency: 1 - normalized stdev of monthly expense totals
  // over the last HISTORY_MONTHS+current. Clamp to [0, 1].
  const monthlyExpenseByLabel = new Map<string, number>();
  for (const d of txHistorySnap?.docs ?? []) {
    const t = d.data();
    if (_str(t.type, '') !== 'expense') continue;
    const dateIso = _str(t.date, '');
    if (dateIso.length < 7) continue;
    const label = dateIso.substring(0, 7);
    monthlyExpenseByLabel.set(
      label,
      (monthlyExpenseByLabel.get(label) ?? 0) + _num(t.amount, 0),
    );
  }
  const monthlyValues = Array.from(monthlyExpenseByLabel.values());
  const consistency = _consistencyScore(monthlyValues);

  // Goal progress: avg current/target across non-completed goals.
  let goalProgressSum = 0;
  let goalProgressCount = 0;
  for (const d of goalsSnap?.docs ?? []) {
    const g = d.data();
    const target = _num(g.targetAmount, _num(g.target, 0));
    const current = _num(g.currentAmount, _num(g.current, 0));
    if (target > 0) {
      goalProgressSum += Math.min(1, current / target);
      goalProgressCount += 1;
    }
  }
  const goalProgressAvgPct =
    goalProgressCount > 0 ? goalProgressSum / goalProgressCount : 0;

  // Subscription share: total recurringRules monthly equivalent / monthly income.
  // We approximate from the user's recurringRules subcollection.
  let subscriptionMonthly = 0;
  try {
    const recurringSnap = await userRef.collection('recurringRules').get();
    for (const d of recurringSnap.docs) {
      const r = d.data();
      if (r.isPaused === true) continue;
      const template = _parseTemplate(r.transactionTemplate);
      if (template?.type !== 'expense') continue;
      const amount = _num(template.amount, 0);
      const freq = _str(r.frequency, 'monthly');
      const interval = Math.max(1, _num(r.interval, 1));
      subscriptionMonthly += _monthlyEquivalent(amount, freq, interval);
    }
  } catch (e) {
    console.warn('computeHealthScore: recurringRules fetch failed', e);
  }
  const subscriptionShareOfIncome =
    monthlyIncome > 0 ? subscriptionMonthly / monthlyIncome : 0;

  return {
    currency,
    monthlyIncome,
    monthlyExpense,
    savingsRate,
    budgetAdherencePct,
    emergencyFundMonths,
    debtToIncomeRatio,
    spendingConsistencyScore: consistency,
    goalProgressAvgPct,
    subscriptionShareOfIncome,
  };
}

function _consistencyScore(values: number[]): number {
  if (values.length < 2) return 1;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  if (mean <= 0) return 1;
  const variance =
    values.reduce((acc, v) => acc + (v - mean) * (v - mean), 0) / values.length;
  const stdev = Math.sqrt(variance);
  const cv = stdev / mean; // coefficient of variation; lower = more consistent
  return Math.max(0, Math.min(1, 1 - cv));
}

function _parseTemplate(v: unknown): { type?: string; amount?: number } | null {
  if (typeof v === 'string') {
    try {
      return JSON.parse(v);
    } catch {
      return null;
    }
  }
  if (typeof v === 'object' && v !== null) {
    return v as { type?: string; amount?: number };
  }
  return null;
}

function _monthlyEquivalent(
  amount: number,
  frequency: string,
  interval: number,
): number {
  // Convert a rule's per-occurrence amount into a monthly cost.
  switch (frequency) {
    case 'daily':
      return (amount * 30) / interval;
    case 'weekly':
      return (amount * 4.345) / interval;
    case 'monthly':
      return amount / interval;
    case 'yearly':
      return amount / (12 * interval);
    default:
      return amount;
  }
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
