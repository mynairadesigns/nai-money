import Link from 'next/link';
import type { ReactNode } from 'react';

import { Badge, Card, CardTitle, EmptyState, Stat } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { requireAdmin } from '@/lib/auth/require-admin';
import {
  loadSystemHealth,
  FUNCTION_SECRETS,
  type FxCacheRow,
  type HeartbeatRecord,
  type RollupCollectionState,
  type SchedulerHealth,
  type SchedulerState,
  type SystemHealth,
} from '@/lib/data/system';
import {
  EMPTY,
  formatDateTime,
  formatNumber,
  formatRelative,
} from '@/lib/format';
import {
  RC_MANIFEST,
  RC_READ_BY_BLURB,
  RC_READ_BY_LABEL,
  RC_READ_BY_ORDER,
  type RcKeyDef,
  type RcReadBy,
} from '@/lib/remote-config/manifest';
import { readRemoteConfig } from '@/lib/remote-config/read';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * System health.
 *
 * Read-only, and deliberately the one page that still renders when everything
 * else is broken: every read degrades to "unknown" rather than throwing, so a
 * deployment with no credentials, no deployed schedulers, and an empty
 * Firestore still gets a page that says which of those is true.
 *
 * Nothing here is a live probe. Firestore is the only thing the panel can see,
 * so a scheduler is judged by the trace it leaves (`adminHeartbeats`), not by
 * asking Cloud Scheduler — and Secret Manager is invisible entirely.
 */
export default async function SystemPage() {
  await requireAdmin();

  const [health, rc] = await Promise.all([loadSystemHealth(), readRemoteConfig()]);

  const healthy = health.schedulers.filter((s) => s.state === 'ok').length;
  const staleFx = health.fxRates.filter((row) => row.stale).length;
  const ttlHours = Math.round(health.fxTtlMs / (60 * 60 * 1000));

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">System health</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Whether the scheduled jobs are running, how fresh the caches are, and
          what is left to configure. Everything below is inferred from what the
          backend wrote to Firestore — this page never calls a Function.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Schedulers reporting"
          value={`${healthy}/${health.schedulers.length}`}
          hint={
            health.heartbeatsUnreadable
              ? 'adminHeartbeats unreadable'
              : 'ran inside their window'
          }
        />
        <Stat
          label="FX pairs cached"
          value={formatNumber(health.fxRates.length)}
          hint={`${formatNumber(staleFx)} past the ${ttlHours}h TTL`}
        />
        <Stat
          label="Daily rollups"
          value={formatNumber(health.daily.documentCount)}
          hint={health.daily.latestId ?? 'never run'}
        />
        <Stat
          label="Monthly rollups"
          value={formatNumber(health.monthly.documentCount)}
          hint={health.monthly.latestId ?? 'never run'}
        />
      </div>

      <SchedulersCard health={health} />
      <FxCard
        rows={health.fxRates}
        unreadable={health.fxUnreadable}
        nowMs={health.nowMs}
        ttlHours={ttlHours}
        monthlyCeiling={health.fxMonthlyCeiling}
      />
      <RollupsCard
        daily={health.daily}
        monthly={health.monthly}
        nowMs={health.nowMs}
      />
      <ConfigurationCard
        setKeys={rc.values}
        conditional={rc.conditional}
        templateUnreadable={rc.etag === null}
      />
    </div>
  );
}

/* ------------------------------------------------------------ schedulers -- */

const STATE_TONE: Readonly<
  Record<SchedulerState, 'positive' | 'warning' | 'critical' | 'neutral'>
> = {
  ok: 'positive',
  error: 'critical',
  overdue: 'warning',
  never: 'neutral',
};

const STATE_LABEL: Readonly<Record<SchedulerState, string>> = {
  ok: 'ok',
  error: 'failed',
  overdue: 'overdue',
  never: 'never run',
};

