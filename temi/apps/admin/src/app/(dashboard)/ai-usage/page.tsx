import Link from 'next/link';

import { Badge, Card, CardTitle, EmptyState, Stat } from '@/components/ui';
import { Meter, Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { requireAdmin } from '@/lib/auth/require-admin';
import {
  estimateCost,
  type FeatureEstimate,
  type ProviderSetting,
} from '@/lib/cost/estimate';
import {
  getTopConsumers,
  getUsageTotals,
  percentChange,
} from '@/lib/data/ai-usage';
import { EMPTY, formatNumber, formatUsd } from '@/lib/format';
import {
  freeTierLimits,
  rcString,
  readRemoteConfig,
} from '@/lib/remote-config/read';

import { Assumptions } from './assumptions';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const TOP_CONSUMER_LIMIT = 10;

/**
 * AI usage & cost.
 *
 * Reads `users/{uid}/aiUsage` live. There are no trend charts here and there
 * cannot be: `resetMonthlyAIQuotas` deletes everything older than the previous
 * month, so two columns is the entire history that exists. The Phase 3
 * `adminStatsMonthly` rollup is what turns this into a time series.
 */
export default async function AiUsagePage() {
  await requireAdmin();

  const [summary, consumers, rc] = await Promise.all([
    getUsageTotals(),
    getTopConsumers(TOP_CONSUMER_LIMIT),
    readRemoteConfig(),
  ]);

  // Deliberately NOT trimmed or case-folded: selectProvider() compares the raw
  // string against 'openai' | 'gemini', so ' OpenAI ' is ignored by the backend
  // and must read as ignored here too.
  const rawProvider = rcString(rc, 'ai_provider', '');
  const setting: ProviderSetting =
    rawProvider === 'openai' || rawProvider === 'gemini' ? rawProvider : null;
  const providerUnrecognized = rawProvider !== '' && setting === null;

  const current = estimateCost(summary.totals.current, setting);
  const previous = estimateCost(summary.totals.previous, setting);
  const previousByFeature = new Map(
    previous.perFeature.map((line) => [line.feature, line]),
  );

  const aiCeiling = freeTierLimits(rc).aiMonthly;

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">AI usage &amp; cost</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Live counters for {summary.currentMonth} and {summary.previousMonth},
          read straight from <code>users/&#123;uid&#125;/aiUsage</code>. Spend is
          an estimate derived from call counts and documented token assumptions —
          not a bill.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label={`AI calls · ${summary.currentMonth}`}
          value={formatNumber(summary.llmCalls.current)}
          hint={`${formatNumber(summary.activeUsers.current)} users · ${formatNumber(summary.premiumCalls.current)} premium`}
        />
        <Stat
          label={`AI calls · ${summary.previousMonth}`}
          value={formatNumber(summary.llmCalls.previous)}
          hint={`${formatNumber(summary.activeUsers.previous)} users`}
        />
        <Stat
          label="Quota rejections"
          value={formatNumber(summary.rejected.current)}
          hint="not recorded yet — see below"
        />
        <Stat
          label="Estimated spend"
          value={formatUsd(current.totalUsd)}
          hint={`${summary.previousMonth}: ${formatUsd(previous.totalUsd)}`}
        />
      </div>

      <ProviderCard
        setting={setting}
        rawProvider={rawProvider}
        unrecognized={providerUnrecognized}
        conditional={rc.conditional.has('ai_provider')}
      />

      {summary.hasAnyUsage ? (
        <>
          <Card className="flex flex-col gap-4">
            <CardTitle>By feature</CardTitle>
            <Table>
              <THead>
                <TH>Feature</TH>
                <TH>Model</TH>
                <TH numeric>{summary.currentMonth}</TH>
                <TH numeric>{summary.previousMonth}</TH>
                <TH numeric>Change</TH>
                <TH numeric>Est. cost</TH>
              </THead>
              <TBody>
                {current.perFeature.map((line) => (
                  <FeatureRow
                    key={line.feature}
                    line={line}
                    previousCalls={
                      previousByFeature.get(line.feature)?.calls ?? 0
                    }
                  />
                ))}
                <TR>
                  <TD className="text-label-md uppercase">Total</TD>
                  <TD>{EMPTY}</TD>
                  <TD numeric>{formatNumber(summary.llmCalls.current)}</TD>
                  <TD numeric>{formatNumber(summary.llmCalls.previous)}</TD>
                  <TD numeric>
                    <Change
                      current={summary.llmCalls.current}
                      previous={summary.llmCalls.previous}
                    />
                  </TD>
                  <TD numeric>{formatUsd(current.totalUsd)}</TD>
                </TR>
              </TBody>
            </Table>
          </Card>

          <Card className="flex flex-col gap-4">
            <div>
              <CardTitle>Top consumers · {summary.currentMonth}</CardTitle>
              <p className="mt-1 text-body-md text-on-surface-variant">
                Ranked by calls that reached a model. The meter tracks only the
                counters the free-tier ceiling governs ({formatNumber(aiCeiling)}
                /month); premium users bypass it entirely.
              </p>
            </div>

            {consumers.length === 0 ? (
              <p className="text-body-md text-on-surface-variant">
                No AI calls yet this month.
              </p>
            ) : (
              <Table>
                <THead>
                  <TH>User</TH>
                  <TH className="min-w-40">Against ceiling</TH>
                  <TH numeric>Premium calls</TH>
                  <TH numeric>Total calls</TH>
                  <TH numeric>Est. cost</TH>
                </THead>
                <TBody>
                  {consumers.map((row) => {
                    // premiumCalls > 0 is evidence the server actually bypassed
                    // the ceiling for them, which beats reading premiumStatus:
                    // a lapsed subscription still carries the old status.
                    const bypassed = row.premiumCalls > 0;
                    return (
                      <TR key={row.uid}>
                        <TD>
                          <Link
                            href={`/users/${row.uid}`}
                            className="text-primary hover:underline"
                          >
                            {row.email ?? row.uid}
                          </Link>
                          {row.premiumStatus === 'premium' ? (
                            <span className="ml-2 align-middle">
                              <Badge tone="positive">premium</Badge>
                            </span>
                          ) : null}
                        </TD>
                        <TD>
                          <Meter
                            value={row.quotaCounted}
                            max={bypassed ? null : aiCeiling}
                          />
                        </TD>
                        <TD numeric>{formatNumber(row.premiumCalls)}</TD>
                        <TD numeric>{formatNumber(row.llmCalls)}</TD>
                        <TD numeric>
                          {formatUsd(estimateCost(row.counts, setting).totalUsd)}
                        </TD>
                      </TR>
                    );
                  })}
                </TBody>
              </Table>
            )}
          </Card>
        </>
      ) : (
        <EmptyState
          title="No AI usage recorded"
          body="Nothing has written to users/{uid}/aiUsage for either month. Cloud Functions are the only writer, so this is also what a deployment with the AI functions undeployed looks like."
        />
      )}

      <KnownGaps
        rejected={summary.rejected.current}
        premiumCalls={summary.premiumCalls.current}
        currentMonth={summary.currentMonth}
        previousMonth={summary.previousMonth}
      />

      <Assumptions setting={setting} />
    </div>
  );
}

