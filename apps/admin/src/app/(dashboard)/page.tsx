import Link from 'next/link';

import { Card, CardTitle, Stat } from '@/components/ui';
import { requireAdmin } from '@/lib/auth/require-admin';
import { estimateCost, type ProviderSetting } from '@/lib/cost/estimate';
import { getUsageTotals } from '@/lib/data/ai-usage';
import {
  countPremiumUsers,
  countUsers,
  countUsersInLastDays,
} from '@/lib/data/users';
import { formatNumber, formatUsd } from '@/lib/format';
import { rcString, readRemoteConfig } from '@/lib/remote-config/read';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * Dashboard.
 *
 * The user counts use Firestore `count()` aggregations, which are billed at a
 * fraction of a document read and need no composite index — so those tiles stay
 * cheap regardless of how many users the deployment has. The AI tiles cost more
 * (a full scan of the aiUsage collection group, see lib/data/ai-usage.ts); they
 * become a two-document read once the Phase 3 rollup exists.
 */
export default async function DashboardPage() {
  await requireAdmin();

  const [total, premium, new7d, new30d, active30d, usage, rc] =
    await Promise.all([
      countUsers(),
      countPremiumUsers(),
      countUsersInLastDays('createdAt', 7),
      countUsersInLastDays('createdAt', 30),
      countUsersInLastDays('lastSyncAt', 30),
      getUsageTotals(),
      readRemoteConfig(),
    ]);

  const conversion = total > 0 ? ((premium / total) * 100).toFixed(1) : '0.0';

  // Mirrors selectProvider(): anything other than an exact 'openai' | 'gemini'
  // leaves each callable on its own per-feature default.
  const rawProvider = rcString(rc, 'ai_provider', '');
  const setting: ProviderSetting =
    rawProvider === 'openai' || rawProvider === 'gemini' ? rawProvider : null;
  const spend = estimateCost(usage.totals.current, setting).totalUsd;

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">Dashboard</h1>
        <p className="mt-1 text-body-md text-on-surface-variant">
          Live counts for this deployment.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Stat label="Total users" value={formatNumber(total)} />
        <Stat
          label="Premium"
          value={formatNumber(premium)}
          hint={`${conversion}% conversion`}
        />
        <Stat
          label="New · 30 days"
          value={formatNumber(new30d)}
          hint={`${formatNumber(new7d)} in the last 7`}
        />
        <Stat
          label="Active · 30 days"
          value={formatNumber(active30d)}
          hint="by last sync"
        />
        <Stat
          label={`AI calls · ${usage.currentMonth}`}
          value={formatNumber(usage.llmCalls.current)}
          hint={`${formatNumber(usage.activeUsers.current)} users · ${formatNumber(usage.llmCalls.previous)} last month`}
        />
        <Stat
          label="Estimated AI spend"
          value={formatUsd(spend)}
          hint="this month · estimate, not a bill"
        />
      </div>

      <Card className="flex flex-col gap-4">
        <CardTitle>What is and is not here</CardTitle>
        <p className="max-w-prose text-body-md text-on-surface-variant">
          Every tile above is read live on each request — there is no
          pre-aggregation behind them yet.
        </p>
        <ul className="flex flex-col gap-2 text-body-md text-on-surface-variant">
          <li className="flex gap-4">
            <span aria-hidden className="text-primary">
              —
            </span>
            <span>
              <strong className="text-on-surface">No trend charts.</strong> They
              need a history to plot, and none is retained:{' '}
              <code>resetMonthlyAIQuotas</code> keeps only the current and
              previous month of AI usage, and nothing snapshots the user counts
              at all. The Phase 3 daily and monthly rollups are what create that
              history.
            </span>
          </li>
          <li className="flex gap-4">
            <span aria-hidden className="text-primary">
              —
            </span>
            <span>
              <strong className="text-on-surface">
                AI spend is an estimate.
              </strong>{' '}
              The counters record calls, not tokens.{' '}
              <Link href="/ai-usage" className="text-primary hover:underline">
                AI usage
              </Link>{' '}
              shows the full derivation and the per-feature breakdown.
            </span>
          </li>
          <li className="flex gap-4">
            <span aria-hidden className="text-primary">
              —
            </span>
            <span>
              <strong className="text-on-surface">
                &ldquo;Active&rdquo; means synced.
              </strong>{' '}
              It counts users whose <code>lastSyncAt</code> moved in the last 30
              days. An offline-first user who never regains network is invisible
              to it, by design — the app works fine without ever syncing.
            </span>
          </li>
        </ul>
      </Card>
    </div>
  );
}