function SchedulersCard({ health }: { health: SystemHealth }) {
  return (
    <Card className="flex flex-col gap-4">
      <div>
        <CardTitle>Scheduled functions</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Each run overwrites one <code>adminHeartbeats/&#123;function&#125;</code>{' '}
          document, so what follows is the <strong>last</strong> run only — there
          is no run history to page through.
        </p>
      </div>

      {health.heartbeatsUnreadable ? (
        <EmptyState
          title="Could not read adminHeartbeats"
          body="The collection query failed, which usually means the server's Firebase credentials are missing rather than that the schedulers are down. The statuses below are therefore unknown, not healthy."
        />
      ) : null}

      <Table>
        <THead>
          <TH>Function</TH>
          <TH>Status</TH>
          <TH>Last run</TH>
          <TH numeric>Duration</TH>
          <TH numeric>Processed</TH>
          <TH>Expected cadence</TH>
        </THead>
        <TBody>
          {health.schedulers.map((row) => (
            <SchedulerRow
              key={row.expectation.functionName}
              row={row}
              nowMs={health.nowMs}
            />
          ))}
        </TBody>
      </Table>

      {health.extraHeartbeats.length > 0 ? (
        <ExtraHeartbeats
          records={health.extraHeartbeats}
          nowMs={health.nowMs}
        />
      ) : null}

      <ul className="flex flex-col gap-2 text-body-md text-on-surface-variant">
        <Bullet>
          <strong className="text-on-surface">
            &ldquo;Never run&rdquo; is not automatically a fault.
          </strong>{' '}
          A heartbeat document only appears <em>after</em> the first run
          following a deploy, so this is the expected state on a project where
          the Phase 3 functions have not been deployed yet. It looks identical
          to a deployed scheduler that has never fired — Firestore cannot tell
          the two apart. Confirm with{' '}
          <code>firebase deploy --only functions</code> and the Cloud Scheduler
          console.
        </Bullet>
        <Bullet>
          <strong className="text-on-surface">
            A failed run is retried by Cloud Scheduler.
          </strong>{' '}
          All three re-throw after recording the heartbeat, so a single red
          status may already have been followed by a successful retry that has
          not been written yet. Two consecutive failures is the signal worth
          acting on.
        </Bullet>
        <Bullet>
          <strong className="text-on-surface">
            The windows include slack.
          </strong>{' '}
          A daily job is flagged after 26h and the monthly one after 33 days, so
          a late fire or a slow run does not raise a false alarm. The trade is
          that a job which stopped an hour ago still reads green.
        </Bullet>
      </ul>
    </Card>
  );
}

function SchedulerRow({
  row,
  nowMs,
}: {
  row: SchedulerHealth;
  nowMs: number;
}) {
  const { expectation, heartbeat, state } = row;

  return (
    <TR>
      <TD>
        <span className="text-on-surface">{expectation.functionName}</span>
        <span className="block text-label-sm text-on-surface-variant">
          {expectation.purpose}
        </span>
        {heartbeat?.error ? (
          // The stored message is the only explanation of WHY the schedule
          // stopped, so it is rendered in full rather than truncated.
          <span className="mt-1 block break-words text-label-sm text-error">
            {heartbeat.error}
          </span>
        ) : null}
      </TD>
      <TD>
        <div className="flex flex-wrap gap-2">
          <Badge tone={STATE_TONE[state]}>{STATE_LABEL[state]}</Badge>
          {/* Both facts matter when a run failed and was never retried. */}
          {state === 'error' && row.overdue ? (
            <Badge tone="warning">also overdue</Badge>
          ) : null}
        </div>
      </TD>
      <TD>
        {heartbeat?.lastRunAtMs == null ? (
          <span className="text-on-surface-variant">
            {heartbeat ? 'unknown' : EMPTY}
          </span>
        ) : (
          <>
            <span className="whitespace-nowrap">
              {formatDateTime(heartbeat.lastRunAtMs)}
            </span>
            <span className="block text-label-sm text-on-surface-variant">
              {formatRelative(heartbeat.lastRunAtMs, nowMs)}
            </span>
          </>
        )}
      </TD>
      <TD numeric>{formatDuration(heartbeat?.durationMs ?? null)}</TD>
      <TD numeric>{formatNumber(heartbeat?.processed ?? null)}</TD>
      <TD>
        <span className="whitespace-nowrap">{expectation.cadence}</span>
        <span className="block text-label-sm text-on-surface-variant">
          <code>{expectation.cron}</code>
        </span>
      </TD>
    </TR>
  );
}

/**
 * Heartbeats from functions this build has no expectation for — a scheduler
 * added after the panel was written. Shown without a verdict, because there is
 * no cadence to judge them against.
 */
