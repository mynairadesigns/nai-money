import Link from 'next/link';

import { Button, Card, EmptyState, Input } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { loadUserList } from '@/lib/data/users';
import { EMPTY, formatDate, formatRelative } from '@/lib/format';

import { Code } from './code';
import { EntitlementBadge } from './entitlement-badge';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const PAGE_SIZE = 50;

/**
 * User directory.
 *
 * All state lives in the URL — search term, premium filter, cursor — so the
 * page is a plain server component with no client bundle, and an operator can
 * paste a link to exactly what they were looking at. The controls are a GET
 * form and ordinary anchors for the same reason: everything works with
 * JavaScript disabled.
 */
export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;

  const query = firstParam(params.q)?.trim().toLowerCase() ?? '';
  const premiumOnly = firstParam(params.premium) === '1';
  const cursor = toCursor(firstParam(params.cursor));
  const searching = query.length > 0;

  const { rows, nextCursorMs, nowMs, missingIndex } = await loadUserList({
    // Search wins over the filter/cursor: an exact-email lookup returns at most
    // one row, so paginating or narrowing it further is meaningless.
    email: searching ? query : null,
    premiumOnly,
    startAfterCreatedAtMs: cursor,
    limit: PAGE_SIZE,
  });

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">Users</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          Find any user, inspect their entitlement, and see why they are hitting
          a limit.
        </p>
      </div>

      <Card>
        <form method="get" className="flex flex-wrap items-end gap-4">
          <label className="flex min-w-64 flex-1 flex-col gap-2">
            <span className="text-label-sm uppercase text-on-surface-variant">
              Email
            </span>
            <Input
              type="search"
              name="q"
              defaultValue={query}
              placeholder="exact@address.com"
              autoComplete="off"
            />
          </label>

          <label className="flex items-center gap-2 py-4 text-body-md text-on-surface">
            <input
              type="checkbox"
              name="premium"
              value="1"
              defaultChecked={premiumOnly}
              className="size-4 accent-primary"
            />
            Premium only
          </label>

          <Button type="submit">Search</Button>

          {searching || premiumOnly || cursor != null ? (
            <Link
              href="/users"
              className="rounded px-6 py-4 text-label-md text-primary hover:bg-surface-container"
            >
              Reset
            </Link>
          ) : null}
        </form>

        <p className="mt-4 text-label-sm text-on-surface-variant">
          Email search is exact-match only — Firestore has no substring index,
          and adding one would mean shipping a search service with the product.
          {searching && premiumOnly
            ? ' The premium filter is ignored while searching: an exact lookup returns one user, whose status the Status column already shows.'
            : ''}
        </p>
      </Card>

      {missingIndex ? (
        <EmptyState
          title="The premium filter needs a composite index"
          body={
            <>
              This query combines <Code>premiumStatus</Code> with an ordering on{' '}
              <Code>createdAt</Code>, which Firestore only serves from a
              declared index. Run{' '}
              <Code>firebase deploy --only firestore:indexes</Code> from the
              repo root, then retry — a freshly created index takes a few
              minutes to build.
            </>
          }
        />
      ) : rows.length === 0 ? (
        <EmptyState
          title={searching ? 'No user with that email' : 'No users yet'}
          body={
            searching
              ? 'The lookup is an exact match on the stored address, which the app lowercases at sign-up. Check for a typo or a different provider address.'
              : premiumOnly
                ? 'No user currently carries a premium status.'
                : 'Users appear here once the mobile app has created their account document.'
          }
        />
      ) : (
        // A full-bleed table reads better than one inset by the Card's padding,
        // and `cx` is a naive join — a `p-0` override would lose to Card's
        // `p-6` in the stylesheet, so the surface tokens are applied directly.
        <div className="overflow-hidden rounded-lg bg-surface-container-lowest shadow-level-1">
          <Table>
            <THead>
              <TH>Email</TH>
              <TH>Name</TH>
              <TH>Currency</TH>
              <TH>Status</TH>
              <TH>Created</TH>
              <TH>Last sync</TH>
            </THead>
            <TBody>
              {rows.map((row) => (
                <TR key={row.uid}>
                  <TD>
                    <Link
                      href={`/users/${row.uid}`}
                      className="text-primary hover:underline"
                    >
                      {row.email ?? row.uid}
                    </Link>
                  </TD>
                  <TD>{row.displayName ?? EMPTY}</TD>
                  <TD>{row.defaultCurrency ?? EMPTY}</TD>
                  <TD>
                    <EntitlementBadge row={row} nowMs={nowMs} />
                  </TD>
                  <TD>{formatDate(row.createdAtMs)}</TD>
                  <TD>{formatRelative(row.lastSyncAtMs, nowMs)}</TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </div>
      )}

      {!searching && (cursor != null || nextCursorMs != null) ? (
        <div className="flex items-center gap-4">
          {cursor != null ? (
            <Link
              href={listHref({ premiumOnly, cursor: null })}
              className="rounded border border-outline/20 px-6 py-4 text-label-md text-on-surface hover:bg-surface-container-high"
            >
              First page
            </Link>
          ) : null}

          {nextCursorMs != null ? (
            <Link
              href={listHref({ premiumOnly, cursor: nextCursorMs })}
              className="rounded bg-primary px-6 py-4 text-label-md text-on-primary hover:shadow-level-2"
            >
              Next {PAGE_SIZE}
            </Link>
          ) : null}

          {/* Cursor paging is forward-only: `startAfter` needs the boundary
              value of the page being left, and the previous one is not in
              scope here. "First page" is the honest way back. */}
        </div>
      ) : null}
    </div>
  );
}

/** A repeated query key arrives as an array; take the first occurrence. */
function firstParam(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

/** The cursor is a createdAt in milliseconds; anything else is discarded. */
function toCursor(raw: string | undefined): number | null {
  if (!raw) return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

function listHref(opts: { premiumOnly: boolean; cursor: number | null }): string {
  const params = new URLSearchParams();
  if (opts.premiumOnly) params.set('premium', '1');
  if (opts.cursor != null) params.set('cursor', String(opts.cursor));
  const qs = params.toString();
  return qs ? `/users?${qs}` : '/users';
}
