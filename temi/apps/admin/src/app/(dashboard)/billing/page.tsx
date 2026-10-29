import Link from 'next/link';
import type { ReactNode } from 'react';

import { Badge, Card, CardTitle, EmptyState, Stat } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import {
  daysUntil,
  isAnonymousAppUserId,
  loadBilling,
  type EventSummary,
  type RevenueCatEventRow,
} from '@/lib/data/billing';
import {
  entitlementDrift,
  isPremiumNow,
  type UserListRow,
} from '@/lib/data/user-mapping';
import {
  EMPTY,
  formatDateTime,
  formatNumber,
  formatRelative,
} from '@/lib/format';

import { RefreshForm } from './refresh-form';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** One fetched page of events. Every per-type figure describes this window. */
const EVENT_LIMIT = 100;
const EXPIRING_DAYS = 30;
const EXPIRING_LIMIT = 100;

/**
 * Billing — whether RevenueCat is actually reaching this deployment.
 *
 * Everything here reads two collections: `revenueCatEvents`, appended by the
 * webhook, and the entitlement fields on `users/{uid}`. Neither is RevenueCat
 * itself, which is the point the page keeps making — see the trust-model card at
 * the bottom, and the refresh control, which is the only thing here that asks
 * RevenueCat directly.
 */
export default async function BillingPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const prefillUid = firstParam(params.uid)?.trim() ?? '';

  const { events, summary, expiring, revenueCatConfigured } = await loadBilling({
    eventLimit: EVENT_LIMIT,
    expiringDays: EXPIRING_DAYS,
    expiringLimit: EXPIRING_LIMIT,
  });

  // A full page means there are probably more. Saying "100" without saying
  // "at least" would report a cap as a count.
  const expiringTruncated = expiring.rows.length === expiring.limit;

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">Billing</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          What RevenueCat has told this deployment, and what the Firestore mirror
          says as a result. Read from{' '}
          <Code>revenueCatEvents</Code> and the entitlement fields on{' '}
          <Code>users/&#123;uid&#125;</Code> — not from RevenueCat, except where
          the refresh below says otherwise.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Webhook events"
          value={formatNumber(summary.total)}
          hint={
            summary.total === 0
              ? 'none recorded'
              : summary.latestMs == null
                ? 'none carry a timestamp'
                : `newest ${formatRelative(summary.latestMs, events.nowMs)}`
          }
        />
        <Stat
          label="Event types"
          value={formatNumber(summary.distinctTypes)}
          hint={`within the last ${EVENT_LIMIT} events`}
        />
        <Stat
          label="No entitlement written"
          value={formatNumber(summary.unhandled)}
          hint="logged, but nothing changed — see below"
        />
        <Stat
          label={`Expiring in ${EXPIRING_DAYS} days`}
          value={
            expiringTruncated
              ? `${formatNumber(expiring.rows.length)}+`
              : formatNumber(expiring.rows.length)
          }
          hint="by the mirrored expiry, not RevenueCat"
        />
      </div>

      {events.error ? (
        <ReadError
          title="Could not read the webhook event log"
          detail={events.error}
        />
      ) : null}
      {expiring.error ? (
        <ReadError
          title="Could not read expiring subscriptions"
          detail={expiring.error}
        />
      ) : null}

      <WebhookHealth summary={summary} nowMs={events.nowMs} error={events.error} />

      {summary.total > 0 ? (
        <Card className="flex flex-col gap-4">
          <div>
            <CardTitle>Recent events</CardTitle>
            <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
              Newest first, most recent {EVENT_LIMIT}. This collection grows one
              document per webhook forever unless a Firestore TTL policy is set
              by hand on <Code>receivedAt</Code> — see{' '}
              <Code>docs/REVENUECAT_SETUP.md</Code>.
            </p>
          </div>

          <Table>
            <THead>
              <TH>When</TH>
              <TH>Type</TH>
              <TH>User</TH>
              <TH>Product</TH>
              <TH>Expiry in event</TH>
              <TH>Entitlement</TH>
            </THead>
            <TBody>
              {events.rows.map((row) => (
                <EventRow key={row.id} row={row} nowMs={events.nowMs} />
              ))}
            </TBody>
          </Table>
        </Card>
      ) : null}

      <Card className="flex flex-col gap-4">
        <div>
          <CardTitle>Expiring within {EXPIRING_DAYS} days</CardTitle>
          <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
            Users whose mirrored <Code>premiumExpiry</Code> falls in the next{' '}
            {EXPIRING_DAYS} days. An auto-renewing subscription belongs here —
            RevenueCat sends the <Code>RENEWAL</Code> event that pushes the date
            out on or shortly after the renewal. A row that is still here once
            the date has passed is the one worth chasing.
            {expiringTruncated
              ? ` Capped at ${EXPIRING_LIMIT} rows, soonest first — there are likely more.`
              : ''}
          </p>
        </div>

        {expiring.rows.length === 0 ? (
          <p className="text-body-md text-on-surface-variant">
            {expiring.error
              ? 'The query failed, so this list is not an answer either way.'
              : `No user carries an expiry inside the next ${EXPIRING_DAYS} days.`}
          </p>
        ) : (
          <Table>
            <THead>
              <TH>User</TH>
              <TH>Mirror says</TH>
              <TH>Expires</TH>
              <TH numeric>Days left</TH>
              <TH>
                <span className="sr-only">Actions</span>
              </TH>
            </THead>
            <TBody>
              {expiring.rows.map((row) => (
                <ExpiringRow key={row.uid} row={row} nowMs={expiring.nowMs} />
              ))}
            </TBody>
          </Table>
        )}
      </Card>

      {revenueCatConfigured ? (
        // `key` resets the controlled input when an operator clicks through from
        // a different row, which an uncontrolled default value would not do.
        <RefreshForm key={prefillUid} defaultUid={prefillUid} />
      ) : (
        <Card className="flex flex-col gap-2">
          <CardTitle>Entitlement refresh is unavailable</CardTitle>
          <p className="max-w-prose text-body-md text-on-surface-variant">
            <Code>REVENUECAT_API_KEY</Code> is not set for the admin panel, so
            RevenueCat cannot be queried from here. The control is hidden rather
            than shown-and-broken. Set the secret and grant the backend access to
            it (<Code>apps/admin/apphosting.yaml</Code> carries the commented
            binding, and <Code>.env.example</Code> the local variable), then
            reload. Note this is the same secret the Cloud Functions use, but a
            separate runtime — having it there does not give it to the panel.
          </p>
        </Card>
      )}

      <TrustModel />
    </div>
  );
}

