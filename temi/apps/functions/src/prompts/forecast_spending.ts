/**
 * Prompt builder for the `forecastSpending` callable. Based on PRD §7.6 —
 * the verbatim "AI explanation" template is preserved, with the JSON
 * schema extended to match the expanded callable contract
 * (CLAUDE.md §7: prompts are centralized; the prompt file documents the
 * exact output schema the callable validates).
 *
 * Output schema (validated in `apps/functions/src/ai/forecast_spending.ts`):
 * {
 *   projectedTotal: number,                // end-of-month spending projection
 *   confidence: number (0..1),
 *   breakdown: Array<{
 *     categoryName: string,
 *     projected: number,
 *     trend: 'up' | 'down' | 'flat'
 *   }>,
 *   headline: string,                      // one-sentence card summary
 *   reasoning: string                      // 1-2 sentences justification
 * }
 */

export interface ForecastCategoryThisMonth {
  categoryName: string;
  spent: number;
}

export interface ForecastMonthTotal {
  label: string; // e.g. "2026-04"
  total: number;
}

export interface ForecastContext {
  currency: string;
  monthLabel: string; // e.g. "2026-05"
  dayOfMonth: number;
  totalDays: number;
  currentSpend: number;
  avgDaily: number;
  linearProjection: number;
  lastMonths: ForecastMonthTotal[]; // last 3 months totals
  currentCategoryBreakdown: ForecastCategoryThisMonth[];
}

export function buildForecastSpendingPrompt(ctx: ForecastContext): {
  system: string;
  user: string;
} {
  const system =
    'You are a financial forecasting assistant. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const historical = ctx.lastMonths
    .map((m) => `${m.label}: ${_fmt(m.total)} ${ctx.currency}`)
    .join(', ') || '(none)';

  const categoryBreakdown = JSON.stringify(ctx.currentCategoryBreakdown);

  const user = `Current month: ${ctx.monthLabel}, day ${ctx.dayOfMonth} of ${ctx.totalDays}.
Spent so far: ${_fmt(ctx.currentSpend)} ${ctx.currency}
Average daily spend so far: ${_fmt(ctx.avgDaily)} ${ctx.currency}
Linear projection (end of month): ${_fmt(ctx.linearProjection)} ${ctx.currency}
Last 3 months actuals: ${historical}
Spending by category this month: ${categoryBreakdown}

Return JSON with this exact schema:
{
  "projectedTotal": number,
  "confidence": number (0.0–1.0),
  "breakdown": [
    {
      "categoryName": string,
      "projected": number,
      "trend": "up" | "down" | "flat"
    }
  ],
  "headline": string (one short sentence summarising the forecast),
  "reasoning": string (1–2 sentences explaining what's driving the projection)
}`;

  return { system, user };
}

function _fmt(n: number): string {
  if (!Number.isFinite(n)) return '0';
  return n.toFixed(2);
}
