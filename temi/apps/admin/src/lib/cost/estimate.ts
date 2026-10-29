import { QUOTA_COUNTED_FIELDS } from '@/lib/types/user-document';

/**
 * Estimated AI spend, derived from call counts.
 *
 * READ THIS BEFORE TRUSTING A NUMBER FROM HERE. The `aiUsage` counters record
 * CALLS, not tokens — no token count is persisted anywhere in the product, and
 * neither provider's usage is reconciled back into Firestore. So every figure
 * below is the product of two documented assumptions: a per-model price table
 * and a per-feature guess at prompt/response size. It answers "is spend roughly
 * where I expect it, and which feature dominates" — it is not a bill, and it
 * will not reconcile with the OpenAI or Google Cloud invoice.
 *
 * Pure on purpose: no firebase, and deliberately NO `server-only` import, so
 * the arithmetic is unit-testable and could render client-side later.
 */

export type ProviderName = 'openai' | 'gemini';

/**
 * The resolved value of Remote Config `ai_provider`.
 *
 * `null` means the key is unset — which is the shipped default, and does NOT
 * mean "no provider". Each callable then keeps its own `featureDefault`
 * (apps/functions/src/providers/select_provider.ts), so a deployment with the
 * key unset runs gpt-4o for receipt scanning and Gemini for everything else.
 */
export type ProviderSetting = ProviderName | null;

/** The nine counters that carry a per-feature attribution. */
export type AiFeature = (typeof QUOTA_COUNTED_FIELDS)[number];

/* ------------------------------------------------------------- prices --- */

export interface ModelPrice {
  /** USD per 1M input tokens. */
  inputPerMillion: number;
  /** USD per 1M output tokens. */
  outputPerMillion: number;
}

/**
 * Published list prices, USD per 1M tokens.
 *
 * Transcribed from each provider's public pricing page and NOT fetched at
 * runtime — a pricing API call on every page load would be a needless external
 * dependency for a number that changes a few times a year. The cost is that
 * these go stale silently, so re-check them when a provider announces a change,
 * and note that discounts (batch, cached-input, committed-use) are ignored:
 * this table is the list-price ceiling.
 *
 * Only the four models the callables can actually select are listed. Adding a
 * model to a callable without adding it here degrades to "unpriced" rather than
 * throwing — see `estimateCost`.
 */
export const MODEL_PRICES: Readonly<Record<string, ModelPrice>> = {
  'gpt-4o': { inputPerMillion: 2.5, outputPerMillion: 10 },
  'gpt-4o-mini': { inputPerMillion: 0.15, outputPerMillion: 0.6 },
  'gemini-2.5-flash': { inputPerMillion: 0.3, outputPerMillion: 2.5 },
  'gemini-2.5-flash-lite': { inputPerMillion: 0.1, outputPerMillion: 0.4 },
};

/* ----------------------------------------------------------- profiles --- */

export interface FeatureProfile {
  label: string;
  /** Assumed prompt size for one call, in tokens. */
  inputTokens: number;
  /** Assumed completion size for one call, in tokens. */
  outputTokens: number;
  /** Provider used when `ai_provider` is unset — mirrors `featureDefault`. */
  defaultProvider: ProviderName;
  /** Model per provider, mirroring the ternary in each callable. */
  models: Readonly<Record<ProviderName, string>>;
  /** Where the token assumption comes from, surfaced in the UI. */
  basis: string;
}

/**
 * Per-feature model + token assumptions.
 *
 * `models` and `defaultProvider` MIRROR the callables in
 * apps/functions/src/ai/ — every one of them resolves its model with the same
 * two lines (`selectProvider({ featureDefault })` then a provider ternary).
 * scanReceipt is the only outlier: vision defaults to OpenAI. If a callable's
 * model changes, change it here in the same commit or the estimate silently
 * prices the wrong model.
 *
 * The token counts are estimates from the prompt templates in
 * apps/functions/src/prompts/ (~350–900 tokens of rendered instructions each)
 * plus the context each callable assembles. They are rounded generously — an
 * estimate that runs slightly high is more useful than one that lulls.
 */
export const FEATURE_PROFILES: Readonly<Record<AiFeature, FeatureProfile>> = {
  categorize: {
    label: 'Smart categorization',
    inputTokens: 500,
    outputTokens: 60,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'Short prompt + merchant string + the user’s category list; a one-line JSON answer.',
  },
  scan: {
    label: 'Receipt scan',
    inputTokens: 1500,
    outputTokens: 250,
    defaultProvider: 'openai',
    models: { openai: 'gpt-4o', gemini: 'gemini-2.5-flash' },
    basis: 'Prompt plus one receipt image (~750–1100 input tokens at high detail); itemised JSON out.',
  },
  chat: {
    label: 'Coach chat',
    inputTokens: 2500,
    outputTokens: 350,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'The largest prompt: financial context plus up to 20 prior messages replayed each turn.',
  },
  forecast: {
    label: 'Spending forecast',
    inputTokens: 1200,
    outputTokens: 300,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'Prompt + up to 10 per-category aggregates.',
  },
  anomalies: {
    label: 'Anomaly detection',
    inputTokens: 1200,
    outputTokens: 300,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'Prompt + up to 10 candidate transactions pre-filtered on the server.',
  },
  healthScore: {
    label: 'Health score',
    inputTokens: 1000,
    outputTokens: 300,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'Prompt + a compact aggregate summary; scored JSON with per-factor notes.',
  },
  recap: {
    label: 'Weekly recap',
    inputTokens: 1200,
    outputTokens: 400,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'A week of aggregates in, a short narrative out.',
  },
  budgetPlan: {
    label: 'Budget generator',
    inputTokens: 1200,
    outputTokens: 600,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'Spending history in; a full per-category plan out, so output-heavy.',
  },
  savingsPlan: {
    label: 'Savings coach',
    inputTokens: 1200,
    outputTokens: 600,
    defaultProvider: 'gemini',
    models: { openai: 'gpt-4o-mini', gemini: 'gemini-2.5-flash-lite' },
    basis: 'Goal + cashflow context in; a multi-step plan out.',
  },
};

