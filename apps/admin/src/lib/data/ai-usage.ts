import 'server-only';

import { cache } from 'react';

import { adminDb } from '@/lib/firebase/admin';
import type { AiUsageDocument } from '@/lib/types/user-document';
import { previousYearMonth, yearMonth } from '@/lib/format';

import { quotaCountedTotal } from './user-mapping';

/**
 * Reads over `users/{uid}/aiUsage/{YYYY-MM}`.
 *
 * QUERY SHAPE: one unfiltered collection-group `get()`, grouped in code. A
 * collection-group query with no `where`/`orderBy` needs no composite index, so
 * a fresh buyer project works without deploying anything — the repo-wide
 * index-frugality rule in CLAUDE.md §7.
 *
 * COST: this reads every aiUsage document, so it scales linearly with user
 * count — bounded only by `resetMonthlyAIQuotas` keeping just the current and
 * previous month. That is acceptable for an ops console at Homa Finance's scale
 * and is exactly what the Phase 3 `adminStatsMonthly` rollup is for: once that
 * scheduler exists, these reads become a two-document lookup and the module's
 * pure summarisers can be pointed at the rollup unchanged.
 */

/**
 * One month's counters for one user.
 *
 * Typed as the known document shape PLUS an open index, because a Cloud
 * Function shipping a new counter must not make this file fail to compile — the
 * panel shows unrecognised counters rather than dropping them.
 */
export type UsageCounts = AiUsageDocument &
  Readonly<Record<string, number | undefined>>;

export interface UsageRecord {
  uid: string;
  /** The document id: a `YYYY-MM` key in UTC. */
  month: string;
  counts: UsageCounts;
}

/* ------------------------------------------------------ pure summarisers -- */

/**
 * Copies only finite numbers out of a raw document.
 *
 * Firestore documents are untyped at rest, and these are written by merge from
 * several callables. A stray string would otherwise turn a sum into `"31"` or
 * `NaN` and quietly corrupt every figure downstream.
 */
export function toUsageCounts(data: unknown): UsageCounts {
  const out: Record<string, number> = {};
  if (data && typeof data === 'object') {
    for (const [key, value] of Object.entries(data)) {
      if (typeof value === 'number' && Number.isFinite(value)) out[key] = value;
    }
  }
  return out as UsageCounts;
}

export interface CounterPair {
  current: number;
  previous: number;
}

export interface UsageSummary {
  currentMonth: string;
  previousMonth: string;
  /** Per-counter totals across all users, ready to hand to `estimateCost`. */
  totals: { current: UsageCounts; previous: UsageCounts };
  /** Calls that actually reached a model: the nine features plus premiumCalls. */
  llmCalls: CounterPair;
  /** The nine ceiling-governed counters only. */
  quotaCounted: CounterPair;
  premiumCalls: CounterPair;
  fx: CounterPair;
  rejected: CounterPair;
  /** Users with at least one LLM call in the month. */
  activeUsers: CounterPair;
  /** Whether any counter anywhere is non-zero — drives the empty state. */
  hasAnyUsage: boolean;
}

function sumInto(target: Record<string, number>, counts: UsageCounts): void {
  for (const [key, value] of Object.entries(counts)) {
    if (typeof value === 'number' && Number.isFinite(value)) {
      target[key] = (target[key] ?? 0) + value;
    }
  }
}