/* ------------------------------------------------------------------ cards -- */

/**
 * Webhook health.
 *
 * An empty log is deliberately NOT presented as a fault. `revenueCatEvents` is
 * written only by `handleRevenueCatWebhook`, so zero events is exactly what a
 * deployment that has not pointed RevenueCat at the endpoint looks like — and
 * that is the common case for a fresh install, not a broken one.
 */
function WebhookHealth({
  summary,
  nowMs,
  error,
}: {
  summary: EventSummary;
  nowMs: number;
  error: string | null;
}) {
  if (summary.total === 0) {
    return (
      <EmptyState
        title="No webhook events recorded"
        body={
          error
            ? 'The event log could not be read, so this is not evidence about the webhook either way — see the error above.'
            : 'Nothing has written to revenueCatEvents. The handleRevenueCatWebhook Function is its only writer, so the most likely explanation is simply that RevenueCat has not been pointed at this deployment yet — set the webhook URL and REVENUECAT_WEBHOOK_SECRET as described in docs/REVENUECAT_SETUP.md. A live deployment that has genuinely had no purchases, renewals, or expiries looks identical from here.'
        }
      />
    );
  }

  return (
    <Card className="flex flex-col gap-4">
      <div>
        <CardTitle>Webhook health</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Last seen per event type, <strong>within the last {summary.total}</strong>{' '}
          events — not across all time. A type absent from this list may have
          fired long ago and been pushed out of the window; the only way to widen
          it is to read further back in Firestore. Counting per type across all
          history would need one composite index per type, which this product
          does not ship.
        </p>
      </div>

      <Table>
        <THead>
          <TH>Event type</TH>
          <TH>Last seen</TH>
          <TH numeric>In window</TH>
          <TH numeric>Entitlement written</TH>
        </THead>
        <TBody>
          {summary.byType.map((type) => (
            <TR key={type.type}>
              <TD>
                <Code>{type.type}</Code>
              </TD>
              <TD className="whitespace-nowrap">
                {type.lastSeenMs == null ? (
                  <span className="text-on-surface-variant">
                    no timestamp recorded
                  </span>
                ) : (
                  <>
                    <span className="block">{formatDateTime(type.lastSeenMs)}</span>
                    <span className="block text-label-sm text-on-surface-variant">
                      {formatRelative(type.lastSeenMs, nowMs)}
                    </span>
                  </>
                )}
              </TD>
              <TD numeric>{formatNumber(type.count)}</TD>
              <TD numeric>
                {formatNumber(type.handled)}
                {type.unhandled > 0 ? (
                  <span className="block text-label-sm text-on-surface-variant">
                    {formatNumber(type.unhandled)} not applied
                  </span>
                ) : null}
              </TD>
            </TR>
          ))}
        </TBody>
      </Table>

      <p className="max-w-prose text-label-sm text-on-surface-variant">
        &ldquo;Not applied&rdquo; is usually correct rather than a failure: the
        webhook only grants on{' '}
        <Code>INITIAL_PURCHASE / RENEWAL / PRODUCT_CHANGE / UNCANCELLATION /
        NON_RENEWING_PURCHASE</Code>{' '}
        and revokes on{' '}
        <Code>EXPIRATION / CANCELLATION / BILLING_ISSUE</Code>. Everything else —{' '}
        <Code>TEST</Code>, <Code>TRANSFER</Code>, <Code>SUBSCRIBER_ALIAS</Code> —
        is logged and deliberately ignored. It also covers the case where the
        Firestore write threw, which is far rarer and shows up as a{' '}
        <Code>500</Code> in the Function logs.
      </p>
    </Card>
  );
}