/* ------------------------------------------------------------------ rows -- */

/**
 * Per-counter footnotes. Three of the twelve rows are not what a reader assumes
 * from the label alone, and a wrong assumption here changes what an operator
 * concludes about spend.
 */
const FEATURE_NOTES: Readonly<Record<string, string>> = {
  premiumCalls:
    'Premium bypass records no feature — costed at the mean across the nine',
  fx: 'Exchange-rate lookups, not a model call',
  rejected: 'Refused at the ceiling — no provider was reached',
};

function FeatureRow({
  line,
  previousCalls,
}: {
  line: FeatureEstimate;
  previousCalls: number;
}) {
  const note = FEATURE_NOTES[line.feature];

  return (
    <TR>
      <TD>
        <span>{line.label}</span>
        {note ? (
          <span className="block text-label-sm text-on-surface-variant">
            {note}
          </span>
        ) : null}
      </TD>
      <TD className="whitespace-nowrap text-on-surface-variant">
        {line.model ?? EMPTY}
      </TD>
      <TD numeric>{formatNumber(line.calls)}</TD>
      <TD numeric>{formatNumber(previousCalls)}</TD>
      <TD numeric>
        <Change current={line.calls} previous={previousCalls} />
      </TD>
      {/* An em-dash, not $0.00: these rows have no cost to state, rather than
          a cost that happens to be zero. */}
      <TD numeric>
        {line.kind === 'llm' || line.kind === 'blended'
          ? formatUsd(line.usd)
          : EMPTY}
      </TD>
    </TR>
  );
}

