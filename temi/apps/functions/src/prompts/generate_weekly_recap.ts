/**
 * Prompt builder for the `generateWeeklyRecap` callable. Based on PRD §7.8 —
 * the verbatim recap template is preserved, with the JSON schema extended
 * to match the expanded callable contract (per CLAUDE.md §7: prompts are
 * centralized).
 *
 * Output schema (validated in `apps/functions/src/ai/generate_weekly_recap.ts`):
 * {
 *   title: string,                          // e.g. "Week of Oct 23"
 *   highlights: string[],                   // 3–5 short bullet points
 *   biggestSpend: {
 *     categoryName: string,
 *     amount: number,
 *     currency: string
 *   },
 *   savingsThisWeek: number,
 *   insight: string                         // friendly closer paragraph
 * }
 */

export interface RecapCategoryTotal {
  categoryName: string;
  amount: number;
}

export interface RecapGoalDelta {
  name: string;
  currentBefore: number;
  currentAfter: number;
  target: number;
}

export interface WeeklyRecapContext {
  currency: string;
  weekStart: string; // ISO date
  weekEnd: string; // ISO date
  weekIncome: number;
  weekExpenses: number;
  weekNet: number;
  priorWeekIncome: number;
  priorWeekExpenses: number;
  priorWeekNet: number;
  topCategories: RecapCategoryTotal[];
  largestExpense: {
    categoryName: string;
    amount: number;
    note: string;
  } | null;
  goalDeltas: RecapGoalDelta[];
}

export function buildWeeklyRecapPrompt(ctx: WeeklyRecapContext): {
  system: string;
  user: string;
} {
  const system =
    'You are Temi Finance Recap. Generate a friendly weekly summary. ' +
    'Tone: encouraging, not preachy. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const topCategoriesText =
    ctx.topCategories
      .map((c) => `${c.categoryName} (${_fmt(c.amount)} ${ctx.currency})`)
      .join(', ') || '(none)';

  const largestExpenseText = ctx.largestExpense
    ? `${ctx.largestExpense.categoryName} — ${_fmt(ctx.largestExpense.amount)} ${ctx.currency} (${ctx.largestExpense.note || 'no note'})`
    : '(none)';

  const goalDeltaText =
    ctx.goalDeltas
      .map(
        (g) =>
          `${g.name}: ${_fmt(g.currentBefore)} → ${_fmt(g.currentAfter)} / ${_fmt(g.target)}`,
      )
      .join('; ') || '(none)';

  const comparison =
    `expenses ${_diffPct(ctx.weekExpenses, ctx.priorWeekExpenses)}, ` +
    `net ${_fmt(ctx.weekNet - ctx.priorWeekNet)} vs prior week`;

  const user = `Week of ${ctx.weekStart} to ${ctx.weekEnd}:
- Total income: ${_fmt(ctx.weekIncome)} ${ctx.currency}
- Total expenses: ${_fmt(ctx.weekExpenses)} ${ctx.currency}
- Net: ${_fmt(ctx.weekNet)} ${ctx.currency}
- Compared to prior week: ${comparison}
- Top 3 categories: ${topCategoriesText}
- Largest single expense: ${largestExpenseText}
- Active goal progress: ${goalDeltaText}

Generate a friendly recap. The "insight" must be max 4 sentences with one piece of actionable advice.
Tone: encouraging, not preachy.

Return JSON with this exact schema:
{
  "title": string (e.g. "Week of Oct 23"),
  "highlights": [string] (3–5 short bullet points),
  "biggestSpend": {
    "categoryName": string,
    "amount": number,
    "currency": string
  },
  "savingsThisWeek": number,
  "insight": string
}

Use ${ctx.currency} as the currency in biggestSpend. If there were no expenses this week, set biggestSpend.categoryName to "None" and amount to 0.`;

  return { system, user };
}

function _fmt(n: number): string {
  if (!Number.isFinite(n)) return '0';
  return n.toFixed(2);
}

function _diffPct(current: number, prior: number): string {
  if (!Number.isFinite(prior) || prior === 0) return 'n/a';
  const pct = ((current - prior) / Math.abs(prior)) * 100;
  const sign = pct >= 0 ? '+' : '';
  return `${sign}${pct.toFixed(1)}%`;
}