function TrustModel() {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>What these numbers can and cannot tell you</CardTitle>
      <ul className="flex flex-col gap-4 text-body-md text-on-surface-variant">
        <li>
          <strong className="text-on-surface">
            RevenueCat is the source of truth; Firestore is a mirror.
          </strong>{' '}
          Every entitlement figure on this page except the refresh result comes
          from <Code>users/&#123;uid&#125;.premiumStatus</Code> and{' '}
          <Code>premiumExpiry</Code>. Those fields are a cache of a RevenueCat
          decision, not the decision itself.
        </li>
        <li>
          <strong className="text-on-surface">
            The mirror has two writers, and one of them is the phone.
          </strong>{' '}
          <Code>handleRevenueCatWebhook</Code> writes it server-side and is
          authoritative. The mobile client ALSO writes it immediately after a
          purchase or restore, as a fast path so the UI does not wait on the
          webhook. That second writer means these fields are{' '}
          <strong className="text-on-surface">client-forgeable</strong> — a
          modified app can set itself premium in Firestore, and nothing here would
          look unusual. Treat a premium status with no matching event above as
          unproven, and use the refresh to settle it.
        </li>
        <li>
          <strong className="text-on-surface">
            A premium status with no expiry grants nothing.
          </strong>{' '}
          <Code>evaluateQuota</Code> requires a non-null{' '}
          <Code>premiumExpiry</Code> in the future, so{' '}
          <Code>&#123; premiumStatus: &lsquo;premium&rsquo;, premiumExpiry: null
          &#125;</Code>{' '}
          is read as free by the server while the row looks premium here. That is
          why lifetime purchases are stored ~100 years out rather than as null,
          in the webhook and in the refresh below alike.
        </li>
        <li>
          <strong className="text-on-surface">
            Every per-type figure describes one page of events.
          </strong>{' '}
          Last-seen is derived in code from the most recent {EVENT_LIMIT} events
          rather than from a query per type, which would need a composite index
          per type. &ldquo;Not seen&rdquo; therefore means &ldquo;not in this
          window&rdquo;, never &ldquo;never happened&rdquo;.
        </li>
        <li>
          <strong className="text-on-surface">
            Refunds and chargebacks are not shown as such.
          </strong>{' '}
          RevenueCat sends them; the webhook maps only the grant and revoke sets
          above, so a refund reaches this page as whatever event type accompanied
          it and appears in the table by name.
        </li>
      </ul>
    </Card>
  );
}