/** Month-over-month change. Tone-free — more AI usage is neither good nor bad. */
function Change({ current, previous }: { current: number; previous: number }) {
  const change = percentChange(current, previous);

  if (change === null) {
    return (
      <span className="text-on-surface-variant">
        {current > 0 ? 'new' : EMPTY}
      </span>
    );
  }

  const pct = Math.round(change * 100);
  return (
    <span className="text-on-surface-variant">
      {pct > 0 ? '+' : ''}
      {pct}%
    </span>
  );
}

/* ----------------------------------------------------------------- cards -- */

function ProviderCard({
  setting,
  rawProvider,
  unrecognized,
  conditional,
}: {
  setting: ProviderSetting;
  rawProvider: string;
  unrecognized: boolean;
  conditional: boolean;
}) {
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-4">
        <CardTitle>Active provider</CardTitle>
        <Badge tone={setting ? 'positive' : 'neutral'}>
          {setting ?? 'gemini (per-feature default)'}
        </Badge>
        {unrecognized ? (
          <Badge tone="critical">
            ai_provider = &ldquo;{rawProvider}&rdquo; — ignored
          </Badge>
        ) : null}
        {conditional ? (
          <Badge tone="warning">has conditional values</Badge>
        ) : null}
      </div>

      <p className="max-w-prose text-body-md text-on-surface-variant">
        {setting
          ? `Remote Config ai_provider is set to "${setting}", so every callable uses that provider — including receipt scanning, which otherwise defaults to OpenAI vision.`
          : 'Remote Config ai_provider is unset, so each callable keeps its own default: gpt-4o for receipt scanning, gemini-2.5-flash-lite for everything else.'}
      </p>

      <ul className="flex flex-col gap-2 text-body-md text-on-surface-variant">
        <li className="flex gap-4">
          <span aria-hidden className="text-primary">
            —
          </span>
          <span>
            Cloud Functions read a key&rsquo;s <strong>defaultValue only</strong>
            . Conditions and percentage rollouts have no effect server-side, so a
            conditional <code>ai_provider</code> silently does nothing.
          </span>
        </li>
        <li className="flex gap-4">
          <span aria-hidden className="text-primary">
            —
          </span>
          <span>
            Each warm Function instance caches the template{' '}
            <strong>for its lifetime, with no TTL</strong>. A change here reaches
            running instances only as they recycle, so expect both providers to
            be in use for a while after an edit.
          </span>
        </li>
      </ul>
    </Card>
  );
}

function KnownGaps({
  rejected,
  premiumCalls,
  currentMonth,
  previousMonth,
}: {
  rejected: number;
  premiumCalls: number;
  currentMonth: string;
  previousMonth: string;
}) {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>What these numbers cannot tell you</CardTitle>
      <ul className="flex flex-col gap-4 text-body-md text-on-surface-variant">
        <li>
          <strong className="text-on-surface">
            Rejections are not being recorded.
          </strong>{' '}
          The schema has a <code>rejected</code> counter, but no shipped Cloud
          Function writes it — <code>checkAndIncrementQuota</code> throws{' '}
          <code>resource-exhausted</code> and returns without touching the
          document. The tile above reads {formatNumber(rejected)} because the
          field is absent, not because nobody was blocked. Incrementing it before
          the throw in <code>apps/functions/src/quota/check_quota.ts</code> is
          the fix.
        </li>
        <li>
          <strong className="text-on-surface">
            Premium calls carry no feature.
          </strong>{' '}
          On the bypass path only <code>premiumCalls</code> is incremented, so
          the {formatNumber(premiumCalls)} premium calls this month are costed at
          the mean across the nine features. A deployment whose premium users
          lean on receipt scanning — roughly 20x the cost of the rest — will be
          under-estimated here.
        </li>
        <li>
          <strong className="text-on-surface">History stops at two months.</strong>{' '}
          <code>resetMonthlyAIQuotas</code> deletes usage documents older than
          the previous month, so {previousMonth} and {currentMonth} is all that
          exists. Trend charts need the Phase 3 <code>adminStatsMonthly</code>{' '}
          rollup, which is not built yet.
        </li>
        <li>
          <strong className="text-on-surface">Months are UTC.</strong> The
          document id is a UTC <code>YYYY-MM</code>, while the mobile client
          counts its own free-tier ceilings against the device&rsquo;s local
          month. Near a month boundary the two disagree.
        </li>
      </ul>
    </Card>
  );
}
