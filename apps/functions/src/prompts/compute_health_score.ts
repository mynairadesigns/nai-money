/**
 * Prompt builder for the `computeHealthScore` callable. Based on PRD §7.11 —
 * the verbatim "AI narrative" template is preserved, with the JSON schema
 * extended to match the expanded callable contract that returns the full
 * 0–100 score, weighted factor breakdown, and actionable tips
 * (per CLAUDE.md §7: prompts are centralized).
 *
 * The server provides the seven raw component values from PRD §7.11
 * (savings rate, budget adherence, emergency fund coverage, debt-to-income
 * ratio, spending consistency, goal progress, subscription bloat).
 * The model maps each to a [-1, 1] signed value, applies the PRD weights,
 * and returns the aggregate score plus narrative.
 *
 * Output schema (validated in `apps/functions/src/ai/compute_health_score.ts`):
 * {
 *   score: number (0..100),
 *   label: 'excellent' | 'good' | 'fair' | 'poor',
 *   factors: Array<{
 *     name: string,
 *     weight: number (0..1),
 *     value: number (-1..1),
 *     explanation: string
 *   }>,
 *   actionableTips: string[]
 * }
 */

export interface HealthScoreContext {
  currency: string;
  monthlyIncome: number;
  monthlyExpense: number;
  savingsRate: number; // (income - expense) / income, can be negative
  budgetAdherencePct: number; // 0..1; share of active budgets currently under threshold
  emergencyFundMonths: number; // months of expenses covered by emergency goal
  debtToIncomeRatio: number; // totalDebt / monthlyIncome
  spendingConsistencyScore: number; // 0..1; 1 = perfectly consistent
  goalProgressAvgPct: number; // 0..1
  subscriptionShareOfIncome: number; // 0..1
}

export function buildHealthScorePrompt(ctx: HealthScoreContext): {
  system: string;
  user: string;
} {
  const system =
    'You are a personal finance health analyst. ' +
    'Given the user\'s raw component values, produce a weighted 0–100 score, ' +
    'a qualitative label, a per-factor breakdown, and actionable tips. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const user = `Default currency: ${ctx.currency}
Monthly income: ${_fmt(ctx.monthlyIncome)} ${ctx.currency}
Monthly expense: ${_fmt(ctx.monthlyExpense)} ${ctx.currency}

Raw component values:
- Savings rate: ${_fmt(ctx.savingsRate)} (target: ≥ 0.20)
- Budget adherence: ${_fmt(ctx.budgetAdherencePct)} (target: ≥ 0.80)
- Emergency fund coverage: ${_fmt(ctx.emergencyFundMonths)} months (target: ≥ 3.0)
- Debt-to-income ratio: ${_fmt(ctx.debtToIncomeRatio)} (target: ≤ 0.35)
- Spending consistency: ${_fmt(ctx.spendingConsistencyScore)} (target: ≥ 0.70)
- Goal progress (avg): ${_fmt(ctx.goalProgressAvgPct)} (target: ≥ 0.50)
- Subscription share of income: ${_fmt(ctx.subscriptionShareOfIncome)} (target: ≤ 0.05)

Weights (PRD §7.11):
- savingsRate: 0.25
- budgetAdherence: 0.20
- emergencyFund: 0.15
- debtToIncome: 0.15
- spendingConsistency: 0.10
- goalProgress: 0.10
- subscriptionBloat: 0.05

Label thresholds:
- excellent: score ≥ 80
- good: 60–79
- fair: 40–59
- poor: < 40

Map each raw component to a signed value in [-1, 1] (1 = far above target, 0 = on target, -1 = far below).
Compute score = round(50 + 50 * sum(weight_i * value_i)).
Clamp to 0..100.
Write a brief 1-sentence "explanation" per factor referencing the raw value.
List 2–4 short, concrete "actionableTips" focused on the lowest-scoring factors.

Return JSON with this exact schema:
{
  "score": number (0..100),
  "label": "excellent" | "good" | "fair" | "poor",
  "factors": [
    {
      "name": string,
      "weight": number (0..1),
      "value": number (-1..1),
      "explanation": string
    }
  ],
  "actionableTips": [string]
}`;

  return { system, user };
}

function _fmt(n: number): string {
  if (!Number.isFinite(n)) return '0';
  return n.toFixed(2);
}
