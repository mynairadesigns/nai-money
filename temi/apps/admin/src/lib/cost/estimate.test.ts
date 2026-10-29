import { describe, expect, it } from 'vitest';

import {
  blendedCostPerCall,
  costPerCall,
  estimateCost,
  FEATURE_PROFILES,
  MODEL_PRICES,
  modelForFeature,
} from './estimate';

/** Pulls one line out of the stable-ordered estimate. */
function line(
  result: ReturnType<typeof estimateCost>,
  feature: string,
): NonNullable<ReturnType<typeof estimateCost>['perFeature'][number]> {
  const found = result.perFeature.find((l) => l.feature === feature);
  if (!found) throw new Error(`no line for ${feature}`);
  return found;
}

describe('modelForFeature', () => {
  it('uses the per-feature default when ai_provider is unset', () => {
    // The shipped default: vision on OpenAI, everything else on Gemini.
    expect(modelForFeature('scan', null)).toBe('gpt-4o');
    expect(modelForFeature('chat', null)).toBe('gemini-2.5-flash-lite');
  });

  it('follows a global override in both directions', () => {
    expect(modelForFeature('chat', 'openai')).toBe('gpt-4o-mini');
    expect(modelForFeature('scan', 'gemini')).toBe('gemini-2.5-flash');
  });

  it('names a model the price table knows, for every feature and provider', () => {
    for (const feature of Object.keys(FEATURE_PROFILES) as Array<
      keyof typeof FEATURE_PROFILES
    >) {
      for (const setting of [null, 'openai', 'gemini'] as const) {
        expect(MODEL_PRICES[modelForFeature(feature, setting)]).toBeDefined();
      }
    }
  });
});

describe('costPerCall', () => {
  it('computes input and output tokens at the model rate', () => {
    // categorize on gemini-2.5-flash-lite: 500 in @ $0.10/M, 60 out @ $0.40/M.
    const expected = (500 * 0.1 + 60 * 0.4) / 1_000_000;
    expect(costPerCall('categorize', 'gemini')).toBeCloseTo(expected, 12);
  });

  it('is materially more expensive on the OpenAI override', () => {
    const gemini = costPerCall('categorize', 'gemini')!;
    const openai = costPerCall('categorize', 'openai')!;
    expect(openai).toBeGreaterThan(gemini);
  });

  it('prices the vision model for receipt scans', () => {
    // 1500 in @ $2.50/M + 250 out @ $10/M = $0.00625.
    expect(costPerCall('scan', null)).toBeCloseTo(0.00625, 12);
  });
});

describe('estimateCost', () => {
  it('multiplies counts by the per-call cost', () => {
    const result = estimateCost({ categorize: 10 }, 'gemini');
    expect(line(result, 'categorize').usd).toBeCloseTo(
      10 * costPerCall('categorize', 'gemini')!,
      12,
    );
    expect(result.totalUsd).toBeCloseTo(line(result, 'categorize').usd, 12);
  });

  it('switches every feature when the provider is overridden', () => {
    const counts = { categorize: 100, chat: 100 };
    const gemini = estimateCost(counts, 'gemini').totalUsd;
    const openai = estimateCost(counts, 'openai').totalUsd;
    expect(openai).toBeGreaterThan(gemini);
    expect(line(estimateCost(counts, 'openai'), 'chat').model).toBe(
      'gpt-4o-mini',
    );
  });

  it('costs premiumCalls at the cross-feature mean', () => {
    const result = estimateCost({ premiumCalls: 7 }, 'gemini');
    const premium = line(result, 'premiumCalls');
    expect(premium.kind).toBe('blended');
    expect(premium.model).toBeNull();
    expect(premium.usd).toBeCloseTo(7 * blendedCostPerCall('gemini'), 12);
  });

  it('contributes nothing for fx or rejected', () => {
    // fx hits exchangerate-api.com, not a model; rejected calls never reached
    // a provider at all. Both must show up as explicit zeroes.
    const result = estimateCost({ fx: 900, rejected: 40 }, null);
    expect(line(result, 'fx').usd).toBe(0);
    expect(line(result, 'fx').calls).toBe(900);
    expect(line(result, 'rejected').usd).toBe(0);
    expect(line(result, 'rejected').kind).toBe('non-llm');
    expect(result.totalUsd).toBe(0);
  });

  it('surfaces an unrecognised counter at zero instead of throwing', () => {
    const result = estimateCost({ someFutureFeature: 12 }, null);
    const unknown = line(result, 'someFutureFeature');
    expect(unknown.kind).toBe('unpriced');
    expect(unknown.calls).toBe(12);
    expect(unknown.usd).toBe(0);
  });

  it('returns every known counter even when the document is empty', () => {
    const result = estimateCost({}, null);
    // Nine features + premiumCalls + fx + rejected.
    expect(result.perFeature).toHaveLength(12);
    expect(result.perFeature.every((l) => l.calls === 0)).toBe(true);
    expect(result.totalUsd).toBe(0);
  });

  it('ignores negative and non-finite counts rather than crediting them', () => {
    const result = estimateCost(
      { categorize: -5, chat: Number.NaN, scan: undefined },
      null,
    );
    expect(result.totalUsd).toBe(0);
    expect(line(result, 'categorize').calls).toBe(0);
  });

  it('keeps a stable order regardless of key order in the document', () => {
    const a = estimateCost({ chat: 1, categorize: 2 }, null);
    const b = estimateCost({ categorize: 2, chat: 1 }, null);
    expect(a.perFeature.map((l) => l.feature)).toEqual(
      b.perFeature.map((l) => l.feature),
    );
    expect(a.perFeature[0].feature).toBe('categorize');
  });
});

describe('unknown model fallback', () => {
  it('reports unpriced without throwing when a model has no price', () => {
    // Simulates a callable being pointed at a model this table predates. The
    // panel must degrade to "visible but uncosted", never take the page down.
    const original = FEATURE_PROFILES.chat.models.gemini;
    const mutable = FEATURE_PROFILES.chat.models as Record<string, string>;
    mutable.gemini = 'gemini-9-not-released';
    try {
      expect(costPerCall('chat', 'gemini')).toBeNull();
      const result = estimateCost({ chat: 50 }, 'gemini');
      expect(line(result, 'chat').kind).toBe('unpriced');
      expect(line(result, 'chat').usd).toBe(0);
      // The blend must survive one unpriced member by averaging the rest.
      expect(blendedCostPerCall('gemini')).toBeGreaterThan(0);
    } finally {
      mutable.gemini = original;
    }
  });
});
