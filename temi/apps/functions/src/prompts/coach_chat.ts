/**
 * Prompt builder for the `aiCoachChat` callable. PRD §7.5 template,
 * verbatim wording. Kept here so the prompt isn't inlined in the
 * callable handler (CLAUDE.md §7: prompts are centralized).
 *
 * Note: our provider abstraction only supports JSON-mode calls
 * (`generateJson({ system, user })`), so we instruct the model to
 * return `{ "reply": string }`. The user-facing chat surface unwraps
 * `.reply` before rendering.
 */

export interface CoachContext {
  defaultCurrency: string;
  totals: { income: number; expense: number; net: number };
  wallets: Array<{ name: string; balance: number; currency: string }>;
  topCategories: Array<{ name: string; amount: number }>;
  topMerchants: Array<{ name: string; amount: number }>;
  budgets: Array<{
    name: string;
    spent: number;
    total: number;
    currency: string;
  }>;
  goals: Array<{
    name: string;
    current: number;
    target: number;
    currency: string;
  }>;
  recentTransactions: Array<{
    note: string;
    amount: number;
    categoryName?: string;
    date: string;
  }>;
}

export interface CoachHistoryMsg {
  role: 'user' | 'assistant';
  content: string;
}

/** Default RAG window — matches PRD §7.5 "last 30 days" simplification. */
export const COACH_TIME_RANGE = '30 days';

export function buildCoachChatPrompt(opts: {
  context: CoachContext;
  history: CoachHistoryMsg[];
  userMessage: string;
}): { system: string; user: string } {
  const { context: ctx, history, userMessage } = opts;

  const topCategories =
    ctx.topCategories
      .map((c) => `${c.name} (${_fmt(c.amount)} ${ctx.defaultCurrency})`)
      .join(', ') || '(none)';

  const topMerchants =
    ctx.topMerchants
      .map((m) => `${m.name} (${_fmt(m.amount)} ${ctx.defaultCurrency})`)
      .join(', ') || '(none)';

  const budgetSummaries =
    ctx.budgets
      .map(
        (b) =>
          `${b.name}: ${_fmt(b.spent)}/${_fmt(b.total)} ${b.currency}`,
      )
      .join('; ') || '(none)';

  const goalSummaries =
    ctx.goals
      .map(
        (g) =>
          `${g.name}: ${_fmt(g.current)}/${_fmt(g.target)} ${g.currency}`,
      )
      .join('; ') || '(none)';

  const recentRelevantTransactionsJSON = JSON.stringify(
    ctx.recentTransactions,
  );

  // PRD §7.5 verbatim — plus the JSON-response instruction at the end.
  const system = `You are Coach Temi, the friendly and concise personal finance assistant inside the Temi Finance app.

The user's financial data context (last ${COACH_TIME_RANGE}):
- Total income: ${_fmt(ctx.totals.income)}
- Total expenses: ${_fmt(ctx.totals.expense)}
- Net savings: ${_fmt(ctx.totals.net)}
- Wallet balances: ${ctx.wallets.map((w) => `${w.name}: ${_fmt(w.balance)} ${w.currency}`).join(', ') || 'none'}
- Top 5 categories: ${topCategories}
- Top 5 merchants: ${topMerchants}
- Active budgets: ${budgetSummaries}
- Active goals: ${goalSummaries}

Recent relevant transactions:
${recentRelevantTransactionsJSON}

Default currency: ${ctx.defaultCurrency}

Guidelines:
- Be concise (2-4 sentences typical)
- Use the user's data directly, never invent numbers
- Suggest concrete actions when relevant
- Never give specific investment advice
- If asked about something not in the data, say so

Return ONLY a JSON object — no surrounding prose, no markdown fence — with this exact schema:
{ "reply": string }`;

  const transcript = history
    .map((m) => `${m.role}: ${m.content}`)
    .join('\n');

  const user = transcript
    ? `Previous conversation:
${transcript}

Current question:
${userMessage}`
    : `Current question:
${userMessage}`;

  return { system, user };
}

function _fmt(n: number): string {
  if (!Number.isFinite(n)) return '0';
  // Two decimals, no thousands separators — keeps the prompt compact and
  // the model doesn't need locale-aware parsing.
  return n.toFixed(2);
}
