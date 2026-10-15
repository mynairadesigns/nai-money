import { describe, expect, it } from 'vitest';

import {
  llmCallTotal,
  percentChange,
  rankConsumers,
  summarizeUsage,
  toUsageCounts,
  type UsageCounts,
  type UsageRecord,
} from './ai-usage';

const CURRENT = '2026-08';
const PREVIOUS = '2026-07';

function record(
  uid: string,
  month: string,
  counts: Record<string, number>,
): UsageRecord {
  return { uid, month, counts: counts as UsageCounts };
}

describe('toUsageCounts', () => {
  it('keeps finite numbers', () => {
    expect(toUsageCounts({ chat: 3, scan: 0 })).toEqual({ chat: 3, scan: 0 });
  });

  it('drops anything that is not a finite number', () => {
    // These documents are written by merge from several callables and are
    // untyped at rest; one stray string would turn a sum into NaN.
    expect(
      toUsageCounts({
        chat: 3,
        scan: '4',
        forecast: null,
        recap: Number.NaN,
        note: { a: 1 },
      }),
    ).toEqual({ chat: 3 });
  });

  it('survives a missing or non-object document', () => {
    expect(toUsageCounts(undefined)).toEqual({});
    expect(toUsageCounts(null)).toEqual({});
    expect(toUsageCounts(42)).toEqual({});
  });

  it('passes through a counter this build does not know about', () => {
    expect(toUsageCounts({ someFutureFeature: 2 })).toEqual({
      someFutureFeature: 2,
    });
  });
});

describe('llmCallTotal', () => {
  it('adds premiumCalls to the nine attributable counters', () => {
    // premiumCalls is incremented INSTEAD OF the per-feature field on the
    // bypass path, so omitting it under-counts every paying deployment.
    expect(
      llmCallTotal({ chat: 2, scan: 1, premiumCalls: 7 } as UsageCounts),
    ).toBe(10);
  });

  it('excludes fx and rejected', () => {
    expect(
      llmCallTotal({ chat: 2, fx: 400, rejected: 9 } as UsageCounts),
    ).toBe(2);
  });
});

describe('summarizeUsage', () => {
  const records: UsageRecord[] = [
    record('u1', CURRENT, { chat: 4, scan: 2, fx: 30, rejected: 1 }),
    record('u2', CURRENT, { premiumCalls: 12 }),
    record('u3', CURRENT, { fx: 5 }), // FX only — not an LLM user
    record('u1', PREVIOUS, { chat: 6 }),
  ];

  const summary = summarizeUsage(records, CURRENT, PREVIOUS);

  it('splits totals by month', () => {
    expect(summary.totals.current.chat).toBe(4);
    expect(summary.totals.previous.chat).toBe(6);
    expect(summary.currentMonth).toBe(CURRENT);
    expect(summary.previousMonth).toBe(PREVIOUS);
  });

  it('separates LLM calls, the quota-counted subtotal, and fx', () => {
    expect(summary.llmCalls).toEqual({ current: 18, previous: 6 });
    expect(summary.quotaCounted).toEqual({ current: 6, previous: 6 });
    expect(summary.premiumCalls).toEqual({ current: 12, previous: 0 });
    expect(summary.fx).toEqual({ current: 35, previous: 0 });
    expect(summary.rejected).toEqual({ current: 1, previous: 0 });
  });

  it('counts a user active only when they made an LLM call', () => {
    // u3 used FX only, which never reaches a model.
    expect(summary.activeUsers).toEqual({ current: 2, previous: 1 });
  });

  it('ignores months outside the two-month window', () => {
    // resetMonthlyAIQuotas only runs on the 1st, so a third month's documents
    // can legitimately linger for a few hours.
    const withStale = summarizeUsage(
      [...records, record('u1', '2026-06', { chat: 999 })],
      CURRENT,
      PREVIOUS,
    );
    expect(withStale.llmCalls).toEqual(summary.llmCalls);
  });

  it('reports no usage for an empty deployment', () => {
    const empty = summarizeUsage([], CURRENT, PREVIOUS);
    expect(empty.hasAnyUsage).toBe(false);
    expect(empty.llmCalls).toEqual({ current: 0, previous: 0 });
  });

  it('reports usage when only fx or only rejections exist', () => {
    // Neither is an LLM call, but the page must not claim the module is unused.
    expect(
      summarizeUsage([record('u1', CURRENT, { fx: 1 })], CURRENT, PREVIOUS)
        .hasAnyUsage,
    ).toBe(true);
    expect(
      summarizeUsage([record('u1', CURRENT, { rejected: 1 })], CURRENT, PREVIOUS)
        .hasAnyUsage,
    ).toBe(true);
  });

  it('carries unknown counters through to the totals and out of the empty state', () => {
    const summary = summarizeUsage(
      [record('u1', CURRENT, { someFutureFeature: 3 })],
      CURRENT,
      PREVIOUS,
    );
    expect(summary.totals.current.someFutureFeature).toBe(3);
    expect(summary.hasAnyUsage).toBe(true);
  });
});

describe('rankConsumers', () => {
  const records: UsageRecord[] = [
    record('u-low', CURRENT, { chat: 1 }),
    record('u-high', CURRENT, { chat: 9, scan: 3 }),
    record('u-premium', CURRENT, { premiumCalls: 20 }),
    record('u-fx', CURRENT, { fx: 800 }),
    record('u-old', PREVIOUS, { chat: 500 }),
  ];

  it('sorts by LLM calls, highest first, for the requested month only', () => {
    expect(rankConsumers(records, CURRENT, 10).map((r) => r.uid)).toEqual([
      'u-premium',
      'u-high',
      'u-low',
    ]);
  });

  it('omits users whose only usage is fx', () => {
    expect(rankConsumers(records, CURRENT, 10).some((r) => r.uid === 'u-fx')).toBe(
      false,
    );
  });

  it('separates the quota-counted subtotal from premium calls', () => {
    const premium = rankConsumers(records, CURRENT, 10)[0];
    expect(premium.quotaCounted).toBe(0);
    expect(premium.premiumCalls).toBe(20);
    expect(premium.llmCalls).toBe(20);
  });

  it('applies the limit', () => {
    expect(rankConsumers(records, CURRENT, 2)).toHaveLength(2);
    expect(rankConsumers(records, CURRENT, 0)).toHaveLength(0);
  });

  it('breaks ties deterministically so rows do not shuffle between requests', () => {
    const tied = [
      record('b', CURRENT, { chat: 5 }),
      record('a', CURRENT, { chat: 5 }),
    ];
    expect(rankConsumers(tied, CURRENT, 10).map((r) => r.uid)).toEqual(['a', 'b']);
  });
});

describe('percentChange', () => {
  it('reports growth and decline as a fraction', () => {
    expect(percentChange(125, 100)).toBeCloseTo(0.25, 12);
    expect(percentChange(50, 100)).toBeCloseTo(-0.5, 12);
  });

  it('is null from a zero base rather than claiming +100%', () => {
    expect(percentChange(10, 0)).toBeNull();
    expect(percentChange(0, 0)).toBeNull();
  });
});
