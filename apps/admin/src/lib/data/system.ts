import 'server-only';

import { adminDb } from '@/lib/firebase/admin';
import { yearMonth } from '@/lib/format';

import { FX_MONTHLY_CEILING, toMillis } from './user-mapping';

/**
 * Reads behind the System health page: scheduler heartbeats, the FX rate cache,
 * and whether the stats rollups have ever run.
 *
 * DEGRADE, NEVER THROW. This page's entire job is to be readable when the
 * deployment is broken — a credential failure or a missing collection must
 * render as "unknown" rather than a 500, because a 500 here tells an operator
 * nothing about which of the six things they were checking is at fault.
 *
 * QUERY SHAPE (CLAUDE.md §7 index policy): `adminHeartbeats` and `fxRates` are
 * read with an unfiltered `.get()` — both are bounded (one doc per scheduler,
 * one per currency pair in use), so a full read is cheaper than any index. The
 * rollup collections grow daily, so those are probed by deterministic document
 * id (`getAll` over the recent UTC date keys) rather than ordered: Firestore's
 * automatic key index is ascending only, so `orderBy('__name__','desc')` would
 * require a composite index this product deliberately does not ship. No
 * composite index exists or is needed for anything on this page.
 */

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/** `fxRates/{FROM-TO}` freshness window — mirrors `CACHE_TTL_MS` in
 *  apps/functions/src/fx/get_fx_rate.ts. If that constant changes, change this. */
export const FX_CACHE_TTL_MS = 12 * HOUR_MS;

/* --------------------------------------------------- schedule expectations -- */

export interface ScheduleExpectation {
  /** Exported function name — also the `adminHeartbeats` doc id. */
  readonly functionName: string;
  /** The cron string declared in the function's `onSchedule` options. */
  readonly cron: string;
  /** Human-readable cadence. */
  readonly cadence: string;
  /**
   * Grace window. A run older than this means the schedule is not being kept.
   * Always the cadence plus slack: Cloud Scheduler fires within a few minutes
   * of the cron, but a retry, a cold start, or a long run can push the *next*
   * recorded run out, and a false alarm on this page is worse than a late one.
   */
  readonly overdueAfterMs: number;
  readonly purpose: string;
  /** Where the function lives, so an operator can go read it. */
  readonly source: string;
}

/**
 * The three scheduled functions this deployment ships (see
 * apps/functions/src/index.ts). Adding a fourth means adding it here — an
 * unlisted heartbeat still renders, but with no cadence to judge it against.
 */
export const SCHEDULE_EXPECTATIONS: readonly ScheduleExpectation[] = [
  {
    functionName: 'processRecurringRules',
    cron: '0 0 * * *',
    cadence: 'Daily · 00:00 UTC',
    // 24h + 2h slack.
    overdueAfterMs: 26 * HOUR_MS,
    purpose:
      'Materializes due recurring rules into real transactions for every user.',
    source: 'apps/functions/src/schedulers/process_recurring_rules.ts',
  },
  {
    functionName: 'aggregatePlatformStats',
    cron: '30 0 * * *',
    cadence: 'Daily · 00:30 UTC',
    overdueAfterMs: 26 * HOUR_MS,
    purpose:
      'Writes the adminStatsDaily snapshot the panel needs for growth trends.',
    source: 'apps/functions/src/schedulers/aggregate_platform_stats.ts',
  },
  {
    functionName: 'resetMonthlyAIQuotas',
    cron: '0 0 1 * *',
    cadence: 'Monthly · 00:00 UTC on the 1st',
    // Longest month (31d) + 2d slack.
    overdueAfterMs: 33 * DAY_MS,
    purpose:
      'Rolls up adminStatsMonthly, then deletes aiUsage documents older than last month.',
    source: 'apps/functions/src/schedulers/reset_monthly_quotas.ts',
  },
];

/* ------------------------------------------------------------- heartbeats -- */

export interface HeartbeatRecord {
  /** The document id, i.e. the exported function name. */
  functionName: string;
  lastRunAtMs: number | null;
  status: 'ok' | 'error' | null;
  durationMs: number | null;
  /** Unit-of-work count the function chose to report. Meaning is per-function. */
  processed: number | null;
  error: string | null;
}

export type SchedulerState = 'ok' | 'error' | 'overdue' | 'never';

