import type { ReactNode } from 'react';

import { Badge, Card, CardTitle, EmptyState, Stat } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { requireAdmin } from '@/lib/auth/require-admin';
import {
  ADMIN_DRIFT_EXPLANATION,
  ADMIN_DRIFT_LABEL,
  listAdmins,
  type AdminRow,
} from '@/lib/data/admins';
import { EMPTY, formatDateTime, formatRelative } from '@/lib/format';

import { GrantForm } from './grant-form';
import { RevokeButton } from './revoke-button';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * Access control — who can sign in to this panel at all.
 *
 * Access is the Firebase Auth custom claim `admin: true`, and nothing else.
 * `adminUsers` is a mirror this page lists from; it grants nothing, so every
 * row is checked against the live claim and any disagreement is shown rather
 * than smoothed over. See src/lib/data/admins.ts for the model.
 */
export default async function AccessPage() {
  const me = await requireAdmin();
  const { rows, nowMs, error } = await listAdmins();

  const canSignIn = rows.filter((row) => row.hasClaim && !row.disabled);
  const needsAttention = rows.filter((row) => row.drift !== null || row.disabled);

  // Only explain the drift kinds actually present — a permanent glossary of
  // states nobody is in is noise on the page that matters most.
  const driftKinds = [
    ...new Set(rows.flatMap((row) => (row.drift ? [row.drift] : []))),
  ].sort();

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">Access control</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Who can sign in to this panel. Access is a Firebase Auth custom claim,
          not a Firestore document — the list below is checked against the live
          claim on every load, so what you see here is what the sign-in gate
          will actually do.
        </p>
      </div>

      {error ? (
        <Card className="flex flex-col gap-2">
          <CardTitle>Could not list admins</CardTitle>
          <p role="alert" className="max-w-prose text-body-md text-error">
            {error}
          </p>
          <p className="max-w-prose text-body-md text-on-surface-variant">
            An empty mirror reads as zero rows rather than an error, so this is
            a credentials, IAM, or connectivity problem. Revoking is blocked
            while it persists: the only-admin check reads the same data, and a
            revoke it cannot verify could lock everyone out.
          </p>
        </Card>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Stat label="Listed" value={rows.length} hint="rows in the adminUsers mirror" />
        <Stat
          label="Can sign in"
          value={canSignIn.length}
          hint="hold the claim and are not disabled"
        />
        <Stat
          label="Needs attention"
          value={needsAttention.length}
          hint={needsAttention.length === 0 ? 'mirror and claims agree' : 'see the status column'}
        />
      </div>

      <HowAccessWorks />

      <GrantForm />

      {rows.length === 0 && !error ? (
        <EmptyState
          title="No admins are listed"
          body="You are signed in, so at least one claim exists — it simply has no mirror row, which is what happens when the claim was set by hand rather than by this page or the CLI. Granting yourself again from the form above writes the missing row."
        />
      ) : (
        // A full-bleed table reads better than one inset by the Card's padding,
        // and `cx` is a naive join — a `p-0` override would lose to Card's
        // `p-6` in the stylesheet, so the surface tokens are applied directly.
        <div className="overflow-hidden rounded-lg bg-surface-container-lowest shadow-level-1">
          <Table>
            <THead>
              <TH>Email</TH>
              <TH>User ID</TH>
              <TH>Status</TH>
              <TH>Granted</TH>
              <TH>Granted by</TH>
              <TH>
                <span className="sr-only">Actions</span>
              </TH>
            </THead>
            <TBody>
              {rows.map((row) => (
                <AdminTableRow
                  key={row.uid}
                  row={row}
                  nowMs={nowMs}
                  isSelf={row.uid === me.uid}
                />
              ))}
            </TBody>
          </Table>
        </div>
      )}

      {driftKinds.length > 0 ? (
        <Card className="flex flex-col gap-4">
          <CardTitle>Rows that need attention</CardTitle>
          {driftKinds.map((kind) => (
            <div key={kind} className="flex flex-col gap-1">
              <Badge tone="critical">{ADMIN_DRIFT_LABEL[kind]}</Badge>
              <p className="max-w-prose text-body-md text-on-surface-variant">
                {ADMIN_DRIFT_EXPLANATION[kind]}
              </p>
            </div>
          ))}
        </Card>
      ) : null}

      <ListScope />
    </div>
  );
}

/* ------------------------------------------------------------------- row -- */

function AdminTableRow({
  row,
  nowMs,
  isSelf,
}: {
  row: AdminRow;
  nowMs: number;
  isSelf: boolean;
}) {
  return (
    <TR>
      <TD>
        <span className="flex flex-wrap items-center gap-2">
          <span>{row.email ?? EMPTY}</span>
          {/* The one thing that changes what a revoke on this row means. */}
          {isSelf ? <Badge tone="warning">you</Badge> : null}
        </span>
        {row.displayName ? (
          <span className="block text-label-sm text-on-surface-variant">
            {row.displayName}
          </span>
        ) : null}
      </TD>

      <TD>
        <code className="rounded-sm bg-surface-container px-1 font-sans text-label-sm text-on-surface">
          {row.uid}
        </code>
      </TD>

      <TD>
        <StatusBadge row={row} />
      </TD>

      <TD className="whitespace-nowrap">
        <span className="block">{formatDateTime(row.grantedAtMs)}</span>
        {row.grantedAtMs != null ? (
          <span className="block text-label-sm text-on-surface-variant">
            {formatRelative(row.grantedAtMs, nowMs)}
          </span>
        ) : null}
      </TD>

      <TD>{row.grantedBy ?? EMPTY}</TD>

      <TD className="text-right">
        <RevokeButton
          uid={row.uid}
          email={row.email}
          isSelf={isSelf}
          hasClaim={row.hasClaim}
        />
      </TD>
    </TR>
  );
}

/** Drift outranks a disabled account: the worse signal is the useful one. */
function StatusBadge({ row }: { row: AdminRow }) {
  if (row.drift) {
    return <Badge tone="critical">{ADMIN_DRIFT_LABEL[row.drift]}</Badge>;
  }
  if (row.disabled) {
    return <Badge tone="warning">account disabled</Badge>;
  }
  return <Badge tone="positive">can sign in</Badge>;
}

/* ------------------------------------------------------------------ copy -- */

/**
 * The three things that make this screen behave unlike a permissions list.
 *
 * They sit above the grant form rather than in a help page because each one
 * changes what the operator should expect in the minutes AFTER acting — which
 * is exactly when they would otherwise conclude it did not work and try again.
 */
function HowAccessWorks() {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>How access works</CardTitle>
      <ul className="flex flex-col gap-4 text-body-md text-on-surface-variant">
        <Point>
          <strong className="text-on-surface">
            A grant takes effect at their next sign-in, not now.
          </strong>{' '}
          Custom claims are baked into an ID token and into the session cookie
          minted from it, so somebody already signed in keeps the old claims
          until that session is replaced. Nothing here can push a claim into a
          token that already exists — they have to sign out and back in.
        </Point>
        <Point>
          <strong className="text-on-surface">A revoke is immediate.</strong>{' '}
          Removing the claim on its own would not be, for exactly the reason
          above: their session cookie is good for up to 14 days. So a revoke
          also revokes the account&rsquo;s refresh tokens, which the panel&rsquo;s
          gate checks on every single request — their next click lands on the
          sign-in page.
        </Point>
        <Point>
          <strong className="text-on-surface">
            The account has to exist already.
          </strong>{' '}
          This page grants access to a Firebase Auth account; it cannot create
          one, and the panel has no sign-up screen. Use{' '}
          <Literal>pnpm -F admin grant-admin you@example.com --create</Literal>{' '}
          from a terminal to create an account and grant it in one step.
        </Point>
      </ul>
    </Card>
  );
}

