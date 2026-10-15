'use client';

import { useRouter } from 'next/navigation';
import { useState, type FormEvent } from 'react';

import { Button, Card, CardTitle, Input } from '@/components/ui';

import { accessWarnings, postAccess, type AccessResponse } from './access-api';

/**
 * Grants the admin claim to an existing account.
 *
 * A client island rather than a GET form because the outcome is not a page
 * state: a grant can succeed AND still have something to report (a mirror or
 * audit write that failed), and a refusal carries guidance the operator has to
 * read before trying again. Both would be lost in a redirect.
 */
export function GrantForm() {
  const router = useRouter();

  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<AccessResponse | null>(null);
  const [result, setResult] = useState<AccessResponse | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;

    setBusy(true);
    setFailure(null);
    setResult(null);

    try {
      const response = await postAccess({ action: 'grant', email });

      if (!response.ok) {
        setFailure(response);
        return;
      }

      setResult(response);
      setEmail('');
      // The list is a server component reading Auth and the mirror, so it has
      // to re-render for the new admin to appear in the table below.
      router.refresh();
    } catch (e) {
      setFailure({
        error: e instanceof Error ? e.message : 'The request failed — network error.',
      });
    } finally {
      setBusy(false);
    }
  }

  const warnings = result ? accessWarnings(result) : [];

  return (
    <Card className="flex flex-col gap-4">
      <div>
        <CardTitle>Grant access</CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          The account must already exist in Firebase Auth — this page grants
          access to one, it cannot create one, and the panel has no sign-up
          screen. To make a brand-new admin account, run{' '}
          <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
            pnpm -F admin grant-admin you@example.com --create
          </code>{' '}
          from a terminal, which creates the account and grants it in one step.
        </p>
      </div>

      <form onSubmit={submit} className="flex flex-wrap items-end gap-4">
        <label className="flex min-w-64 flex-1 flex-col gap-2">
          <span className="text-label-sm uppercase text-on-surface-variant">
            Email
          </span>
          <Input
            type="email"
            name="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="them@example.com"
            autoComplete="off"
          />
        </label>

        <Button type="submit" disabled={busy || email.trim().length === 0}>
          {busy ? 'Granting…' : 'Grant admin'}
        </Button>
      </form>

      {failure ? (
        <div className="flex flex-col gap-2">
          <p role="alert" className="text-label-md text-error">
            {failure.error}
          </p>
          {failure.hint ? (
            <p className="max-w-prose text-body-md text-on-surface-variant">
              {failure.hint}
            </p>
          ) : null}
        </div>
      ) : null}

      {result ? (
        <div className="flex flex-col gap-2 rounded bg-surface-container-low p-4">
          <p className="text-body-md text-on-surface">{result.message}</p>
          {result.email ? (
            <p className="text-label-sm text-on-surface-variant">
              {result.email} — {result.uid}
            </p>
          ) : null}
          {result.alreadyAdmin ? null : (
            <p className="max-w-prose text-body-md text-on-surface-variant">
              Their claims are baked into the token they already hold, so they
              must sign out and back in before the panel will let them past the
              gate.
            </p>
          )}
          {warnings.map((warning) => (
            <p key={warning} role="alert" className="max-w-prose text-label-md text-error">
              {warning}
            </p>
          ))}
        </div>
      ) : null}
    </Card>
  );
}