export interface SchedulerHealth {
  expectation: ScheduleExpectation;
  /** Null when no `adminHeartbeats` document exists yet. */
  heartbeat: HeartbeatRecord | null;
  state: SchedulerState;
  /**
   * True when no run has been RECORDED inside the expected window. Kept
   * separate from `state` because a scheduler can be both errored and stale,
   * and collapsing the two would hide one of them.
   */
  overdue: boolean;
  /** Time since the last recorded run; null when that is unknown. */
  ageMs: number | null;
}

/**
 * Coerces a raw `adminHeartbeats/{fn}` document.
 *
 * Everything is defensive: this document is written from a `finally` block
 * while an exception may be in flight, and a half-written or hand-edited doc
 * must degrade to "unknown" rather than render `NaN` or `Invalid Date`.
 */
export function toHeartbeatRecord(
  functionName: string,
  data: unknown,
): HeartbeatRecord {
  const raw = (data ?? {}) as Record<string, unknown>;

  const status = raw.status;
  const durationMs = raw.durationMs;
  const processed = raw.processed;
  const error = raw.error;

  return {
    functionName,
    lastRunAtMs: toMillis(raw.lastRunAt),
    status: status === 'ok' || status === 'error' ? status : null,
    durationMs:
      typeof durationMs === 'number' && Number.isFinite(durationMs)
        ? durationMs
        : null,
    processed:
      typeof processed === 'number' && Number.isFinite(processed)
        ? processed
        : null,
    // `writeHeartbeat` deletes this field on a successful run, so a non-empty
    // string here always belongs to the run reported by `status`.
    error: typeof error === 'string' && error.length > 0 ? error : null,
  };
}

/**
 * Health for one scheduler.
 *
 * `never` — no heartbeat document at all. A heartbeat only appears AFTER the
 * first run following deployment, so on a project that has not deployed the
 * Phase 3 functions yet this is the EXPECTED state and not a fault. It is also
 * what a deployed-but-never-triggered scheduler looks like; the two are
 * indistinguishable from Firestore, which is why the page says so in words.
 *
 * `error` outranks `overdue`: both can be true, but the stored message is the
 * only thing that explains WHY the schedule stopped being kept, so it must not
 * be masked. The `overdue` flag stays set so the UI can show both.
 *
 * A document with an unusable `lastRunAt` counts as overdue rather than ok —
 * we cannot prove a recent run happened, and an unprovable heartbeat must
 * never read green.
 */
export function deriveSchedulerHealth(
  expectation: ScheduleExpectation,
  heartbeat: HeartbeatRecord | null,
  nowMs: number,
): SchedulerHealth {
  if (heartbeat === null) {
    // Not flagged overdue: with no document there is no evidence the function
    // is even deployed, and "overdue" would accuse an operator of a fault that
    // may not exist.
    return { expectation, heartbeat, state: 'never', overdue: false, ageMs: null };
  }

  const ageMs =
    heartbeat.lastRunAtMs == null ? null : nowMs - heartbeat.lastRunAtMs;

  // `>` not `>=`: a run landing exactly on the window boundary is still inside
  // it. Negative ages (a server clock ahead of this one) are never overdue.
  const overdue = ageMs == null || ageMs > expectation.overdueAfterMs;

  const state: SchedulerState =
    heartbeat.status === 'error' ? 'error' : overdue ? 'overdue' : 'ok';

  return { expectation, heartbeat, state, overdue, ageMs };
}

export interface SchedulerReport {
  /** One entry per expectation, in table order — including ones never run. */
  schedulers: SchedulerHealth[];
  /**
   * Heartbeats whose function is not in `SCHEDULE_EXPECTATIONS`. Surfaced
   * rather than dropped: silently hiding a scheduler somebody added is exactly
   * the blind spot heartbeats exist to close.
   */
  extras: HeartbeatRecord[];
}

export function buildSchedulerReport(
  records: readonly HeartbeatRecord[],
  nowMs: number,
): SchedulerReport {
  const byName = new Map(records.map((r) => [r.functionName, r]));

  const schedulers = SCHEDULE_EXPECTATIONS.map((expectation) =>
    deriveSchedulerHealth(
      expectation,
      byName.get(expectation.functionName) ?? null,
      nowMs,
    ),
  );

  const known = new Set(SCHEDULE_EXPECTATIONS.map((e) => e.functionName));
  const extras = records
    .filter((r) => !known.has(r.functionName))
    .sort((a, b) => a.functionName.localeCompare(b.functionName));

  return { schedulers, extras };
}

/* --------------------------------------------------------------- fx cache -- */

export interface FxCacheRow {
  /** Document id, `FROM-TO`. */
  pair: string;
  from: string | null;
  to: string | null;
  rate: number | null;
  fetchedAtMs: number | null;
  ageMs: number | null;
  /** Past the 12h TTL. Informational — the next request refreshes it. */
  stale: boolean;
}

