import Link from 'next/link';
import { notFound } from 'next/navigation';

import { Badge, Card, CardTitle } from '@/components/ui';
import { Meter, Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import {
  FX_MONTHLY_CEILING,
  entitlementDrift,
  isPremiumNow,
  quotaCountedTotal,
} from '@/lib/data/user-mapping';
import { loadUserDetail } from '@/lib/data/users';
import {
  EMPTY,
  formatDateTime,
  formatNumber,
  formatRelative,
} from '@/lib/format';
import { freeTierLimits, readRemoteConfig } from '@/lib/remote-config/read';
import {
  QUOTA_COUNTED_FIELDS,
  type AiUsageDocument,
} from '@/lib/types/user-document';

import { Code } from '../code';
import { EntitlementBadge } from '../entitlement-badge';
import { Field } from '../field';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * Support view for a single user.
 *
 * Ordered by the question it answers, not by where the data lives: who is this,
 * what are they entitled to, and — the reason most tickets get opened — which
 * ceiling is blocking them.
 */
export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ uid: string }>;
}) {
  const { uid } = await params;

  const [detail, rc] = await Promise.all([
    loadUserDetail(uid),
    readRemoteConfig(),
  ]);

  if (!detail) notFound();

  const {
    user,
    footprint,
    transactionsThisMonth,
    currentMonthKey,
    previousMonthKey,
    currentUsage,
    previousUsage,
    nowMs,
  } = detail;

  const limits = freeTierLimits(rc);
  const premium = isPremiumNow(user, nowMs);
  const drift = entitlementDrift(user, nowMs);
  // The specific trap worth calling out by name: the document says premium but
  // the server's quota check reads a null expiry as free.
  const nullExpiryTrap =
    user.premiumStatus === 'premium' && user.premiumExpiryMs == null;

  const aiUsed = quotaCountedTotal(currentUsage);

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-col gap-2">
        <Link
          href="/users"
          className="text-label-sm uppercase text-primary hover:underline"
        >
          ← All users
        </Link>
        <div className="flex flex-wrap items-center gap-4">
          <h1 className="text-headline-lg text-on-surface">
            {user.displayName ?? user.email ?? user.uid}
          </h1>
          <EntitlementBadge row={user} nowMs={nowMs} />
        </div>
      </div>

      <Card>
        <CardTitle>Profile</CardTitle>
        <dl className="mt-6 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <Field label="Email">{user.email ?? EMPTY}</Field>
          <Field label="Display name">{user.displayName ?? EMPTY}</Field>
          <Field label="UID" className="sm:col-span-2 lg:col-span-1">
            {/* select-all makes one click grab the whole id — this is the value
                an operator pastes into logs and the Firebase console. */}
            <span className="select-all break-all">{user.uid}</span>
          </Field>
          <Field label="Default currency">
            {user.defaultCurrency ?? EMPTY}
          </Field>
          <Field label="Monthly income">
            {user.monthlyIncome == null
              ? EMPTY
              : `${formatNumber(user.monthlyIncome)} ${user.defaultCurrency ?? ''}`.trim()}
          </Field>
          <Field label="Financial health score">
            {user.financialHealthScore == null
              ? EMPTY
              : formatNumber(user.financialHealthScore)}
          </Field>
          <Field label="Created">{formatDateTime(user.createdAtMs)}</Field>
          <Field label="Last sync">
            {formatDateTime(user.lastSyncAtMs)}
            {user.lastSyncAtMs != null ? (
              <span className="text-on-surface-variant">
                {' · '}
                {formatRelative(user.lastSyncAtMs, nowMs)}
              </span>
            ) : null}
          </Field>
          <Field label="Setup completed">
            {user.setupCompletedAtMs == null ? (
              <Badge tone="warning">Onboarding incomplete</Badge>
            ) : (
              formatDateTime(user.setupCompletedAtMs)
            )}
          </Field>
        </dl>
      </Card>

      <Card>
        <CardTitle>Entitlement</CardTitle>
        <dl className="mt-6 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {/* Prose labels, not the raw field names — the <dt> is uppercased for
              display, and "PREMIUMSTATUS" reads as a typo. */}
          <Field label="Premium status">{user.premiumStatus ?? EMPTY}</Field>
          <Field label="Premium expiry">
            {formatDateTime(user.premiumExpiryMs)}
          </Field>
          <Field label="Effective now">
            {/* What the SERVER concludes from the two fields above, which is
                not always what premiumStatus alone suggests. */}
            <EntitlementBadge row={user} nowMs={nowMs} />
          </Field>
          <Field label="Entitlement last written">
            {formatDateTime(user.updatedAtMs)}
          </Field>
        </dl>

        {nullExpiryTrap ? (
          <p className="mt-6 rounded bg-error-container p-4 text-body-md text-on-error-container">
            <strong>This user is treated as FREE by the server.</strong> A{' '}
            <Code>premiumStatus</Code> of <Code>premium</Code> with a null{' '}
            <Code>premiumExpiry</Code> fails the quota check in{' '}
            <Code>apps/functions/src/quota/quota_logic.ts</Code>, which requires
            a non-null expiry in the future. That is why the RevenueCat webhook
            writes a +100-year timestamp for lifetime purchases — granting
            premium by setting the status alone silently grants nothing.
          </p>
        ) : drift ? (
          <p className="mt-6 rounded bg-tertiary-container p-4 text-body-md text-on-tertiary-container">
            {drift === 'expired-but-marked-premium'
              ? 'The document still says premium but the expiry has passed. RevenueCat should have sent an EXPIRATION webhook; if the user genuinely still has a subscription, the webhook was missed and the mirror is stale.'
              : 'The document says free while an unexpired expiry sits on it. Either a renewal webhook landed out of order, or a cancellation wrote the status without clearing the expiry.'}
          </p>
        ) : null}

        <p className="mt-4 text-label-sm text-on-surface-variant">
          RevenueCat is the source of truth. Two writers update these fields:
          the <Code>handleRevenueCatWebhook</Code> Function (authoritative) and
          the mobile client immediately after a purchase, as a fast path.
        </p>
      </Card>

      <Card>
        <CardTitle>Free-tier standing</CardTitle>
        <p className="mt-2 max-w-prose text-body-md text-on-surface-variant">
          Why the app shows this user an upsell. The wallet and transaction
          ceilings are enforced on the CLIENT against its local Drift rows — the
          counts below come from the synced Firestore mirror, so an offline or
          not-yet-synced device can be over a ceiling the panel still reads as
          under it.
        </p>

        {premium ? (
          <div className="mt-6 flex flex-col gap-4">
            <Badge tone="positive">Ceilings bypassed — premium</Badge>
            <dl className="grid gap-6 sm:grid-cols-3">
              <Field label="Wallets">
                {formatNumber(footprint.wallets ?? 0)}
              </Field>
              <Field label={`Transactions · ${currentMonthKey}`}>
                {formatNumber(transactionsThisMonth)}
              </Field>
              <Field label="Applied ceilings">None</Field>
            </dl>
          </div>
        ) : (
          <div className="mt-6 grid gap-6 sm:grid-cols-2">
            <Meter
              value={footprint.wallets ?? 0}
              max={limits.wallets}
              label="Wallets"
            />
            <Meter
              value={transactionsThisMonth}
              max={limits.transactionsMonthly}
              label={`Transactions · ${currentMonthKey}`}
            />
          </div>
        )}

        <p className="mt-6 text-label-sm text-on-surface-variant">
          Ceilings read from Remote Config:{' '}
          <Code>free_tier_wallets_max</Code> = {limits.wallets},{' '}
          <Code>free_tier_transactions_monthly</Code> ={' '}
          {limits.transactionsMonthly}. The transaction window starts at the
          first of the month in UTC, matching the AI counter keys; the client
          counts against the device&apos;s local month.
        </p>
      </Card>

      <Card>
        <CardTitle>AI usage</CardTitle>

        <div className="mt-6 max-w-prose">
          {premium ? (
            <div className="flex flex-col gap-2">
              <Badge tone="positive">Quota bypassed — premium</Badge>
              <p className="text-body-md text-on-surface-variant">
                Premium calls skip the ceiling entirely and increment{' '}
                <Code>premiumCalls</Code> for analytics instead.
              </p>
            </div>
          ) : (
            <Meter
              value={aiUsed}
              max={limits.aiMonthly}
              label={`Quota-counted AI calls · ${currentMonthKey}`}
            />
          )}
        </div>

        <div className="mt-6">
          <Table>
            <THead>
              <TH>Counter</TH>
              <TH numeric>{currentMonthKey}</TH>
              <TH numeric>{previousMonthKey}</TH>
            </THead>
            <TBody>
              {QUOTA_COUNTED_FIELDS.map((field) => (
                <TR key={field}>
                  <TD>{QUOTA_LABELS[field]}</TD>
                  <TD numeric>{counter(currentUsage, field)}</TD>
                  <TD numeric>{counter(previousUsage, field)}</TD>
                </TR>
              ))}
              <TR>
                <TD className="text-label-md uppercase">
                  Counted against quota
                </TD>
                <TD numeric className="text-label-md">
                  {formatNumber(aiUsed)}
                </TD>
                <TD numeric className="text-label-md">
                  {formatNumber(quotaCountedTotal(previousUsage))}
                </TD>
              </TR>
            </TBody>
          </Table>
        </div>

        <div className="mt-6 grid gap-6 sm:grid-cols-3">
          <Field label="Premium calls">
            {counter(currentUsage, 'premiumCalls')}
            <span className="block text-label-sm text-on-surface-variant">
              analytics only — no ceiling
            </span>
          </Field>
          <Field label="Rejected">
            {counter(currentUsage, 'rejected')}
            <span className="block text-label-sm text-on-surface-variant">
              calls refused for hitting the ceiling
            </span>
          </Field>
          <Field label="FX rate lookups">
            {counter(currentUsage, 'fx')}
            <span className="block text-label-sm text-on-surface-variant">
              own ceiling: {formatNumber(FX_MONTHLY_CEILING)}/month, hardcoded in
              getFxRate rather than Remote Config
            </span>
          </Field>
        </div>

        <p className="mt-6 text-label-sm text-on-surface-variant">
          Read from <Code>users/{uid}/aiUsage/{currentMonthKey}</Code>. The
          document id is the month, so a new month rotates to a fresh zero
          counter on its own —{' '}
          <Code>resetMonthlyAIQuotas</Code> only garbage-collects old ones.
          Ceiling: <Code>free_tier_ai_quota</Code> = {limits.aiMonthly}.
        </p>
      </Card>

      <Card>
        <CardTitle>Data footprint</CardTitle>
        <p className="mt-2 text-body-md text-on-surface-variant">
          Synced document counts under <Code>users/{uid}</Code>. Coach chat is
          Firestore-only and not part of the synced set, so it is not counted
          here.
        </p>
        <dl className="mt-6 grid gap-6 sm:grid-cols-3 lg:grid-cols-4">
          {Object.entries(footprint).map(([name, count]) => (
            <Field key={name} label={FOOTPRINT_LABELS[name] ?? name}>
              <span className="text-headline-md tabular-nums">
                {formatNumber(count)}
              </span>
            </Field>
          ))}
        </dl>
      </Card>
    </div>
  );
}

