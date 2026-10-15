import { Card, CardTitle, EmptyState, Stat } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import {
  AUDIT_ACTION_LABEL,
  listAuditEntries,
  type AuditRow,
} from '@/lib/audit/log';
import { requireAdmin } from '@/lib/auth/require-admin';
import { EMPTY, formatDateTime, formatRelative } from '@/lib/format';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const LIMIT = 100;

/**
 * The panel's audit trail.
 *
 * Reads `adminAuditLog`, which `firestore.rules` denies to every client — so
 * this page is the only way to see it short of the Firestore console, and no
 * end user can read or forge an entry.
 *
 * Scope is narrow on purpose: Remote Config publishing is currently the only
 * mutation this panel performs, so it is the only thing that appears here. An
 * empty log is the honest state of a deployment nobody has changed, not a
 * broken query — the copy below says so, because "no rows" otherwise reads as
 * a fault.
 */
export default async function AuditPage() {
  await requireAdmin();

  const { rows, nowMs, error } = await listAuditEntries(LIMIT);

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">Audit log</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Every change made from this panel, newest first — who made it, what it
          was before, and what it is now. Changes made directly in the Firebase
          console do not appear here; nothing outside this panel writes to the
          log.
        </p>
      </div>

      {error ? (
        <Card className="flex flex-col gap-2">
          <CardTitle>Could not read the audit log</CardTitle>
          <p role="alert" className="max-w-prose text-body-md text-error">
            {error}
          </p>
          <p className="max-w-prose text-body-md text-on-surface-variant">
            An empty collection reads as zero entries rather than an error, so
            this is a credentials, IAM, or connectivity problem — not an empty
            log.
          </p>
        </Card>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Stat
          label="Entries shown"
          value={rows.length}
          hint={
            rows.length === LIMIT
              ? `most recent ${LIMIT} — older entries exist`
              : 'the complete log'
          }
        />
        <Stat
          label="Most recent"
          value={
            <span className="text-body-lg">
              {rows.length > 0 ? formatRelative(rows[0].atMs, nowMs) : EMPTY}
            </span>
          }
          hint={rows.length > 0 ? (rows[0].actorEmail ?? rows[0].actorUid) : 'no activity'}
        />
        <Stat
          label="Distinct admins"
          value={new Set(rows.map((r) => r.actorUid)).size}
          hint="across the entries shown"
        />
      </div>

      {rows.length === 0 && !error ? (
        <EmptyState
          title="No changes recorded"
          body="Nothing has been published from this panel yet. Remote Config publishing is currently the only action that writes an audit entry — edits made in the Firebase console are invisible to it."
        />
      ) : (
        <Card className="flex flex-col gap-4">
          <CardTitle>Recent activity</CardTitle>
          <Table>
            <THead>
              <TH>When</TH>
              <TH>Admin</TH>
              <TH>Action</TH>
              <TH>Change</TH>
            </THead>
            <TBody>
              {rows.map((row) => (
                <Entry key={row.id} row={row} nowMs={nowMs} />
              ))}
            </TBody>
          </Table>
        </Card>
      )}
    </div>
  );
}

function Entry({ row, nowMs }: { row: AuditRow; nowMs: number }) {
  const label =
    AUDIT_ACTION_LABEL[row.action as keyof typeof AUDIT_ACTION_LABEL] ??
    row.action;

  // Union of both sides: a key that only appears in `after` is a creation, and
  // one that only appears in `before` is a removal. Reading a single side would
  // silently drop one of those.
  const keys = [
    ...new Set([...Object.keys(row.before), ...Object.keys(row.after)]),
  ].sort();

  return (
    <TR>
      <TD className="whitespace-nowrap">
        <span className="block">{formatDateTime(row.atMs)}</span>
        <span className="block text-label-sm text-on-surface-variant">
          {formatRelative(row.atMs, nowMs)}
        </span>
      </TD>
      <TD>
        <span className="block">{row.actorEmail ?? EMPTY}</span>
        <span className="block text-label-sm text-on-surface-variant">
          {row.actorUid}
        </span>
      </TD>
      <TD>
        <span className="block">{label}</span>
        {row.target ? (
          <span className="block text-label-sm text-on-surface-variant">
            {row.target}
          </span>
        ) : null}
      </TD>
      <TD>
        {keys.length === 0 ? (
          EMPTY
        ) : (
          <ul className="flex flex-col gap-1">
            {keys.map((key) => (
              <li key={key} className="text-label-sm">
                <span className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
                  {key}
                </span>{' '}
                <span className="text-on-surface-variant">
                  {display(row.before[key])}
                </span>{' '}
                <span aria-hidden>→</span>{' '}
                <span className="text-on-surface">{display(row.after[key])}</span>
              </li>
            ))}
          </ul>
        )}
      </TD>
    </TR>
  );
}

/** Distinguishes "had no value" from "was the empty string". */
function display(value: string | null | undefined): string {
  if (value == null) return 'not set';
  return value === '' ? '""' : value;
}