export function toFxCacheRow(
  pair: string,
  data: unknown,
  nowMs: number,
): FxCacheRow {
  const raw = (data ?? {}) as Record<string, unknown>;
  const rate = raw.rate;
  const fetchedAtMs = toMillis(raw.fetchedAt);
  const ageMs = fetchedAtMs == null ? null : nowMs - fetchedAtMs;

  return {
    pair,
    from: typeof raw.from === 'string' ? raw.from : null,
    to: typeof raw.to === 'string' ? raw.to : null,
    rate: typeof rate === 'number' && Number.isFinite(rate) ? rate : null,
    fetchedAtMs,
    ageMs,
    // An entry with no readable `fetchedAt` is treated as stale: getFxRate's
    // freshness check fails closed the same way and re-fetches it.
    stale: ageMs == null || ageMs >= FX_CACHE_TTL_MS,
  };
}

/* ---------------------------------------------------------------- rollups -- */

export interface RollupCollectionState {
  collection: string;
  /** Newest document id — a `YYYY-MM-DD` or `YYYY-MM` key. */
  latestId: string | null;
  /** When that document was written, from `computedAt` / `rolledUpAt`. */
  writtenAtMs: number | null;
  /** How much history has accumulated. */
  documentCount: number;
  /** The collection could not be read at all — not the same as "empty". */
  unreadable: boolean;
}

/* ------------------------------------------------------- function secrets -- */

export interface FunctionSecret {
  readonly name: string;
  readonly usedBy: string;
  /** What breaks when it is unset. */
  readonly impact: string;
}

/**
 * Cloud Functions secrets, listed for the checklist.
 *
 * The panel CANNOT read these and never will: they live in Secret Manager and
 * are mounted only into the Functions runtime. Showing an unverifiable
 * "configured ✓" would be a lie an operator could act on, so the page prints
 * the `firebase functions:secrets:set` commands instead and says plainly that
 * it has not checked them.
 */
export const FUNCTION_SECRETS: readonly FunctionSecret[] = [
  {
    name: 'OPENAI_API_KEY',
    usedBy: 'every AI callable + scanReceipt vision',
    impact:
      'OpenAI-backed calls fail. Receipt scanning defaults to gpt-4o, so it breaks even when ai_provider is gemini.',
  },
  {
    name: 'GEMINI_API_KEY',
    usedBy: 'every AI callable',
    impact:
      'Gemini-backed calls fail. Eight of the nine callables default to gemini-2.5-flash-lite, so this is the one most deployments need.',
  },
  {
    name: 'EXCHANGERATE_API_KEY',
    usedBy: 'getFxRate',
    impact:
      'FX lookups fall back to the last cached rate; with no cache the app asks the user to type a rate manually.',
  },
  {
    name: 'REVENUECAT_WEBHOOK_SECRET',
    usedBy: 'handleRevenueCatWebhook',
    impact:
      'Every webhook is rejected, so purchases, renewals, and cancellations never reach users/{uid}.premiumStatus.',
  },
  {
    name: 'REVENUECAT_API_KEY',
    usedBy: 'refreshEntitlement',
    impact: 'Manual entitlement re-sync from RevenueCat fails.',
  },
];

/* -------------------------------------------------------------- firestore -- */

export interface SystemHealth {
  /** The clock every relative time on the page is rendered against. */
  nowMs: number;
  schedulers: SchedulerHealth[];
  extraHeartbeats: HeartbeatRecord[];
  heartbeatsUnreadable: boolean;
  fxRates: FxCacheRow[];
  fxUnreadable: boolean;
  fxTtlMs: number;
  /** getFxRate's own hardcoded monthly cap — not the Remote Config AI quota. */
  fxMonthlyCeiling: number;
  daily: RollupCollectionState;
  monthly: RollupCollectionState;
}

async function readHeartbeats(): Promise<{
  records: HeartbeatRecord[];
  unreadable: boolean;
}> {
  try {
    const snap = await adminDb().collection('adminHeartbeats').get();
    return {
      records: snap.docs.map((doc) => toHeartbeatRecord(doc.id, doc.data())),
      unreadable: false,
    };
  } catch (e) {
    console.error('[admin] adminHeartbeats read failed:', e);
    return { records: [], unreadable: true };
  }
}