/**
 * Typed as a total map over QUOTA_COUNTED_FIELDS on purpose: adding a counter
 * to the shared type breaks this file until it gets a label, rather than
 * silently rendering a raw field name.
 */
const QUOTA_LABELS: Record<(typeof QUOTA_COUNTED_FIELDS)[number], string> = {
  categorize: 'Smart categorization',
  scan: 'Receipt scan',
  chat: 'Coach chat',
  forecast: 'Spending forecast',
  anomalies: 'Anomaly detection',
  healthScore: 'Health score',
  recap: 'Weekly recap',
  budgetPlan: 'Budget plan',
  savingsPlan: 'Savings plan',
};

const FOOTPRINT_LABELS: Record<string, string> = {
  wallets: 'Wallets',
  transactions: 'Transactions',
  budgets: 'Budgets',
  goals: 'Goals',
  debts: 'Debts',
  recurringRules: 'Recurring rules',
  categories: 'Categories',
};

/**
 * Absent counters render as 0, not an em-dash: the document is built up with
 * merge writes, so a missing field means the feature was never used — which is
 * a real zero, unlike a missing profile value.
 */
function counter(
  usage: AiUsageDocument | null,
  field: keyof AiUsageDocument,
): string {
  return formatNumber(usage?.[field] ?? 0);
}
