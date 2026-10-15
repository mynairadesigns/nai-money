import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { getProvider, selectProvider } from '../providers/select_provider';
import { checkAndIncrementQuota } from '../quota/check_quota';
import { enforceRateLimit } from '../quota/rate_limit';
import {
  buildSuggestCategoryPrompt,
  type SuggestCategoryInput,
} from '../prompts/suggest_category';
import { REGION } from '../utils/region';
import { GEMINI_FAST } from '../providers/models';

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');

/**
 * Callable: AI-suggest a category for a draft transaction.
 *
 * Per CLAUDE.md §7: auth → rate-limit → quota → provider → JSON validate.
 * Feature default provider is **Gemini Flash** (cheap, fast text);
 * Remote Config `ai_provider` can override globally.
 *
 * Response shape (PRD §7.3):
 *   { suggestedCategoryId: string, confidence: number, reasoning: string }
 */
export const suggestCategory = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    secrets: [OPENAI_API_KEY, GEMINI_API_KEY],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }
    const uid = request.auth.uid;

    enforceRateLimit({
      uid,
      key: 'suggestCategory',
      windowSeconds: 60,
      maxCalls: 5,
    });
    await checkAndIncrementQuota({ uid, field: 'categorize' });

    const input = _validateInput(request.data);

    const providerName = await selectProvider({ featureDefault: 'gemini' });
    const model =
      providerName === 'openai' ? 'gpt-4o-mini' : GEMINI_FAST;
    const provider = getProvider(providerName, model);

    const { system, user } = buildSuggestCategoryPrompt(input);

    let raw: unknown;
    try {
      raw = await provider.generateJson({ system, user });
    } catch (e) {
      console.error('suggestCategory: provider error', e);
      throw new HttpsError('internal', 'AI provider error');
    }

    if (typeof raw !== 'object' || raw === null) {
      throw new HttpsError('internal', 'Malformed AI response');
    }
    const r = raw as Record<string, unknown>;
    const suggestedCategoryId = r.suggestedCategoryId;
    const confidence = r.confidence;
    const reasoning = r.reasoning;
    if (
      typeof suggestedCategoryId !== 'string' ||
      typeof confidence !== 'number' ||
      typeof reasoning !== 'string'
    ) {
      throw new HttpsError(
        'internal',
        'AI response missing required fields',
      );
    }
    return { suggestedCategoryId, confidence, reasoning };
  },
);

function _validateInput(data: unknown): SuggestCategoryInput {
  if (typeof data !== 'object' || data === null) {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const type = d.type;
  if (type !== 'expense' && type !== 'income') {
    throw new HttpsError('invalid-argument', 'type must be expense or income');
  }
  if (typeof d.amount !== 'number') {
    throw new HttpsError('invalid-argument', 'amount must be a number');
  }
  if (typeof d.currency !== 'string') {
    throw new HttpsError('invalid-argument', 'currency must be a string');
  }
  return {
    type,
    amount: d.amount,
    currency: d.currency,
    note: typeof d.note === 'string' ? d.note : undefined,
    merchant: typeof d.merchant === 'string' ? d.merchant : undefined,
    expenseCategories: _categoryArray(d.expenseCategories),
    incomeCategories: _categoryArray(d.incomeCategories),
    recentTransactions: _recentArray(d.recentTransactions),
  };
}

function _categoryArray(v: unknown): Array<{ id: string; name: string }> {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x): x is Record<string, unknown> => typeof x === 'object' && x !== null)
    .map((x) => ({
      id: String(x.id ?? ''),
      name: String(x.name ?? ''),
    }))
    .filter((x) => x.id !== '');
}

function _recentArray(
  v: unknown,
): Array<{ note?: string; categoryId: string }> {
  if (!Array.isArray(v)) return [];
  return v
    .filter((x): x is Record<string, unknown> => typeof x === 'object' && x !== null)
    .map((x) => ({
      note: typeof x.note === 'string' ? x.note : undefined,
      categoryId: String(x.categoryId ?? ''),
    }))
    .filter((x) => x.categoryId !== '');
}