function ExtraHeartbeats({
  records,
  nowMs,
}: {
  records: readonly HeartbeatRecord[];
  nowMs: number;
}) {
  return (
    <div className="rounded-lg bg-surface-container-low p-4">
      <p className="text-body-md text-on-surface">
        Heartbeats from functions this panel does not know about
      </p>
      <p className="mt-1 text-label-sm text-on-surface-variant">
        No cadence is recorded for these, so no staleness verdict is possible.
        Add them to <code>SCHEDULE_EXPECTATIONS</code> in{' '}
        <code>src/lib/data/system.ts</code> to have them judged.
      </p>
      <ul className="mt-2 flex flex-col gap-1">
        {records.map((record) => (
          <li
            key={record.functionName}
            className="text-label-sm text-on-surface-variant"
          >
            <code>{record.functionName}</code> — {record.status ?? 'unknown'},{' '}
            {formatRelative(record.lastRunAtMs, nowMs)}
          </li>
        ))}
      </ul>
    </div>
  );
}

/* -------------------------------------------------------------- fx cache -- */

function FxCard({
  rows,
  unreadable,
  nowMs,
  ttlHours,
  monthlyCeiling,
}: {
  rows: readonly FxCacheRow[];
  unreadable: boolean;
  nowMs: number;
  ttlHours: number;
  monthlyCeiling: number;
}) {
  return (
    <Card className="flex flex-col gap-4">
      <div>
        <CardTitle>FX rate cache</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          <code>fxRates/&#123;FROM-TO&#125;</code>, written by{' '}
          <code>getFxRate</code>. Entries older than {ttlHours}h are refreshed on
          the next request for that pair, so{' '}
          <strong className="text-on-surface">stale is informational</strong> —
          it means nobody has converted that pair recently, not that anything is
          broken.
        </p>
      </div>

      {unreadable ? (
        <EmptyState
          title="Could not read fxRates"
          body="The collection query failed. That is a credentials or connectivity problem on this server, not evidence about the cache."
        />
      ) : rows.length === 0 ? (
        <EmptyState
          title="No cached rates"
          body="Nothing has called getFxRate yet. The cache is created lazily on the first cross-currency transfer, so an empty collection is normal on a new deployment."
        />
      ) : (
        <Table>
          <THead>
            <TH>Pair</TH>
            <TH numeric>Rate</TH>
            <TH>Fetched</TH>
            <TH>Age</TH>
            <TH>Freshness</TH>
          </THead>
          <TBody>
            {rows.map((row) => (
              <TR key={row.pair}>
                <TD>
                  <code>{row.pair}</code>
                </TD>
                <TD numeric>
                  {row.rate == null ? EMPTY : row.rate.toString()}
                </TD>
                <TD>
                  <span className="whitespace-nowrap">
                    {formatDateTime(row.fetchedAtMs)}
                  </span>
                </TD>
                <TD>{formatRelative(row.fetchedAtMs, nowMs)}</TD>
                <TD>
                  <Badge tone={row.stale ? 'neutral' : 'positive'}>
                    {row.stale ? 'past TTL' : 'fresh'}
                  </Badge>
                </TD>
              </TR>
            ))}
          </TBody>
        </Table>
      )}

      <ul className="flex flex-col gap-2 text-body-md text-on-surface-variant">
        <Bullet>
          <strong className="text-on-surface">
            The cache is shared, the quota is not.
          </strong>{' '}
          One document per pair serves every user, but the{' '}
          <code>fx</code> counter is per user and has its{' '}
          <strong className="text-on-surface">
            own ceiling of {formatNumber(monthlyCeiling)} calls per month
          </strong>
          , hardcoded in <code>get_fx_rate.ts</code>. It is separate from the AI
          quota and no Remote Config key changes it. Only a provider call
          increments it — a cache hit is free.
        </Bullet>
        <Bullet>
          <strong className="text-on-surface">
            A stale entry is also the fallback.
          </strong>{' '}
          When the provider fails, <code>getFxRate</code> returns the cached rate
          regardless of age rather than erroring. A very old entry here means a
          pair that is either unused or being served past its TTL because the
          provider is down.
        </Bullet>
      </ul>
    </Card>
  );
}

/* --------------------------------------------------------------- rollups -- */

