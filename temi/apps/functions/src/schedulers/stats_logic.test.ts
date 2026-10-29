import {
  AiUsageRecord,
  coerceCount,
  dayKey,
  daysAgo,
  emptyAiCallCounts,
  previousMonthKey,
  rollUpMonthly,
  shapeDailyStats,
  utcDayStart,
  yearMonthKey,
} from './stats_logic';

/** Convenience: an `aiUsage` row for [uid] in [month] with [counters]. */
function record(
  uid: string,
  month: string,
  counters: Record<string, unknown>,
): AiUsageRecord {
  return { uid, month, counters };
}

describe('rollUpMonthly — summing across users', () => {
  it('sums per-feature counters across every user in a month', () => {
    const rollups = rollUpMonthly([
      record('u1', '2026-05', { chat: 3, scan: 1 }),
      record('u2', '2026-05', { chat: 2, fx: 10 }),
      record('u3', '2026-05', { scan: 4 }),
    ]);

    const may = rollups.get('2026-05')!;
    expect(may.aiCalls.chat).toBe(5);
    expect(may.aiCalls.scan).toBe(5);
    expect(may.aiCalls.fx).toBe(10);
    expect(may.aiCallsTotal).toBe(20);
    expect(may.users).toBe(3);
    expect(may.activeUsers).toBe(3);
  });

  it('buckets records into separate months', () => {
    const rollups = rollUpMonthly([
      record('u1', '2026-04', { chat: 1 }),
      record('u1', '2026-05', { chat: 2 }),
      record('u2', '2026-05', { chat: 4 }),
    ]);

    expect(rollups.size).toBe(2);
    expect(rollups.get('2026-04')!.aiCallsTotal).toBe(1);
    expect(rollups.get('2026-04')!.users).toBe(1);
    expect(rollups.get('2026-05')!.aiCallsTotal).toBe(6);
    expect(rollups.get('2026-05')!.users).toBe(2);
  });

  it('emits every counter field even when a feature saw zero traffic', () => {
    const may = rollUpMonthly([record('u1', '2026-05', { chat: 1 })]).get('2026-05')!;
    expect(may.aiCalls).toEqual({ ...emptyAiCallCounts(), chat: 1 });
  });

  it('returns an empty map for no records', () => {
    expect(rollUpMonthly([]).size).toBe(0);
  });
});

describe('rollUpMonthly — user segmentation', () => {
  it('counts a user with only rejections in `users` but not `activeUsers`', () => {
    const may = rollUpMonthly([
      record('u1', '2026-05', { chat: 2 }),
      record('u2', '2026-05', { rejected: 7 }),
    ]).get('2026-05')!;

    expect(may.users).toBe(2);
    expect(may.activeUsers).toBe(1);
    expect(may.aiCalls.rejected).toBe(7);
    // `rejected` never reached a provider, so it stays out of the total.
    expect(may.aiCallsTotal).toBe(2);
  });

  it('counts users with premiumCalls > 0 as premium', () => {
    const may = rollUpMonthly([
      record('u1', '2026-05', { premiumCalls: 40 }),
      record('u2', '2026-05', { premiumCalls: 0, chat: 1 }),
      record('u3', '2026-05', { chat: 1 }),
    ]).get('2026-05')!;

    expect(may.usersPremium).toBe(1);
    expect(may.users).toBe(3);
    // premiumCalls IS a real call — premium users' traffic lands there only.
    expect(may.aiCallsTotal).toBe(42);
  });

  it('counts a uid once even if the scan yields it twice for one month', () => {
    const may = rollUpMonthly([
      record('u1', '2026-05', { chat: 1 }),
      record('u1', '2026-05', { chat: 2 }),
    ]).get('2026-05')!;

    expect(may.users).toBe(1);
    expect(may.activeUsers).toBe(1);
    expect(may.aiCalls.chat).toBe(3);
  });
});

describe('rollUpMonthly — idempotent re-run', () => {
  it('produces a deep-equal result when run twice on the same input', () => {
    const records = [
      record('u1', '2026-05', { chat: 3, rejected: 1 }),
      record('u2', '2026-05', { premiumCalls: 9 }),
      record('u3', '2026-04', { scan: 2 }),
    ];

    const first = rollUpMonthly(records);
    const second = rollUpMonthly(records);

    expect([...second.entries()]).toEqual([...first.entries()]);
  });

  it('is order-independent', () => {
    const a = rollUpMonthly([
      record('u1', '2026-05', { chat: 3 }),
      record('u2', '2026-05', { scan: 2 }),
    ]);
    const b = rollUpMonthly([
      record('u2', '2026-05', { scan: 2 }),
      record('u1', '2026-05', { chat: 3 }),
    ]);

    expect(b.get('2026-05')).toEqual(a.get('2026-05'));
  });
});

