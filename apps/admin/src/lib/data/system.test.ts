import { describe, expect, it } from 'vitest';

import {
  buildSchedulerReport,
  deriveSchedulerHealth,
  FX_CACHE_TTL_MS,
  SCHEDULE_EXPECTATIONS,
  toFxCacheRow,
  toHeartbeatRecord,
  type HeartbeatRecord,
  type ScheduleExpectation,
} from './system';

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** A fixed instant, so nothing here depends on when the suite runs. */
const NOW = Date.UTC(2026, 7, 10, 12, 0, 0);

function expectationFor(name: string): ScheduleExpectation {
  const found = SCHEDULE_EXPECTATIONS.find((e) => e.functionName === name);
  if (!found) throw new Error(`no expectation for ${name}`);
  return found;
}

const DAILY = expectationFor('processRecurringRules');
const STATS = expectationFor('aggregatePlatformStats');
const MONTHLY = expectationFor('resetMonthlyAIQuotas');

function heartbeat(overrides: Partial<HeartbeatRecord> = {}): HeartbeatRecord {
  return {
    functionName: 'processRecurringRules',
    lastRunAtMs: NOW - HOUR_MS,
    status: 'ok',
    durationMs: 1200,
    processed: 4,
    error: null,
    ...overrides,
  };
}

describe('SCHEDULE_EXPECTATIONS', () => {
  it('covers the three deployed schedulers', () => {
    expect(SCHEDULE_EXPECTATIONS.map((e) => e.functionName)).toEqual([
      'processRecurringRules',
      'aggregatePlatformStats',
      'resetMonthlyAIQuotas',
    ]);
  });

  it('pins the crons the functions actually declare', () => {
    expect(DAILY.cron).toBe('0 0 * * *');
    expect(STATS.cron).toBe('30 0 * * *');
    expect(MONTHLY.cron).toBe('0 0 1 * *');
  });

  it('leaves slack beyond the cadence itself', () => {
    // A window equal to the cadence would flag every run that lands a minute
    // late — the false alarm is worse than the late warning.
    expect(DAILY.overdueAfterMs).toBe(26 * HOUR_MS);
    expect(STATS.overdueAfterMs).toBe(26 * HOUR_MS);
    expect(MONTHLY.overdueAfterMs).toBe(33 * DAY_MS);
    expect(MONTHLY.overdueAfterMs).toBeGreaterThan(31 * DAY_MS);
  });
});

describe('toHeartbeatRecord', () => {
  it('reads a well-formed successful run', () => {
    expect(
      toHeartbeatRecord('processRecurringRules', {
        lastRunAt: NOW,
        status: 'ok',
        durationMs: 812,
        processed: 17,
      }),
    ).toEqual({
      functionName: 'processRecurringRules',
      lastRunAtMs: NOW,
      status: 'ok',
      durationMs: 812,
      processed: 17,
      error: null,
    });
  });

  it('reads a Firestore Timestamp', () => {
    const record = toHeartbeatRecord('x', {
      lastRunAt: { toMillis: () => NOW },
      status: 'error',
      error: 'boom',
    });
    expect(record.lastRunAtMs).toBe(NOW);
    expect(record.status).toBe('error');
    expect(record.error).toBe('boom');
  });

  it('degrades every unusable field to null rather than NaN', () => {
    // This document is written from a `finally` block while an exception may be
    // in flight, so a half-written doc is a real possibility.
    const record = toHeartbeatRecord('x', {
      lastRunAt: 'yesterday',
      status: 'weird',
      durationMs: Number.NaN,
      processed: '4',
      error: '',
    });
    expect(record).toEqual({
      functionName: 'x',
      lastRunAtMs: null,
      status: null,
      durationMs: null,
      processed: null,
      error: null,
    });
  });

  it('survives a missing document body', () => {
    expect(toHeartbeatRecord('x', undefined).lastRunAtMs).toBeNull();
    expect(toHeartbeatRecord('x', null).status).toBeNull();
  });
});

