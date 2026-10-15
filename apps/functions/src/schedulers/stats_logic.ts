/**
 * Pure platform-stats logic — zero firebase imports.
 *
 * Extracted from `reset_monthly_quotas.ts` (monthly AI-usage rollup) and
 * `aggregate_platform_stats.ts` (daily snapshot) so the summing, the shaping
 * and the UTC key derivation can be unit-tested without initialising
 * firebase-admin or hitting Firestore.
 *
 * Every key here is derived in **UTC**, matching the schedulers' `timeZone:
 * 'UTC'` and the `users/{uid}/aiUsage/{YYYY-MM}` doc-id convention. Using
 * local time would silently shift a doc into the wrong bucket depending on
 * where the function happens to run.
 */

/**
 * Every counter field written under `users/{uid}/aiUsage/{YYYY-MM}`
 * (CLAUDE.md §8 — "AI quota counters"). The rollup emits all of them so a
 * month's document has a stable shape even when a feature saw zero traffic;
 * the admin panel can then chart a field without null-guarding every point.
 */
export const AI_COUNTER_FIELDS = [
  'categorize',
  'scan',
  'chat',
  'forecast',
  'anomalies',
  'healthScore',
  'recap',
  'budgetPlan',
  'savingsPlan',
  'premiumCalls',
  'fx',
  'rejected',
] as const;

export type AiCounterField = (typeof AI_COUNTER_FIELDS)[number];
export type AiCallCounts = Record<AiCounterField, number>;

/**
 * Counters that do NOT represent a call that reached a provider.
 *
 * `rejected` counts requests denied at the free-tier ceiling — no provider
 * was ever called — so it is excluded from `aiCallsTotal` and from the
 * `activeUsers` test. Everything else counts, including `premiumCalls`:
 * premium users bypass the per-feature counters entirely and their calls
 * land there instead (see `quota/check_quota.ts`), so dropping it would
 * under-report exactly the heaviest users.
 */
const NON_CALL_FIELDS: ReadonlySet<string> = new Set<string>(['rejected']);

/** A single `users/{uid}/aiUsage/{YYYY-MM}` document, flattened for rollup. */
export interface AiUsageRecord {
  /** Firestore doc id — the `YYYY-MM` month this row belongs to. */
  month: string;
  /** Owning user, derived from the doc path (`ref.parent.parent.id`). */
  uid: string;
  /** Raw doc data. Absent / non-numeric / negative fields coerce to 0. */
  counters: Record<string, unknown>;
}

/** One `adminStatsMonthly/{YYYY-MM}` document body (minus `rolledUpAt`). */
export interface MonthlyRollup {
  /** Distinct users with an `aiUsage` doc that month — includes reject-only users. */
  users: number;
  /** Distinct users who made at least one call as premium (`premiumCalls > 0`). */
  usersPremium: number;
  /** Per-feature totals across every user. */
  aiCalls: AiCallCounts;
  /** Sum of `aiCalls` excluding `rejected` — calls that actually happened. */
  aiCallsTotal: number;
  /** Distinct users with at least one *successful* call (≠ `users` when rejects exist). */
  activeUsers: number;
}

/** All-zero counter map. Guarantees a stable document shape per month. */
export function emptyAiCallCounts(): AiCallCounts {
  const out = {} as AiCallCounts;
  for (const field of AI_COUNTER_FIELDS) out[field] = 0;
  return out;
}

/**
 * Coerces a raw Firestore field to a non-negative integer count.
 *
 * Firestore is schemaless and these counters are written by several code
 * paths over time, so a field can legitimately be absent, `null`, a string,
 * or (after a bad migration) a float. Anything that isn't a finite
 * non-negative number is treated as 0 rather than poisoning the whole
 * month's total with `NaN`.
 */
export function coerceCount(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return 0;
  }
  return Math.floor(value);
}

/**
 * Folds a flat list of `aiUsage` docs into one rollup per month.
 *
 * Pure and order-independent: re-running with the same input produces a
 * deep-equal result, which is what makes the caller's `set(..., { merge:
 * true })` write idempotent — a re-run overwrites a month with the same
 * numbers instead of double-counting.
 */