describe('rollUpMonthly — absent / non-numeric counters', () => {
  it('treats an empty doc as all zeros', () => {
    const may = rollUpMonthly([record('u1', '2026-05', {})]).get('2026-05')!;

    expect(may.aiCalls).toEqual(emptyAiCallCounts());
    expect(may.aiCallsTotal).toBe(0);
    expect(may.users).toBe(1);
    expect(may.activeUsers).toBe(0);
  });

  it('ignores strings, null, undefined, NaN and negatives without poisoning the total', () => {
    const may = rollUpMonthly([
      record('u1', '2026-05', {
        chat: '5',
        scan: null,
        forecast: undefined,
        anomalies: NaN,
        recap: -3,
        healthScore: Infinity,
        budgetPlan: 2,
      }),
    ]).get('2026-05')!;

    expect(may.aiCalls.chat).toBe(0);
    expect(may.aiCalls.scan).toBe(0);
    expect(may.aiCalls.forecast).toBe(0);
    expect(may.aiCalls.anomalies).toBe(0);
    expect(may.aiCalls.recap).toBe(0);
    expect(may.aiCalls.healthScore).toBe(0);
    expect(may.aiCalls.budgetPlan).toBe(2);
    expect(may.aiCallsTotal).toBe(2);
    expect(Number.isNaN(may.aiCallsTotal)).toBe(false);
  });

  it('ignores unknown fields written by a future feature', () => {
    const may = rollUpMonthly([
      record('u1', '2026-05', { chat: 1, someFutureCounter: 99 }),
    ]).get('2026-05')!;

    expect(may.aiCallsTotal).toBe(1);
    expect(Object.keys(may.aiCalls)).not.toContain('someFutureCounter');
  });

  it('floors fractional counts', () => {
    expect(coerceCount(2.7)).toBe(2);
    expect(coerceCount(0)).toBe(0);
    expect(coerceCount(-0.5)).toBe(0);
    expect(coerceCount('3')).toBe(0);
  });
});

describe('yearMonthKey / dayKey — UTC boundaries', () => {
  it('zero-pads single-digit months and days', () => {
    const d = new Date(Date.UTC(2026, 0, 5, 12, 0, 0));
    expect(yearMonthKey(d)).toBe('2026-01');
    expect(dayKey(d)).toBe('2026-01-05');
  });

  it('formats a double-digit month and day', () => {
    const d = new Date(Date.UTC(2026, 11, 31, 23, 59, 59));
    expect(yearMonthKey(d)).toBe('2026-12');
    expect(dayKey(d)).toBe('2026-12-31');
  });

  it('derives keys in UTC, not local time', () => {
    // 00:30 UTC on Jan 1 is still Dec 31 in any negative-offset zone; the key
    // must not follow the machine's timezone.
    const d = new Date(Date.UTC(2027, 0, 1, 0, 30, 0));
    expect(dayKey(d)).toBe('2027-01-01');
    expect(yearMonthKey(d)).toBe('2027-01');

    // …and 23:30 UTC on Dec 31 is already Jan 1 in positive-offset zones.
    const e = new Date(Date.UTC(2026, 11, 31, 23, 30, 0));
    expect(dayKey(e)).toBe('2026-12-31');
  });
});

describe('previousMonthKey — year rollover', () => {
  it('steps back one month mid-year', () => {
    expect(previousMonthKey(new Date(Date.UTC(2026, 4, 1, 0, 0, 0)))).toBe('2026-04');
  });

  it('rolls back across the year boundary (Jan → previous Dec)', () => {
    expect(previousMonthKey(new Date(Date.UTC(2026, 0, 1, 0, 0, 0)))).toBe('2025-12');
  });

  it('rolls back from the last instant of January', () => {
    expect(previousMonthKey(new Date(Date.UTC(2026, 0, 31, 23, 59, 59)))).toBe('2025-12');
  });

  it('sorts lexicographically below the current month (the cleanup invariant)', () => {
    const now = new Date(Date.UTC(2026, 0, 1));
    const cutoff = previousMonthKey(now);
    expect('2025-11' < cutoff).toBe(true); // stale → deleted
    expect('2025-12' < cutoff).toBe(false); // kept (previous month)
    expect('2026-01' < cutoff).toBe(false); // kept (current month)
  });
});

describe('utcDayStart / daysAgo', () => {
  it('utcDayStart truncates to midnight UTC', () => {
    const d = utcDayStart(new Date(Date.UTC(2026, 7, 10, 0, 30, 15, 500)));
    expect(d.toISOString()).toBe('2026-08-10T00:00:00.000Z');
  });

  it('daysAgo(dayStart, 1) yields the previous UTC midnight, across a month boundary', () => {
    const dayEnd = utcDayStart(new Date(Date.UTC(2026, 8, 1, 0, 30, 0)));
    const dayStart = daysAgo(dayEnd, 1);
    expect(dayStart.toISOString()).toBe('2026-08-31T00:00:00.000Z');
    expect(dayKey(dayStart)).toBe('2026-08-31');
  });

  it('daysAgo crosses a year boundary', () => {
    const dayEnd = utcDayStart(new Date(Date.UTC(2027, 0, 1, 0, 30, 0)));
    expect(dayKey(daysAgo(dayEnd, 1))).toBe('2026-12-31');
  });

  it('daysAgo subtracts exact 24h multiples', () => {
    const now = new Date(Date.UTC(2026, 7, 10, 12, 0, 0));
    expect(daysAgo(now, 7).toISOString()).toBe('2026-08-03T12:00:00.000Z');
    expect(daysAgo(now, 30).toISOString()).toBe('2026-07-11T12:00:00.000Z');
  });
});

describe('shapeDailyStats', () => {
  it('passes through valid counts', () => {
    expect(
      shapeDailyStats({
        totalUsers: 1200,
        newUsers: 14,
        premiumUsers: 88,
        activeUsers24h: 300,
        activeUsers7d: 700,
        activeUsers30d: 1000,
      }),
    ).toEqual({
      totalUsers: 1200,
      newUsers: 14,
      premiumUsers: 88,
      activeUsers24h: 300,
      activeUsers7d: 700,
      activeUsers30d: 1000,
    });
  });

  it('coerces missing / invalid aggregation results to 0 rather than NaN', () => {
    const stats = shapeDailyStats({ totalUsers: 5, newUsers: undefined, premiumUsers: NaN });
    expect(stats).toEqual({
      totalUsers: 5,
      newUsers: 0,
      premiumUsers: 0,
      activeUsers24h: 0,
      activeUsers7d: 0,
      activeUsers30d: 0,
    });
  });
});