/**
 * Counters that exist on the document but cost nothing to run an LLM for.
 *
 * `fx` calls exchangerate-api.com, not a model. `rejected` counts calls that
 * were REFUSED at the ceiling, so by definition no provider was reached. Both
 * are listed rather than ignored so the UI can show them as deliberate zeroes
 * instead of leaving an operator wondering whether they were forgotten.
 */
export const NON_LLM_COUNTERS: Readonly<Record<string, string>> = {
  fx: 'FX rate lookups',
  rejected: 'Quota rejections',
};

/** Human label for `premiumCalls`, which has no per-feature breakdown. */
export const PREMIUM_CALLS_LABEL = 'Premium calls (unattributed)';

/* ------------------------------------------------------------- costing -- */

/** The model a feature runs on under [setting]. */
export function modelForFeature(
  feature: AiFeature,
  setting: ProviderSetting,
): string {
  const profile = FEATURE_PROFILES[feature];
  return profile.models[setting ?? profile.defaultProvider];
}

/**
 * USD for a single call of [feature]. Returns null when the model carries no
 * entry in the price table — the caller decides how to present "unpriced",
 * which is always better than a confident 0 or a thrown error inside a page.
 */
export function costPerCall(
  feature: AiFeature,
  setting: ProviderSetting,
): number | null {
  const profile = FEATURE_PROFILES[feature];
  const price = MODEL_PRICES[modelForFeature(feature, setting)];
  if (!price) return null;

  return (
    (profile.inputTokens * price.inputPerMillion +
      profile.outputTokens * price.outputPerMillion) /
    1_000_000
  );
}

/**
 * Mean cost of one call across the nine attributable features.
 *
 * Needed because `premiumCalls` is a single undifferentiated counter: on the
 * premium path `checkAndIncrementQuota` increments ONLY `premiumCalls` and
 * leaves the per-feature field untouched, so a premium user's calls carry no
 * feature attribution at all. A flat mean is the least-wrong assumption
 * available; it will be well off for a deployment whose premium users lean
 * heavily on receipt scanning, which is roughly 20x the cost of the others.
 */
export function blendedCostPerCall(setting: ProviderSetting): number {
  const priced = QUOTA_COUNTED_FIELDS.map((f) => costPerCall(f, setting)).filter(
    (c): c is number => c != null,
  );
  if (priced.length === 0) return 0;

  return priced.reduce((sum, c) => sum + c, 0) / priced.length;
}

export interface FeatureEstimate {
  /** The raw counter field name. */
  feature: string;
  label: string;
  calls: number;
  /** Null where no single model applies (blended) or none is known. */
  model: string | null;
  usd: number;
  /**
   * - `llm`     — priced from the model table.
   * - `blended` — premiumCalls, costed at the cross-feature mean.
   * - `non-llm` — known to cost nothing (fx, rejected).
   * - `unpriced` — a counter or model this build does not recognise; 0 USD.
   */
  kind: 'llm' | 'blended' | 'non-llm' | 'unpriced';
}

export interface CostEstimate {
  perFeature: FeatureEstimate[];
  totalUsd: number;
}

/**
 * Estimates spend for a map of counter field -> call count.
 *
 * Never throws. An unrecognised counter field (a future Cloud Function shipping
 * ahead of this panel) or a model missing from the price table both land as
 * `unpriced` with 0 USD, so a new backend feature degrades to "visible but
 * uncosted" rather than taking the page down.
 *
 * Output order is stable — the nine features in quota order, then premiumCalls,
 * then the non-LLM counters, then anything unrecognised — so the table does not
 * reshuffle between requests as counts change.
 */
export function estimateCost(
  counts: Readonly<Record<string, number | undefined>>,
  setting: ProviderSetting,
): CostEstimate {
  const perFeature: FeatureEstimate[] = [];
  const seen = new Set<string>();

  const take = (key: string): number => {
    seen.add(key);
    const value = counts[key];
    return typeof value === 'number' && Number.isFinite(value) && value > 0
      ? value
      : 0;
  };

  for (const feature of QUOTA_COUNTED_FIELDS) {
    const calls = take(feature);
    const unit = costPerCall(feature, setting);
    perFeature.push({
      feature,
      label: FEATURE_PROFILES[feature].label,
      calls,
      model: modelForFeature(feature, setting),
      usd: unit == null ? 0 : unit * calls,
      kind: unit == null ? 'unpriced' : 'llm',
    });
  }

  const premiumCalls = take('premiumCalls');
  perFeature.push({
    feature: 'premiumCalls',
    label: PREMIUM_CALLS_LABEL,
    calls: premiumCalls,
    model: null,
    usd: blendedCostPerCall(setting) * premiumCalls,
    kind: 'blended',
  });

  for (const [key, label] of Object.entries(NON_LLM_COUNTERS)) {
    perFeature.push({
      feature: key,
      label,
      calls: take(key),
      model: null,
      usd: 0,
      kind: 'non-llm',
    });
  }

  for (const [key, value] of Object.entries(counts)) {
    if (seen.has(key)) continue;
    perFeature.push({
      feature: key,
      label: key,
      calls: typeof value === 'number' && Number.isFinite(value) ? value : 0,
      model: null,
      usd: 0,
      kind: 'unpriced',
    });
  }

  return {
    perFeature,
    totalUsd: perFeature.reduce((sum, line) => sum + line.usd, 0),
  };
}
