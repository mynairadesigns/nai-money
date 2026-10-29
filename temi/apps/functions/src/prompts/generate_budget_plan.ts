/**
 * Prompt builder for the `generateBudgetPlan` callable. Based on PRD §7.9 —
 * the verbatim "AI Budget Generator" template is preserved, with the JSON
 * schema extended to match the expanded callable contract that returns the
 * full suggestion list plus an aggregate total and notes (per CLAUDE.md §7:
 * prompts are centralized).
 *
 * Output schema (validated in `apps/functions/src/ai/generate_budget_plan.ts`):
 * {
 *   suggestions: Array<{
 *     categoryId: string,                    // must match a provided id
 *     categoryName: string,
 *     suggestedAmount: number,
 *     reasoning: string                      // one sentence
 *   }>,
 *   totalSuggested: number,
 *   notes: string                            // overall recommendation
 * }
 */

export interface BudgetCategoryRef {
  id: string;
  name: string;
  averageMonthlySpend: number; // from last 3 months
  currentBudgetAmount?: number; // null/undefined if no active budget
}

export interface BudgetPlanContext {
  currency: string;
  monthlyIncome: number;
  expenseCategories: BudgetCategoryRef[];
  /** Last-3-month rolling expense total, for sanity-check context. */
  recentMonthlyExpenseAvg: number;
}

export function buildBudgetPlanPrompt(ctx: BudgetPlanContext): {
  system: string;
  user: string;
} {
  const system =
    'You are a budget planning assistant. ' +
    'Use the 50/30/20 rule as a baseline (50% needs, 30% wants, 20% savings/debt) ' +
    'and adjust for the user\'s actual spending history. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const categoryList = ctx.expenseCategories
    .map(
      (c) =>
        `  - { id: "${c.id}", name: "${c.name}", avgMonthlySpend: ${_fmt(c.averageMonthlySpend)}` +
        (c.currentBudgetAmount != null
          ? `, currentBudget: ${_fmt(c.currentBudgetAmount)}`
          : '') +
        ' }',
    )
    .join('\n');

  const user = `User profile:
- Monthly income: ${_fmt(ctx.monthlyIncome)} ${ctx.currency}
- Recent average monthly expenses (last 3 mo): ${_fmt(ctx.recentMonthlyExpenseAvg)} ${ctx.currency}

Available expense categories (id + name + recent average monthly spend, optional current budget):
${categoryList || '  (none)'}

Propose a monthly budget that sums to ≤ ${_fmt(ctx.monthlyIncome)} ${ctx.currency}.
Allocate to each category. Use the 50/30/20 rule as baseline, adjust for actual spending patterns.
Every "categoryId" must match one of the ids provided above — do not invent categories.

Return JSON with this exact schema:
{
  "suggestions": [
    {
      "categoryId": string,
      "categoryName": string,
      "suggestedAmount": number,
      "reasoning": string (one short sentence)
    }
  ],
  "totalSuggested": number,
  "notes": string (1–2 sentence overall recommendation)
}`;

  return { system, user };
}

function _fmt(n: number): string {
  if (!Number.isFinite(n)) return '0';
  return n.toFixed(2);
}