describe('deriveSchedulerHealth', () => {
  it('reports `never` when no heartbeat document exists', () => {
    // Expected — not a fault — on a project that has not deployed the
    // scheduler yet: the doc only appears after the first run.
    const health = deriveSchedulerHealth(DAILY, null, NOW);
    expect(health.state).toBe('never');
    expect(health.overdue).toBe(false);
    expect(health.ageMs).toBeNull();
  });

  it('reports `ok` for a recent successful run', () => {
    const health = deriveSchedulerHealth(DAILY, heartbeat(), NOW);
    expect(health.state).toBe('ok');
    expect(health.overdue).toBe(false);
    expect(health.ageMs).toBe(HOUR_MS);
  });

  it('reports `error` when the last run failed', () => {
    const health = deriveSchedulerHealth(
      DAILY,
      heartbeat({ status: 'error', error: 'template parse failed' }),
      NOW,
    );
    expect(health.state).toBe('error');
    expect(health.overdue).toBe(false);
  });

  it('keeps the overdue flag set on a stale errored run', () => {
    // Both are true and both matter: `error` carries the reason, `overdue`
    // says it has not been retried since.
    const health = deriveSchedulerHealth(
      DAILY,
      heartbeat({ status: 'error', lastRunAtMs: NOW - 40 * HOUR_MS }),
      NOW,
    );
    expect(health.state).toBe('error');
    expect(health.overdue).toBe(true);
  });

  it('treats an unusable lastRunAt as overdue, never as ok', () => {
    const health = deriveSchedulerHealth(
      DAILY,
      heartbeat({ lastRunAtMs: null }),
      NOW,
    );
    expect(health.state).toBe('overdue');
    expect(health.overdue).toBe(true);
    expect(health.ageMs).toBeNull();
  });

  it('is not fooled by a lastRunAt in the future', () => {
    // Clock skew between the Functions runtime and this server, not a fault.
    const health = deriveSchedulerHealth(
      DAILY,
      heartbeat({ lastRunAtMs: NOW + HOUR_MS }),
      NOW,
    );
    expect(health.state).toBe('ok');
    expect(health.ageMs).toBe(-HOUR_MS);
  });

  describe('window boundaries', () => {
    it('daily: exactly 26h old is still inside the window', () => {
      const health = deriveSchedulerHealth(
        DAILY,
        heartbeat({ lastRunAtMs: NOW - 26 * HOUR_MS }),
        NOW,
      );
      expect(health.state).toBe('ok');
      expect(health.overdue).toBe(false);
    });

    it('daily: one millisecond past 26h is overdue', () => {
      const health = deriveSchedulerHealth(
        DAILY,
        heartbeat({ lastRunAtMs: NOW - 26 * HOUR_MS - 1 }),
        NOW,
      );
      expect(health.state).toBe('overdue');
      expect(health.overdue).toBe(true);
    });

    it('daily stats: a run 25h ago is fine, 27h ago is not', () => {
      expect(
        deriveSchedulerHealth(
          STATS,
          heartbeat({ lastRunAtMs: NOW - 25 * HOUR_MS }),
          NOW,
        ).state,
      ).toBe('ok');
      expect(
        deriveSchedulerHealth(
          STATS,
          heartbeat({ lastRunAtMs: NOW - 27 * HOUR_MS }),
          NOW,
        ).state,
      ).toBe('overdue');
    });

    it('monthly: exactly 33 days old is still inside the window', () => {
      const health = deriveSchedulerHealth(
        MONTHLY,
        heartbeat({ lastRunAtMs: NOW - 33 * DAY_MS }),
        NOW,
      );
      expect(health.state).toBe('ok');
      expect(health.overdue).toBe(false);
    });

    it('monthly: one millisecond past 33 days is overdue', () => {
      const health = deriveSchedulerHealth(
        MONTHLY,
        heartbeat({ lastRunAtMs: NOW - 33 * DAY_MS - 1 }),
        NOW,
      );
      expect(health.state).toBe('overdue');
    });

    it('monthly: a 31-day-old run is NOT overdue', () => {
      // The gap between two runs of `0 0 1 * *` is a full calendar month, so
      // the window has to clear the longest one.
      expect(
        deriveSchedulerHealth(
          MONTHLY,
          heartbeat({ lastRunAtMs: NOW - 31 * DAY_MS }),
          NOW,
        ).state,
      ).toBe('ok');
    });
  });
});

describe('buildSchedulerReport', () => {
  it('returns one row per expectation, in table order, even with no data', () => {
    const report = buildSchedulerReport([], NOW);
    expect(report.schedulers.map((s) => s.expectation.functionName)).toEqual([
      'processRecurringRules',
      'aggregatePlatformStats',
      'resetMonthlyAIQuotas',
    ]);
    expect(report.schedulers.every((s) => s.state === 'never')).toBe(true);
    expect(report.extras).toEqual([]);
  });

  it('matches heartbeats to expectations by function name', () => {
    const report = buildSchedulerReport(
      [
        heartbeat({ functionName: 'resetMonthlyAIQuotas', status: 'error' }),
        heartbeat({ functionName: 'processRecurringRules' }),
      ],
      NOW,
    );
    expect(report.schedulers[0].state).toBe('ok');
    expect(report.schedulers[1].state).toBe('never');
    expect(report.schedulers[2].state).toBe('error');
  });

  it('surfaces a heartbeat from a scheduler this build does not know about', () => {
    // Hiding it would recreate exactly the blind spot heartbeats exist to close.
    const report = buildSchedulerReport(
      [
        heartbeat({ functionName: 'sendWeeklyRecapPush' }),
        heartbeat({ functionName: 'anotherJob' }),
      ],
      NOW,
    );
    expect(report.extras.map((e) => e.functionName)).toEqual([
      'anotherJob',
      'sendWeeklyRecapPush',
    ]);
  });
});

describe('toFxCacheRow', () => {
  it('reads a fresh cache entry', () => {
    const row = toFxCacheRow(
      'USD-EUR',
      { rate: 0.92, from: 'USD', to: 'EUR', fetchedAt: NOW - HOUR_MS },
      NOW,
    );
    expect(row).toEqual({
      pair: 'USD-EUR',
      from: 'USD',
      to: 'EUR',
      rate: 0.92,
      fetchedAtMs: NOW - HOUR_MS,
      ageMs: HOUR_MS,
      stale: false,
    });
  });

  it('is fresh right up to the 12h TTL and stale at it', () => {
    // getFxRate serves the cache while `now - fetchedAt < TTL`, so the instant
    // the TTL is reached the next request re-fetches.
    expect(
      toFxCacheRow('USD-EUR', { fetchedAt: NOW - FX_CACHE_TTL_MS + 1 }, NOW)
        .stale,
    ).toBe(false);
    expect(
      toFxCacheRow('USD-EUR', { fetchedAt: NOW - FX_CACHE_TTL_MS }, NOW).stale,
    ).toBe(true);
  });

  it('treats an unreadable fetchedAt as stale', () => {
    const row = toFxCacheRow('USD-EUR', { rate: 0.92 }, NOW);
    expect(row.fetchedAtMs).toBeNull();
    expect(row.ageMs).toBeNull();
    expect(row.stale).toBe(true);
  });

  it('drops a non-numeric rate rather than rendering NaN', () => {
    expect(toFxCacheRow('USD-EUR', { rate: '0.92' }, NOW).rate).toBeNull();
    expect(toFxCacheRow('USD-EUR', undefined, NOW).rate).toBeNull();
  });
});
