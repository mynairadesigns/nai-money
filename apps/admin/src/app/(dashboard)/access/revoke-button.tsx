'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { Button } from '@/components/ui';

import { accessWarnings, postAccess, type AccessResponse } from './access-api';

/**
 * Per-row revoke, with a mandatory confirmation step.
 *
 * Always two-step, never a bare button: a revoke is immediate and irreversible
 * from inside the panel — the target's sessions die at once and only a new
 * grant brings them back — so a misclick on a table row is too cheap a way to
 * cause it. The confirmation is also where the consequence is spelled out,
 * which is the moment it is actually worth reading.
 *
 * The SELF case is louder still, and sends the explicit `confirmSelf` the route
 * requires. Nothing else in the UI can produce that flag.
 */
export function RevokeButton({
  uid,
  email,
  isSelf,
  hasClaim,
}: {
  uid: string;
  email: string | null;
  isSelf: boolean;
  /** False for a drift row: there is no access to end, only a row to clear. */
  hasClaim: boolean;
}) {
  const router = useRouter();

  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<AccessResponse | null>(null);
  const [result, setResult] = useState<AccessResponse | null>(null);

  const label = hasClaim ? 'Revoke' : 'Clear row';
  const who = email ?? uid;

  async function revoke() {
    setBusy(true);
    setFailure(null);

    try {
      const response = await postAccess({
        action: 'revoke',
        uid,
        // Only ever true on the operator's own row, and only after they have
        // read the warning below.
        confirmSelf: isSelf,
      });

      if (!response.ok) {
        setFailure(response);
        setConfirming(false);
        return;
      }

      const warnings = accessWarnings(response);

      // A clean revoke against someone else needs no report: refreshing makes
      // the row vanish, which says it plainly. Anything with a caveat — or a
      // self-revoke, whose refresh would bounce straight to /login — stays on
      // screen until the operator has seen it.
      if (warnings.length === 0 && !isSelf) {
        router.refresh();
        return;
      }

      setResult(response);
      setConfirming(false);
    } catch (e) {
      setFailure({
        error: e instanceof Error ? e.message : 'The request failed — network error.',
      });
      setConfirming(false);
    } finally {
      setBusy(false);
    }
  }

  if (result) {
    return <Outcome result={result} isSelf={isSelf} onReload={() => router.refresh()} />;
  }

  if (!confirming) {
    return (
      <div className="flex flex-col items-end gap-2">
        <Button type="button" variant="ghost" onClick={() => setConfirming(true)}>
          {label}
        </Button>
        {failure ? <Failure failure={failure} /> : null}
      </div>
    );
  }

  return (
    <div className="flex w-72 flex-col gap-2 rounded bg-surface-container-low p-4 text-left">
      {isSelf ? (
        <>
          <p className="text-label-md text-error">
            This revokes YOUR OWN access.
          </p>
          <p className="text-body-md text-on-surface-variant">
            You will be signed out immediately and this page will stop letting
            you in. Getting back requires{' '}
            <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
              pnpm -F admin grant-admin {who}
            </code>{' '}
            from a terminal with project credentials.
          </p>
        </>
      ) : hasClaim ? (
        <p className="text-body-md text-on-surface-variant">
          Remove admin access for <span className="text-on-surface">{who}</span>?
          Their sessions are revoked too, so access ends immediately rather than
          whenever their cookie would have expired. Their Homa Finance account is
          untouched.
        </p>
      ) : (
        <p className="text-body-md text-on-surface-variant">
          This row carries no admin claim, so nobody loses access — it only
          deletes the <span className="text-on-surface">adminUsers</span> mirror
          document for <span className="text-on-surface">{who}</span>.
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        <Button type="button" variant="danger" onClick={revoke} disabled={busy}>
          {busy ? 'Working…' : isSelf ? 'Revoke my own access' : label}
        </Button>
        <Button
          type="button"
          variant="text"
          onClick={() => setConfirming(false)}
          disabled={busy}
        >
          Cancel
        </Button>
      </div>
    </div>
  );
}

function Failure({ failure }: { failure: AccessResponse }) {
  return (
    <div className="flex w-72 flex-col gap-1 text-left">
      <p role="alert" className="text-label-md text-error">
        {failure.error}
      </p>
      {failure.hint ? (
        <p className="text-body-md text-on-surface-variant">{failure.hint}</p>
      ) : null}
    </div>
  );
}

function Outcome({
  result,
  isSelf,
  onReload,
}: {
  result: AccessResponse;
  isSelf: boolean;
  onReload: () => void;
}) {
  return (
    <div className="flex w-72 flex-col gap-2 rounded bg-surface-container-low p-4 text-left">
      <p className="text-body-md text-on-surface">{result.message}</p>

      {accessWarnings(result).map((warning) => (
        <p key={warning} role="alert" className="text-label-md text-error">
          {warning}
        </p>
      ))}

      {isSelf ? (
        // Not a router.refresh(): the session is already dead, so re-rendering
        // would bounce to /login before this could be read. Let them leave when
        // they have.
        <a
          href="/login"
          className="rounded px-6 py-4 text-center text-label-md text-primary hover:bg-surface-container"
        >
          Go to sign-in
        </a>
      ) : (
        <Button type="button" variant="ghost" onClick={onReload}>
          Reload list
        </Button>
      )}
    </div>
  );
}
