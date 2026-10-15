import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import {
  buildScanReceiptPrompt,
  type ScanReceiptInput,
} from '../prompts/scan_receipt';
import { REGION } from '../utils/region';

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

/**
 * Callable: AI-parse a receipt image into a structured transaction.
 *
 * Per CLAUDE.md §7: auth → rate-limit (tighter — receipts are heavy) →
 * quota → provider → JSON validate.
 * Feature default provider is **OpenAI GPT-4o** (best vision OCR);
 * Remote Config `ai_provider` can override globally.
 *
 * Input (PRD §7.2):
 *   { imageUrl: string, defaultCurrency: string, expenseCategories: [...] }
 *
 * Response (PRD §7.2):
 *   { merchant, total, currency, date, suggestedCategoryId,
 *     lineItems[], confidence, notes? }
 *
 * Confidence < 0.5 → still returned; client surfaces the manual-prefill
 * fallback (PRD §7.2).
 */
export const scanReceipt = onCall(
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
      key: 'scanReceipt',
      windowSeconds: 60,
      maxCalls: 3,
    });
    await checkAndIncrementQuota({ uid, field: 'scan' });

    const { input, imageUrl } = _validateInput(request.data);

    const providerName = await selectProvider({ featureDefault: 'openai' });
    const model = providerName === 'openai' ? 'gpt-4o' : 'gemini-2.5-flash';
    const provider = getProvider(providerName, model);

    const { system, user } = buildScanReceiptPrompt(input);

    let raw: unknown;
    try {
      raw = await provider.generateJsonWithImage({ system, user, imageUrl });
    } catch (e) {
      console.error('scanReceipt: provider error', e);
      throw new HttpsError('internal', 'AI provider error');
    }

    return _validateOutput(raw, input.defaultCurrency);
  },
);

function _validateInput(data: unknown): {
  input: ScanReceiptInput;
  imageUrl: string;
} {
  if (typeof data !== 'object' || data === null) {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const imageUrl = d.imageUrl;
  if (typeof imageUrl !== 'string' || imageUrl.length === 0) {
    throw new HttpsError('invalid-argument', 'imageUrl is required');
  }
  const defaultCurrency = d.defaultCurrency;
  if (typeof defaultCurrency !== 'string') {
    throw new HttpsError('invalid-argument', 'defaultCurrency is required');
  }
  const expenseCategories = Array.isArray(d.expenseCategories)
    ? d.expenseCategories
        .filter(
          (x): x is Record<string, unknown> =>
            typeof x === 'object' && x !== null,
        )
        .map((x) => ({ id: String(x.id ?? ''), name: String(x.name ?? '') }))
        .filter((x) => x.id !== '')
    : [];
  return { input: { defaultCurrency, expenseCategories }, imageUrl };
}

function _validateOutput(raw: unknown, defaultCurrency: string): {
  merchant: string;
  total: number;
  currency: string;
  date: string;
  suggestedCategoryId: string;
  lineItems: Array<{ description: string; amount: number }>;
  confidence: number;
  notes?: string;
} {
  if (typeof raw !== 'object' || raw === null) {
    throw new HttpsError('internal', 'Malformed AI response');
  }
  const r = raw as Record<string, unknown>;
  const merchant = String(r.merchant ?? '');
  const totalNum = typeof r.total === 'number' ? r.total : Number(r.total);
  if (!Number.isFinite(totalNum)) {
    throw new HttpsError('internal', 'AI response: total must be a number');
  }
  const currency =
    typeof r.currency === 'string' && r.currency.length > 0
      ? r.currency
      : defaultCurrency;
  const date = typeof r.date === 'string' ? r.date : new Date().toISOString();
  const suggestedCategoryId = String(r.suggestedCategoryId ?? '');
  const lineItems = Array.isArray(r.lineItems)
    ? r.lineItems
        .filter(
          (x): x is Record<string, unknown> =>
            typeof x === 'object' && x !== null,
        )
        .map((x) => ({
          description: String(x.description ?? ''),
          amount: typeof x.amount === 'number' ? x.amount : Number(x.amount) || 0,
        }))
    : [];
  const confidence =
    typeof r.confidence === 'number'
      ? Math.max(0, Math.min(1, r.confidence))
      : 0;
  const notes = typeof r.notes === 'string' ? r.notes : undefined;
  return {
    merchant,
    total: totalNum,
    currency,
    date,
    suggestedCategoryId,
    lineItems,
    confidence,
    notes,
  };
}
