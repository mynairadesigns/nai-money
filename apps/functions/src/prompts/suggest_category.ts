/**
 * Prompt builder for the `suggestCategory` callable. PRD §7.3 template,
 * verbatim wording. Kept here so the prompt isn't inlined in the
 * callable handler (CLAUDE.md §7: prompts are centralized).
 */
export interface CategoryRef {
  id: string;
  name: string;
}

export interface RecentTransaction {
  note?: string;
  categoryId: string;
}

export interface SuggestCategoryInput {
  type: 'expense' | 'income';
  amount: number;
  currency: string;
  note?: string;
  merchant?: string;
  expenseCategories: CategoryRef[];
  incomeCategories: CategoryRef[];
  recentTransactions?: RecentTransaction[];
}

export function buildSuggestCategoryPrompt(i: SuggestCategoryInput): {
  system: string;
  user: string;
} {
  const system =
    'You are a transaction categorization assistant. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const expenseList = i.expenseCategories
    .map((c) => `  - { id: "${c.id}", name: "${c.name}" }`)
    .join('\n');
  const incomeList = i.incomeCategories
    .map((c) => `  - { id: "${c.id}", name: "${c.name}" }`)
    .join('\n');

  const recentList = (i.recentTransactions ?? [])
    .map(
      (t) =>
        `  - { note: ${JSON.stringify(t.note ?? '')}, categoryId: "${t.categoryId}" }`,
    )
    .join('\n');

  const user = `Available categories (expense):
${expenseList || '  (none)'}

Available categories (income):
${incomeList || '  (none)'}

Recent user transactions (for pattern learning):
${recentList || '  (none)'}

New transaction:
- Type: ${i.type}
- Amount: ${i.amount} ${i.currency}
- Note: ${JSON.stringify(i.note ?? '')}
- Merchant: ${JSON.stringify(i.merchant ?? '')}

Return JSON with this exact schema:
{
  "suggestedCategoryId": string (one of the provided category IDs from the matching type),
  "confidence": number (0.0–1.0),
  "reasoning": string (one short sentence)
}`;

  return { system, user };
}
