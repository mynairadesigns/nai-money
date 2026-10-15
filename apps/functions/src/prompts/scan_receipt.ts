/**
 * Prompt builder for the `scanReceipt` callable. PRD §7.2 template,
 * verbatim wording. The image itself is delivered to the provider via
 * `generateJsonWithImage`; this builder only emits the text portion.
 */
export interface CategoryRef {
  id: string;
  name: string;
}

export interface ScanReceiptInput {
  defaultCurrency: string;
  expenseCategories: CategoryRef[];
}

export function buildScanReceiptPrompt(i: ScanReceiptInput): {
  system: string;
  user: string;
} {
  const system =
    'You are a receipt-parsing assistant. ' +
    'Return ONLY a JSON object — no surrounding prose, no markdown fence.';

  const categoryList = i.expenseCategories
    .map((c) => `  - { id: "${c.id}", name: "${c.name}" }`)
    .join('\n');

  const user = `Extract structured data from the attached receipt image.

User context:
- Default currency: ${i.defaultCurrency}
- Available expense categories:
${categoryList || '  (none)'}

Return JSON with this exact schema:
{
  "merchant": string,
  "total": number,
  "currency": string (ISO 4217 — fall back to defaultCurrency if the receipt doesn't show one),
  "date": string (ISO 8601),
  "suggestedCategoryId": string (one of the provided category IDs),
  "lineItems": [{ "description": string, "amount": number }],
  "confidence": number (0.0–1.0),
  "notes": string (optional — only present if confidence < 0.5, explaining what was hard to read)
}

If you cannot read the receipt clearly, set confidence < 0.5 and put what you could extract anyway.`;

  return { system, user };
}