function RollupsCard({
  daily,
  monthly,
  nowMs,
}: {
  daily: RollupCollectionState;
  monthly: RollupCollectionState;
  nowMs: number;
}) {
  return (
    <Card className="flex flex-col gap-4">
      <div>
        <CardTitle>Rollup freshness</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          The two collections that give this panel any history at all. Live
          Firestore only ever answers &ldquo;right now&rdquo;.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <RollupPanel
          state={daily}
          nowMs={nowMs}
          title="adminStatsDaily"
          writtenBy="aggregatePlatformStats"
          idFormat="YYYY-MM-DD"
          describes="the calendar day that had just closed when it ran"
        />
        <RollupPanel
          state={monthly}
          nowMs={nowMs}
          title="adminStatsMonthly"
          writtenBy="resetMonthlyAIQuotas"
          idFormat="YYYY-MM"
          describes="AI usage for that month, folded from the aiUsage scan"
        />
      </div>

      <ul className="flex flex-col gap-2 text-body-md text-on-surface-variant">
        <Bullet>
          <strong className="text-on-surface">
            Daily stats cannot be backfilled.
          </strong>{' '}
          Every figure comes from a <code>count()</code> against the live{' '}
          <code>users</code> collection, which only ever describes the present.
          There is no record of what those counts were yesterday, so history
          starts accumulating on the day <code>aggregatePlatformStats</code> is
          first deployed and no earlier — a gap left by a scheduler that was down
          stays a gap permanently.
        </Bullet>
        <Bullet>
          <strong className="text-on-surface">
            Monthly rollups partly can.
          </strong>{' '}
          <code>resetMonthlyAIQuotas</code> rolls up every month still present in{' '}
          <code>users/&#123;uid&#125;/aiUsage</code> before deleting the stale
          ones, so its first run captures the current and previous month. Beyond
          that the source documents are already gone.
        </Bullet>
        <Bullet>
          <strong className="text-on-surface">Absent means never run.</strong> No
          other writer touches either collection, so an empty one is a scheduler
          that has not run — not a scheduler that ran and found nothing.
        </Bullet>
      </ul>
    </Card>
  );
}

function RollupPanel({
  state,
  nowMs,
  title,
  writtenBy,
  idFormat,
  describes,
}: {
  state: RollupCollectionState;
  nowMs: number;
  title: string;
  writtenBy: string;
  idFormat: string;
  describes: string;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-lg bg-surface-container-low p-4">
      <div className="flex flex-wrap items-center gap-2">
        <p className="text-body-lg text-on-surface">
          <code>{title}</code>
        </p>
        {state.unreadable ? (
          <Badge tone="critical">unreadable</Badge>
        ) : state.latestId ? (
          <Badge tone="positive">
            {formatNumber(state.documentCount)} documents
          </Badge>
        ) : (
          <Badge tone="warning">never run</Badge>
        )}
      </div>

      <p className="text-body-md text-on-surface-variant">
        Written by <code>{writtenBy}</code>. Document id is a{' '}
        <code>{idFormat}</code> key describing {describes}.
      </p>

      <dl className="flex flex-col gap-1 text-label-sm text-on-surface-variant">
        <div className="flex justify-between gap-4">
          <dt>Newest document</dt>
          <dd className="text-on-surface">
            {state.unreadable ? 'unknown' : (state.latestId ?? 'none')}
          </dd>
        </div>
        <div className="flex justify-between gap-4">
          <dt>Written</dt>
          <dd className="text-on-surface">
            {state.writtenAtMs == null
              ? EMPTY
              : `${formatDateTime(state.writtenAtMs)} · ${formatRelative(state.writtenAtMs, nowMs)}`}
          </dd>
        </div>
      </dl>
    </div>
  );
}

/* --------------------------------------------------------- configuration -- */

function ConfigurationCard({
  setKeys,
  conditional,
  templateUnreadable,
}: {
  setKeys: ReadonlyMap<string, string>;
  conditional: ReadonlySet<string>;
  templateUnreadable: boolean;
}) {
  const groups = RC_READ_BY_ORDER.map((readBy) => ({
    readBy,
    keys: RC_MANIFEST.filter((key) => key.readBy === readBy),
  }));

  return (
    <Card className="flex flex-col gap-6">
      <div>
        <CardTitle>Configuration checklist</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Which of the documented Remote Config keys this project actually
          publishes. An unset key is not automatically wrong — every one has a
          fallback baked into the code — but a key that is <em>expected</em> to
          be set and is not is the usual cause of a feature that silently does
          nothing. Values and editing live in{' '}
          <Link href="/remote-config" className="text-primary hover:underline">
            Remote Config
          </Link>
          .
        </p>
      </div>

      {templateUnreadable ? (
        <EmptyState
          title="Could not read the Remote Config template"
          body="Every key below will therefore read as unset. Check the server's credentials and that the runtime service account has the Firebase Remote Config Viewer role before concluding anything from this list."
        />
      ) : null}

      {groups.map((group) => (
        <RcGroup
          key={group.readBy}
          readBy={group.readBy}
          keys={group.keys}
          setKeys={setKeys}
          conditional={conditional}
        />
      ))}

      <SecretsSection />
    </Card>
  );
}