async function readFxRates(
  nowMs: number,
): Promise<{ rows: FxCacheRow[]; unreadable: boolean }> {
  try {
    const snap = await adminDb().collection('fxRates').get();
    const rows = snap.docs.map((doc) =>
      toFxCacheRow(doc.id, doc.data(), nowMs),
    );
    // Alphabetical by pair — a stable order, so a reload never looks like the
    // cache changed when it did not.
    rows.sort((a, b) => a.pair.localeCompare(b.pair));
    return { rows, unreadable: false };
  } catch (e) {
    console.error('[admin] fxRates read failed:', e);
    return { rows: [], unreadable: true };
  }
}

/** UTC `YYYY-MM-DD`, matching the `adminStatsDaily` document ids. */
function dayKey(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * The document ids to probe, newest first.
 *
 * Both rollups key their documents on a UTC date, so the ids are fully
 * predictable — we can name the recent ones instead of asking Firestore to
 * order anything.
 */
export function recentRollupIds(
  kind: 'daily' | 'monthly',
  nowMs: number,
  window: number,
): string[] {
  const out: string[] = [];
  for (let i = 0; i < window; i++) {
    if (kind === 'daily') {
      out.push(dayKey(nowMs - i * DAY_MS));
    } else {
      const d = new Date(nowMs);
      out.push(yearMonth(new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - i, 1))));
    }
  }
  return out;
}

/** How far back to look for the most recent rollup document. */
const DAILY_PROBE_DAYS = 14;
const MONTHLY_PROBE_MONTHS = 6;

/**
 * Newest rollup document plus how many exist.
 *
 * Deliberately NOT `orderBy('__name__','desc').limit(1)`. Firestore's automatic
 * key index is ASCENDING only, so ordering by `__name__` descending demands an
 * explicit composite index — which a fresh buyer project would not have, making
 * this page fail with FAILED_PRECONDITION until someone deployed one. The
 * repo-wide policy (CLAUDE.md §7) is to avoid composite indexes, so instead we
 * exploit the fact that the ids are derived from a UTC date and simply ask for
 * the ones that would exist, newest first, via a single `getAll`.
 *
 * Cost is one read per probed id and needs no index. Looking back
 * ${DAILY_PROBE_DAYS} days / ${MONTHLY_PROBE_MONTHS} months is far past the
 * point where a scheduler is already flagged overdue, so anything older is
 * reported as "nothing recent" — which is the same operational answer.
 */
async function readRollup(
  collection: string,
  writtenAtField: string,
  kind: 'daily' | 'monthly',
  nowMs: number,
): Promise<RollupCollectionState> {
  try {
    const db = adminDb();
    const ref = db.collection(collection);
    const ids = recentRollupIds(
      kind,
      nowMs,
      kind === 'daily' ? DAILY_PROBE_DAYS : MONTHLY_PROBE_MONTHS,
    );

    const [docs, count] = await Promise.all([
      db.getAll(...ids.map((id) => ref.doc(id))),
      ref.count().get(),
    ]);

    // `ids` is newest-first, and getAll preserves input order.
    const doc = docs.find((d) => d.exists);

    return {
      collection,
      latestId: doc?.id ?? null,
      writtenAtMs: doc ? toMillis(doc.data()?.[writtenAtField]) : null,
      documentCount: count.data().count,
      unreadable: false,
    };
  } catch (e) {
    console.error(`[admin] ${collection} read failed:`, e);
    return {
      collection,
      latestId: null,
      writtenAtMs: null,
      documentCount: 0,
      unreadable: true,
    };
  }
}

/**
 * Everything /system renders, in one call.
 *
 * The clock is read here rather than in the page: server components are held to
 * React's purity rules, and every staleness judgement below has to be made
 * against one consistent instant anyway.
 */
export async function loadSystemHealth(): Promise<SystemHealth> {
  const nowMs = Date.now();

  const [heartbeats, fx, daily, monthly] = await Promise.all([
    readHeartbeats(),
    readFxRates(nowMs),
    readRollup('adminStatsDaily', 'computedAt', 'daily', nowMs),
    readRollup('adminStatsMonthly', 'rolledUpAt', 'monthly', nowMs),
  ]);

  const report = buildSchedulerReport(heartbeats.records, nowMs);

  return {
    nowMs,
    schedulers: report.schedulers,
    extraHeartbeats: report.extras,
    heartbeatsUnreadable: heartbeats.unreadable,
    fxRates: fx.rows,
    fxUnreadable: fx.unreadable,
    fxTtlMs: FX_CACHE_TTL_MS,
    fxMonthlyCeiling: FX_MONTHLY_CEILING,
    daily,
    monthly,
  };
}
