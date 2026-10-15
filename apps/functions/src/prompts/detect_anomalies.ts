/**
 * Prompt builder for the `detectAnomalies` callable. Based on PRD §7.7 —
 * the verbatim "anomaly explanation" template is preserved as a section
 * of the system prompt, with the JSON schema extended to match the
 * expanded callable contract (per CLAUDE.md §7: prompts are centralized).
 *
 * Anomaly trigger: any category whose 7-day spend is ≥ 2× the trailing
 * 4-week average (PRD §7.7).
 *
 * Output schema (validated in `apps/functions/src/ai/detect_anomalies.ts`):
 * {
 *   anomalies: Array<{
 *     transactionId?: string,                  // optional — single-tx anomaly
 *     categoryName: string,
 *     amount: number,
 *     currency: string,
 *     summary: string,
 *     severity: 'low' | 'medium' | 'high'
 *   }>,
 *   summary: string                             // headline; "" if no anomalies
 * }
 */

export interface AnomalyTopTransaction {
  transactionId: string;
  amount: number;
  note: string;
  date: string;
}

export interface AnomalyCandidate {
  categoryName: string;
  currentWeekSpend: number;
  averageWeekSpend: number;
  multiplier: number;
  topTransactions: AnomalyTopTransaction[];
}

export interface AnomalyContext {
  currency: string;
  candidates: AnomalyCandidate[];
}

export function buildDetectAnomaliesPrompt(ctx: AnomalyContext): {
  system: string;
  user: string;
} {
  const system =
    'You are a personal finance anomaly explainer. ' +
    'Given category-level spending spikes already detected by the server, ' +
    'classify their severity and write friendly one-sentence summaries. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const candidatesJson = JSON.stringify(ctx.candidates);

  const user = `Default currency: ${ctx.currency}

Detected category spikes (current 7-day spend vs. trailing 4-week average):
${candidatesJson}

Severity rules:
- low: multiplier between 2.0 and 2.5
- medium: multiplier between 2.5 and 4.0
- high: multiplier > 4.0

For each candidate, write a one-sentence "summary" (e.g. "Coffee spending is 3× last month's average").
If the spike is driven by a single transaction in topTransactions, set "transactionId" to that id and "amount" to its amount; otherwise omit transactionId and set "amount" to the category's currentWeekSpend.

Return JSON with this exact schema:
{
  "anomalies": [
    {
      "transactionId": string | undefined,
      "categoryName": string,
      "amount": number,
      "currency": string,
      "summary": string,
      "severity": "low" | "medium" | "high"
    }
  ],
  "summary": string (one-line headline across all anomalies; empty string if anomalies is empty)
}

If the candidates list is empty, return:
{ "anomalies": [], "summary": "" }`;

  return { system, user };
}