function RcGroup({
  readBy,
  keys,
  setKeys,
  conditional,
}: {
  readBy: RcReadBy;
  keys: readonly RcKeyDef[];
  setKeys: ReadonlyMap<string, string>;
  conditional: ReadonlySet<string>;
}) {
  const setCount = keys.filter((key) => setKeys.has(key.name)).length;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-baseline gap-4">
        <h3 className="text-body-lg text-on-surface">
          {RC_READ_BY_LABEL[readBy]}
        </h3>
        <span className="text-label-sm text-on-surface-variant">
          {setCount} of {keys.length} set
        </span>
      </div>
      <p className="max-w-prose text-body-md text-on-surface-variant">
        {RC_READ_BY_BLURB[readBy]}
      </p>

      {/* The inert keys get no table: the only thing worth knowing is whether
          one has been set, since setting it changes nothing either way. */}
      {readBy === 'none' ? (
        <div className="flex flex-wrap gap-2 pt-1">
          {keys.map((key) => (
            <Badge
              key={key.name}
              tone={setKeys.has(key.name) ? 'warning' : 'neutral'}
            >
              {key.name}
              {setKeys.has(key.name) ? ' · set but inert' : ''}
            </Badge>
          ))}
        </div>
      ) : (
        <Table>
          <THead>
            <TH>Key</TH>
            <TH>In template</TH>
            <TH>Falls back to</TH>
          </THead>
          <TBody>
            {keys.map((key) => (
              <TR key={key.name}>
                <TD>
                  <code>{key.name}</code>
                  <span className="block max-w-prose text-label-sm text-on-surface-variant">
                    {key.description}
                  </span>
                </TD>
                <TD>
                  <div className="flex flex-wrap gap-2">
                    <Badge tone={setKeys.has(key.name) ? 'positive' : 'neutral'}>
                      {setKeys.has(key.name) ? 'set' : 'not set'}
                    </Badge>
                    {/* Conditions are invisible to Cloud Functions, which read
                        the defaultValue only. */}
                    {conditional.has(key.name) ? (
                      <Badge tone="warning">
                        {readBy === 'server'
                          ? 'conditional · ignored server-side'
                          : 'has conditions'}
                      </Badge>
                    ) : null}
                  </div>
                </TD>
                <TD>
                  <code>
                    {key.defaultValue === ''
                      ? 'empty'
                      : key.defaultValue}
                  </code>
                </TD>
              </TR>
            ))}
          </TBody>
        </Table>
      )}
    </div>
  );
}

function SecretsSection() {
  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-body-lg text-on-surface">Cloud Functions secrets</h3>
      <p className="max-w-prose text-body-md text-on-surface-variant">
        <strong className="text-on-surface">
          This panel cannot check any of these.
        </strong>{' '}
        They live in Secret Manager and are mounted only into the Functions
        runtime — there is no read path from here, and printing a green tick
        without one would be a guess. Verify with{' '}
        <code>firebase functions:secrets:access &lt;NAME&gt;</code>, and set a
        missing one with the command listed below. A secret set after the last
        deploy needs a redeploy of the functions that use it.
      </p>

      <Table>
        <THead>
          <TH>Secret</TH>
          <TH>Used by</TH>
          <TH>If unset</TH>
        </THead>
        <TBody>
          {FUNCTION_SECRETS.map((secret) => (
            <TR key={secret.name}>
              <TD>
                <code>{secret.name}</code>
                <span className="block text-label-sm text-on-surface-variant">
                  <code>firebase functions:secrets:set {secret.name}</code>
                </span>
              </TD>
              <TD className="text-on-surface-variant">{secret.usedBy}</TD>
              <TD>
                <span className="block max-w-prose text-body-md text-on-surface-variant">
                  {secret.impact}
                </span>
              </TD>
            </TR>
          ))}
        </TBody>
      </Table>
    </div>
  );
}

/* --------------------------------------------------------------- helpers -- */

function Bullet({ children }: { children: ReactNode }) {
  return (
    <li className="flex gap-4">
      <span aria-hidden className="text-primary">
        —
      </span>
      <span className="max-w-prose">{children}</span>
    </li>
  );
}

/**
 * Run duration. Sub-second runs are the common case for a scheduler with
 * nothing to do, and rounding those to "0s" would hide the difference between
 * a fast run and a run that never happened.
 */
function formatDuration(ms: number | null): string {
  if (ms == null) return EMPTY;
  if (ms < 1000) return `${Math.round(ms)}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.round(ms / 60_000)}m`;
}
