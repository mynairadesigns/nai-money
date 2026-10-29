'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { Badge, Button, Card, CardTitle, Input } from '@/components/ui';
import { EMPTY, formatDateTime } from '@/lib/format';

/**
 * Admin-triggered entitlement refresh for ONE user.
 *
 * A client component because it holds a uid and a result, but it owns no
 * knowledge: everything it decides comes back from
 * POST /api/admin/billing/refresh, which re-authorizes the caller itself.
 *
 * The uid is typed (or arrives prefilled from `?uid=`) rather than picked from a
 * dropdown on purpose — this runs against RevenueCat's live API and writes to
 * `users/{uid}`, so it should take a deliberate act, not a stray click in a list.
 */

interface EntitlementState {
  premiumStatus: string | null;
  premiumExpiryMs: number | null;
}

interface RefreshResponse {
  ok?: boolean;
  uid?: string;
  before?: EntitlementState;
  after?: EntitlementState;
  changed?: boolean;
  auditError?: string | null;
  error?: string;
}

export function RefreshForm({ defaultUid }: { defaultUid: string }) {
  const router = useRouter();

  const [uid, setUid] = useState(defaultUid);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<RefreshResponse | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setResult(null);

    try {
      const response = await fetch('/api/admin/billing/refresh', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ uid }),
      });

      const body: RefreshResponse = await response.json().catch(() => ({}));

      if (!response.ok) {
        setError(body.error ?? 'The refresh failed.');
        return;
      }

      setResult(body);
      // The tables above are server-rendered from Firestore, so they have to
      // re-render for a changed expiry to leave the expiring-soon list.
      router.refresh();
    } catch (e) {
      setError(
        e instanceof Error
          ? `The refresh failed: ${e.message}`
          : 'The refresh failed — network error.',
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="flex flex-col gap-6">
      <div>
        <CardTitle>Refresh a user&rsquo;s entitlement</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Asks RevenueCat what this user is actually entitled to and rewrites{' '}
          <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
            premiumStatus
          </code>{' '}
          and{' '}
          <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
            premiumExpiry
          </code>{' '}
          to match. Use it when a user says they paid and the app still shows the
          paywall — that is a missed webhook, and this is the repair. It is
          idempotent: running it on an unchanged subscription writes the same
          values again.
        </p>
      </div>

      <form onSubmit={submit} className="flex flex-wrap items-end gap-4">
        <label className="flex min-w-64 flex-1 flex-col gap-2">
          <span className="text-label-sm uppercase text-on-surface-variant">
            Firebase uid
          </span>
          <Input
            name="uid"
            value={uid}
            onChange={(e) => setUid(e.target.value)}
            placeholder="the uid from the Users page"
            autoComplete="off"
            spellCheck={false}
          />
        </label>

        <Button type="submit" disabled={busy || uid.trim().length === 0}>
          {busy ? 'Checking RevenueCat…' : 'Refresh from RevenueCat'}
        </Button>
      </form>

      {error ? (
        <p role="alert" className="max-w-prose text-label-md text-error">
          {error}
        </p>
      ) : null}

      {result?.ok ? <Outcome result={result} /> : null}
    </Card>
  );
}

function Outcome({ result }: { result: RefreshResponse }) {
  const before = result.before;
  const after = result.after;

  return (
    <div className="flex flex-col gap-4 rounded-lg bg-surface-container-low p-6">
      <div className="flex flex-wrap items-center gap-4">
        <span className="text-label-md uppercase text-on-surface">
          {result.changed ? 'Mirror updated' : 'Already in sync'}
        </span>
        <Badge tone={result.changed ? 'warning' : 'positive'}>
          {result.changed
            ? 'Firestore had drifted'
            : 'RevenueCat agreed with Firestore'}
        </Badge>
      </div>

      <dl className="grid gap-6 sm:grid-cols-2">
        <div className="flex flex-col gap-1">
          <dt className="text-label-sm uppercase text-on-surface-variant">
            Before
          </dt>
          <dd className="text-body-md text-on-surface">
            {describe(before)}
          </dd>
        </div>
        <div className="flex flex-col gap-1">
          <dt className="text-label-sm uppercase text-on-surface-variant">
            After
          </dt>
          <dd className="text-body-md text-on-surface">{describe(after)}</dd>
        </div>
      </dl>

      <p className="max-w-prose text-label-sm text-on-surface-variant">
        Written to <span className="text-on-surface">users/{result.uid}</span>.
        The mobile app picks this up on its next Firestore read; RevenueCat&rsquo;s
        own entitlement stream on the device is unaffected either way.
      </p>

      {result.auditError ? (
        <p role="alert" className="max-w-prose text-label-md text-error">
          The entitlement was written, but the audit entry failed:{' '}
          {result.auditError} — this change is missing from the audit log. Record
          it by hand if your deployment relies on that trail.
        </p>
      ) : null}
    </div>
  );
}

/** Renders one side of the change. "not set" and "" must not look alike. */
function describe(state: EntitlementState | undefined): string {
  if (!state) return EMPTY;
  const status = state.premiumStatus ?? 'not set';
  const expiry =
    state.premiumExpiryMs == null
      ? 'no expiry'
      : formatDateTime(state.premiumExpiryMs);
  return `${status} · ${expiry}`;
}