export function rollUpMonthly(
  records: readonly AiUsageRecord[],
): Map<string, MonthlyRollup> {
  // uid sets are kept alongside the sums so a user is counted once even if
  // the scan somehow yields two rows for the same (month, uid) pair.
  const acc = new Map<
    string,
    {
      users: Set<string>;
      premium: Set<string>;
      active: Set<string>;
      aiCalls: AiCallCounts;
      aiCallsTotal: number;
    }
  >();

  for (const record of records) {
    let bucket = acc.get(record.month);
    if (!bucket) {
      bucket = {
        users: new Set<string>(),
        premium: new Set<string>(),
        active: new Set<string>(),
        aiCalls: emptyAiCallCounts(),
        aiCallsTotal: 0,
      };
      acc.set(record.month, bucket);
    }

    bucket.users.add(record.uid);

    let successfulCalls = 0;
    for (const field of AI_COUNTER_FIELDS) {
      const count = coerceCount(record.counters[field]);
      if (count === 0) continue;
      bucket.aiCalls[field] += count;
      if (!NON_CALL_FIELDS.has(field)) successfulCalls += count;
    }

    bucket.aiCallsTotal += successfulCalls;
    if (successfulCalls > 0) bucket.active.add(record.uid);
    if (coerceCount(record.counters.premiumCalls) > 0) {
      bucket.premium.add(record.uid);
    }
  }

  const out = new Map<string, MonthlyRollup>();
  for (const [month, bucket] of acc) {
    out.set(month, {
      users: bucket.users.size,
      usersPremium: bucket.premium.size,
      aiCalls: bucket.aiCalls,
      aiCallsTotal: bucket.aiCallsTotal,
      activeUsers: bucket.active.size,
    });
  }
  return out;
}

/** One `adminStatsDaily/{YYYY-MM-DD}` document body (minus `computedAt`). */
export interface DailyStats {
  totalUsers: number;
  newUsers: number;
  premiumUsers: number;
  activeUsers24h: number;
  activeUsers7d: number;
  activeUsers30d: number;
}

/**
 * Normalises the six raw aggregation results into the stored shape.
 *
 * `count().get()` always returns a number today, but a failed/short-circuited
 * branch upstream could hand us `undefined`; writing `NaN` into Firestore
 * would break every chart downstream, so everything funnels through
 * [coerceCount].
 */
export function shapeDailyStats(
  raw: Partial<Record<keyof DailyStats, unknown>>,
): DailyStats {
  return {
    totalUsers: coerceCount(raw.totalUsers),
    newUsers: coerceCount(raw.newUsers),
    premiumUsers: coerceCount(raw.premiumUsers),
    activeUsers24h: coerceCount(raw.activeUsers24h),
    activeUsers7d: coerceCount(raw.activeUsers7d),
    activeUsers30d: coerceCount(raw.activeUsers30d),
  };
}

/** `YYYY-MM` (UTC) — the `aiUsage` / `adminStatsMonthly` doc-id format. */
export function yearMonthKey(date: Date): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

/** `YYYY-MM-DD` (UTC) — the `adminStatsDaily` doc-id format. */
export function dayKey(date: Date): string {
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${yearMonthKey(date)}-${d}`;
}

/**
 * `YYYY-MM` for the month *before* [date], in UTC.
 *
 * Used by `resetMonthlyAIQuotas` as the exclusive lower bound: `aiUsage` doc
 * ids below this string are stale. Relies on `Date.UTC` normalising a month
 * index of -1 into December of the previous year.
 */
export function previousMonthKey(date: Date): string {
  return yearMonthKey(
    new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() - 1, 1)),
  );
}

/** Midnight UTC on the same calendar day as [date]. */
export function utcDayStart(date: Date): Date {
  return new Date(
    Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()),
  );
}

/** [date] shifted back by [days] whole days (exact 24h multiples, UTC-safe). */
export function daysAgo(date: Date, days: number): Date {
  return new Date(date.getTime() - days * 24 * 60 * 60 * 1000);
}