/**
 * What this list cannot see, stated plainly rather than papered over.
 *
 * The blind spot is a deliberate trade: closing it means paging through every
 * Firebase Auth account in the project, a cost that grows with the product's
 * user base rather than with the number of admins. An ops console should not
 * scan the whole tenant on page load, so it says so instead.
 */
function ListScope() {
  return (
    <Card className="flex flex-col gap-4">
      <CardTitle>What this list can and cannot see</CardTitle>
      <ul className="flex flex-col gap-4 text-body-md text-on-surface-variant">
        <Point>
          It is built from <Literal>adminUsers</Literal>, a mirror that this page
          and{' '}
          <Literal>grant-admin</Literal> both write on every grant. The mirror is
          a convenience for listing — the claim is what grants access, and each
          row above is checked against the live claim before it is shown.
        </Point>
        <Point>
          <strong className="text-on-surface">
            A claim set by hand does not appear here.
          </strong>{' '}
          If somebody calls <Literal>setCustomUserClaims</Literal> from their own
          script, no mirror row is written: that person can sign in to this panel
          and is invisible on this page. Finding them means reading every
          Firebase Auth account in the project, which this panel will not do —
          check the Auth users list directly if you suspect one.
        </Point>
        <Point>
          That blind spot only ever makes the safety rails{' '}
          <em>more</em> cautious. The &ldquo;this is the last admin&rdquo; check
          counts the rows above that hold the claim, so an unlisted admin can
          cause a needless refusal — one CLI command to fix — but never a revoke
          that leaves nobody with access.
        </Point>
      </ul>
    </Card>
  );
}

function Point({ children }: { children: ReactNode }) {
  return (
    <li className="flex max-w-prose gap-4">
      <span aria-hidden className="text-primary">
        —
      </span>
      <span>{children}</span>
    </li>
  );
}

/**
 * Inline literal — a claim name, a collection, a shell command.
 *
 * `font-sans` is not redundant: Tailwind's preflight points `<code>` at the
 * mono stack, and Sora is the only family this design system allows.
 */
function Literal({ children }: { children: ReactNode }) {
  return (
    <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
      {children}
    </code>
  );
}