function numberAt(counts: UsageCounts, key: string): number {
  const value = counts[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/**
 * Total calls that reached a provider.
 *
 * `premiumCalls` is added to the nine because those ARE real model calls:
 * `checkAndIncrementQuota` increments `premiumCalls` INSTEAD OF the per-feature
 * field on the premium-bypass path, so leaving it out would under-count every
 * paying deployment. `fx` is excluded — it calls exchangerate-api.com, not a
 * model — and so is `rejected`, which by definition never reached one.
 */
export function llmCallTotal(counts: UsageCounts): number {
  return quotaCountedTotal(counts) + numberAt(counts, 'premiumCalls');
}

/**
 * Folds raw records into the two-month summary the page renders.
 *
 * Records outside the two target months are ignored rather than merged in:
 * `resetMonthlyAIQuotas` only runs on the 1st, so a third month's documents can
 * legitimately still exist for a few hours and must not inflate either column.
 */
export function summarizeUsage(
  records: readonly UsageRecord[],
  currentMonth: string,
  previousMonth: string,
): UsageSummary {
  const current: Record<string, number> = {};
  const previous: Record<string, number> = {};
  const activeCurrent = new Set<string>();
  const activePrevious = new Set<string>();

  for (const record of records) {
    const isCurrent = record.month === currentMonth;
    const isPrevious = record.month === previousMonth;
    if (!isCurrent && !isPrevious) continue;

    sumInto(isCurrent ? current : previous, record.counts);

    if (llmCallTotal(record.counts) > 0) {
      (isCurrent ? activeCurrent : activePrevious).add(record.uid);
    }
  }

  const currentCounts = current as UsageCounts;
  const previousCounts = previous as UsageCounts;

  const pair = (key: string): CounterPair => ({
    current: numberAt(currentCounts, key),
    previous: numberAt(previousCounts, key),
  });

  const llmCalls: CounterPair = {
    current: llmCallTotal(currentCounts),
    previous: llmCallTotal(previousCounts),
  };
  const fx = pair('fx');
  const rejected = pair('rejected');

  return {
    currentMonth,
    previousMonth,
    totals: { current: currentCounts, previous: previousCounts },
    llmCalls,
    quotaCounted: {
      current: quotaCountedTotal(currentCounts),
      previous: quotaCountedTotal(previousCounts),
    },
    premiumCalls: pair('premiumCalls'),
    fx,
    rejected,
    activeUsers: { current: activeCurrent.size, previous: activePrevious.size },
    // Any non-zero counter at all, including ones this build does not know
    // about — an empty state that hides a counter it failed to recognise would
    // be the worst possible lie for this page to tell.
    hasAnyUsage: hasNonZero(currentCounts) || hasNonZero(previousCounts),
  };
}

function hasNonZero(counts: UsageCounts): boolean {
  return Object.values(counts).some(
    (value) => typeof value === 'number' && value !== 0,
  );
}

export interface ConsumerRow {
  uid: string;
  counts: UsageCounts;
  /** Calls that reached a model — the ranking key. */
  llmCalls: number;
  /** The subtotal the free-tier ceiling actually governs. */
  quotaCounted: number;
  premiumCalls: number;
}

/**
 * Top consumers for one month, highest first.
 *
 * Ties break on uid so the ordering is deterministic — otherwise two users on
 * the same count could swap places between requests and look like activity.
 */
export function rankConsumers(
  records: readonly UsageRecord[],
  month: string,
  limit: number,
): ConsumerRow[] {
  const rows: ConsumerRow[] = [];

  for (const record of records) {
    if (record.month !== month) continue;

    const llmCalls = llmCallTotal(record.counts);
    if (llmCalls === 0) continue;

    rows.push({
      uid: record.uid,
      counts: record.counts,
      llmCalls,
      quotaCounted: quotaCountedTotal(record.counts),
      premiumCalls: numberAt(record.counts, 'premiumCalls'),
    });
  }

  rows.sort((a, b) => b.llmCalls - a.llmCalls || a.uid.localeCompare(b.uid));
  return rows.slice(0, Math.max(limit, 0));
}

/**
 * Month-over-month change as a fraction (0.25 = +25%).
 *
 * Null when the previous month was zero: "infinite growth" is not a useful
 * thing to render, and "+100%" would be a lie. The UI shows "new" instead.
 */
export function percentChange(
  current: number,
  previous: number,
): number | null {
  if (previous === 0) return null;
  return (current - previous) / previous;
}

/* ------------------------------------------------------------ firestore -- */

/**
 * Every aiUsage document, deduped per request.
 *
 * `cache()` matters here: the dashboard and this module's two public helpers
 * would otherwise each run the full collection-group scan. One scan per request
 * is the entire point.
 */
const readUsageRecords = cache(async (): Promise<UsageRecord[]> => {
  const snap = await adminDb().collectionGroup('aiUsage').get();

  return snap.docs.flatMap((doc) => {
    // parent.parent is the users/{uid} document. Absent only if some other
    // collection named aiUsage appears at the root, which the schema forbids.
    const uid = doc.ref.parent.parent?.id;
    if (!uid) return [];

    return [{ uid, month: doc.id, counts: toUsageCounts(doc.data()) }];
  });
});

/**
 * Per-counter totals for the current and previous UTC month.
 *
 * The clock read lives here rather than in the page: server components are held
 * to React's purity rules, and the month keys are a data concern anyway — they
 * must be derived in UTC to match the `YYYY-MM` document ids.
 */
export async function getUsageTotals(): Promise<UsageSummary> {
  const now = new Date();
  const records = await readUsageRecords();
  return summarizeUsage(records, yearMonth(now), previousYearMonth(now));
}

export interface TopConsumer extends ConsumerRow {
  email: string | null;
  premiumStatus: string | null;
}

/**
 * The heaviest consumers this month, enriched with the user document.
 *
 * Only the top [limit] user documents are fetched — and in a single `getAll`
 * round trip — so this stays cheap no matter how many users have usage.
 */
export async function getTopConsumers(limit = 10): Promise<TopConsumer[]> {
  const now = new Date();
  const records = await readUsageRecords();
  const ranked = rankConsumers(records, yearMonth(now), limit);
  if (ranked.length === 0) return [];

  const db = adminDb();
  const snaps = await db.getAll(
    ...ranked.map((row) => db.collection('users').doc(row.uid)),
  );
  const byUid = new Map(snaps.map((snap) => [snap.id, snap.data()]));

  return ranked.map((row) => {
    const user = byUid.get(row.uid);
    return {
      ...row,
      email: (user?.email as string | undefined) ?? null,
      premiumStatus: (user?.premiumStatus as string | undefined) ?? null,
    };
  });
}