function ReadError({ title, detail }: { title: string; detail: string }) {
  return (
    <Card className="flex flex-col gap-2">
      <CardTitle>{title}</CardTitle>
      <p role="alert" className="max-w-prose text-body-md text-error">
        {detail}
      </p>
      <p className="max-w-prose text-body-md text-on-surface-variant">
        A collection that has never been written to reads as zero documents
        rather than an error, so this is a credentials, IAM, or connectivity
        problem — not an empty log.
      </p>
    </Card>
  );
}

/* ------------------------------------------------------------------- rows -- */

function EventRow({ row, nowMs }: { row: RevenueCatEventRow; nowMs: number }) {
  return (
    <TR>
      <TD className="whitespace-nowrap">
        {row.receivedAtMs == null ? (
          EMPTY
        ) : (
          <>
            <span className="block">{formatDateTime(row.receivedAtMs)}</span>
            <span className="block text-label-sm text-on-surface-variant">
              {formatRelative(row.receivedAtMs, nowMs)}
            </span>
          </>
        )}
      </TD>
      <TD>
        <Code>{row.type}</Code>
      </TD>
      <TD>
        <UserCell appUserId={row.appUserId} />
      </TD>
      <TD className="text-on-surface-variant">{row.productId ?? EMPTY}</TD>
      <TD className="whitespace-nowrap">
        {row.expiresAtMs == null ? EMPTY : formatDateTime(row.expiresAtMs)}
      </TD>
      <TD>
        {row.handled ? (
          <Badge tone="positive">written</Badge>
        ) : (
          <Badge tone="neutral">not applied</Badge>
        )}
      </TD>
    </TR>
  );
}

/**
 * RevenueCat's `app_user_id`. Normally the Firebase uid, so it links straight to
 * the user page — but an anonymous id can never match a `users/{uid}` document,
 * so it renders as plain text rather than a link to a guaranteed 404.
 */
function UserCell({ appUserId }: { appUserId: string | null }) {
  if (appUserId == null) return <span>{EMPTY}</span>;

  if (isAnonymousAppUserId(appUserId)) {
    return (
      <>
        <span className="block break-all">{appUserId}</span>
        <span className="block text-label-sm text-on-surface-variant">
          anonymous — the app purchased before calling Purchases.logIn(uid)
        </span>
      </>
    );
  }

  return (
    <Link
      href={`/users/${appUserId}`}
      className="break-all text-primary hover:underline"
    >
      {appUserId}
    </Link>
  );
}

function ExpiringRow({ row, nowMs }: { row: UserListRow; nowMs: number }) {
  const left = daysUntil(row.premiumExpiryMs, nowMs);

  return (
    <TR>
      <TD>
        <Link
          href={`/users/${row.uid}`}
          className="break-all text-primary hover:underline"
        >
          {row.email ?? row.uid}
        </Link>
      </TD>
      <TD>
        {/* Every row here carries a FUTURE expiry by construction, so the only
            interesting distinction is whether the status agrees with it. */}
        {entitlementDrift(row, nowMs) === 'free-but-has-future-expiry' ? (
          <Badge tone="warning">Mirror drift — says free</Badge>
        ) : isPremiumNow(row, nowMs) ? (
          <Badge tone="positive">Premium</Badge>
        ) : (
          <Badge tone="neutral">{row.premiumStatus ?? 'status not set'}</Badge>
        )}
      </TD>
      <TD className="whitespace-nowrap">
        {formatDateTime(row.premiumExpiryMs)}
      </TD>
      <TD numeric>{left == null ? EMPTY : formatNumber(left)}</TD>
      <TD>
        <Link
          href={`/billing?uid=${encodeURIComponent(row.uid)}`}
          className="whitespace-nowrap text-label-sm text-primary hover:underline"
        >
          Check RevenueCat
        </Link>
      </TD>
    </TR>
  );
}

/* ---------------------------------------------------------------- helpers -- */

/**
 * Inline literal — a field name, a document path, an event type.
 *
 * `font-sans` is not redundant: Tailwind's preflight points `<code>` at the mono
 * stack, and Sora is the only family this design system allows.
 *
 * Deliberately local. The identical helper exists at `users/code.tsx`; both
 * should be lifted into `components/ui` once one owner holds both directories —
 * a cross-module import between two route folders is the worse coupling of the
 * two while they are edited independently.
 */
function Code({ children }: { children: ReactNode }) {
  return (
    <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
      {children}
    </code>
  );
}

/** A repeated query key arrives as an array; take the first occurrence. */
function firstParam(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}
