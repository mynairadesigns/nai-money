/**
 * Prompt builder for the `generateSavingsPlan` callable. Based on PRD §7.10
 * (AI Savings Coach) — the verbatim template is preserved, with the JSON
 * schema extended to match the expanded callable contract that returns the
 * monthly required contribution, on-track flag, per-category cut
 * suggestions, summary, and timeline (per CLAUDE.md §7: prompts are
 * centralized).
 *
 * Output schema (validated in `apps/functions/src/ai/generate_savings_plan.ts`):
 * {
 *   requiredPerMonth: number,
 *   onTrack: boolean,
 *   suggestions: Array<{
 *     categoryName: string,
 *     currentMonthlySpend: number,
 *     suggestedCut: number,
 *     monthlySavingsImpact: number
 *   }>,
 *   summary: string,
 *   timelineWeeks: number                    // weeks to goal at suggested rate
 * }
 */

export interface DiscretionaryCategory {
  categoryName: string;
  averageMonthlySpend: number;
}

export interface SavingsPlanContext {
  currency: string;
  goalName: string;
  targetAmount: number;
  currentAmount: number;
  deadlineIso: string | null;
  daysRemaining: number | null;
  monthlyNetSavings: number; // average net savings per month over recent window
  topDiscretionary: DiscretionaryCategory[];
}

export function buildSavingsPlanPrompt(ctx: SavingsPlanContext): {
  system: string;
  user: string;
} {
  const system =
    'You are a savings planning assistant. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const deadlineText = ctx.deadlineIso ?? '(no deadline)';
  const daysRemainingText =
    ctx.daysRemaining == null ? '(no deadline)' : String(ctx.daysRemaining);
  const discretionaryText = JSON.stringify(ctx.topDiscretionary);

  const user = `Goal: "${ctx.goalName}"
Target: ${_fmt(ctx.targetAmount)} ${ctx.currency}
Current: ${_fmt(ctx.currentAmount)} ${ctx.currency}
Deadline: ${deadlineText}
Days remaining: ${daysRemainingText}

User's recent average monthly net savings: ${_fmt(ctx.monthlyNetSavings)} ${ctx.currency}
Top discretionary categories: ${discretionaryText}

Propose a savings plan. Include:
- requiredPerMonth: monthly contribution needed to hit the target by the deadline (if no deadline, suggest a sensible 12-month plan)
- onTrack: true if the user's monthlyNetSavings ≥ requiredPerMonth, else false
- suggestions: 2–3 specific cuts from discretionary categories the user could make. Each entry must include the category's currentMonthlySpend and a non-negative suggestedCut (≤ currentMonthlySpend) plus its monthlySavingsImpact (= suggestedCut)
- summary: 1–2 sentence friendly explanation
- timelineWeeks: weeks until goal at requiredPerMonth (assume 4.345 weeks/month)

Return JSON with this exact schema:
{
  "requiredPerMonth": number,
  "onTrack": boolean,
  "suggestions": [
    {
      "categoryName": string,
      "currentMonthlySpend": number,
      "suggestedCut": number,
      "monthlySavingsImpact": number
    }
  ],
  "summary": string,
  "timelineWeeks": number
}`;

  return { system, user };
}

function _fmt(n: number): string {
  if (!Number.isFinite(n)) return '0';
  return n.toFixed(2);
}
