import 'server-only';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { adminDb } from '@/lib/firebase/admin';
import type { UserDocument } from '@/lib/types/user-document';

import { toMillis, toUserRow, type UserListRow } from './user-mapping';

/**
 * Billing: what RevenueCat has actually told this deployment, and what the
 * Firestore mirror says as a result.
 *
 * THE TRUST MODEL, because every number on this page depends on it. RevenueCat
 * is the source of truth for entitlements. `users/{uid}.premiumStatus` and
 * `premiumExpiry` are a MIRROR with two writers (CLAUDE.md §7):
 *
 *   1. `handleRevenueCatWebhook` — authoritative, server-side, and the writer
 *      that also appends the `revenueCatEvents` documents read below.
 *   2. the mobile client, immediately after a purchase, as a fast path so the
 *      UI does not wait on the webhook.
 *
 * Writer (2) means the mirror is CLIENT-FORGEABLE and can drift: a missed
 * webhook, an out-of-order delivery, or a device writing optimistically all
 * leave Firestore disagreeing with RevenueCat. That is the whole reason the
 * refresh below exists.
 *
 * QUERY POLICY (CLAUDE.md §7): no composite indexes. The event listing orders
 * by one field with no filter; the expiring-soon query puts BOTH range bounds on
 * the same field, which the automatic per-field index serves. Adding a filter on
 * any other field to either would demand a composite index a fresh buyer project
 * does not have.
 */

const EVENTS = 'revenueCatEvents';
const USERS = 'users';

const DAY_MS = 24 * 60 * 60 * 1000;

/* -------------------------------------------------------------- pure part -- */

/**
 * One `revenueCatEvents/{autoId}` document, as written by
 * `apps/functions/src/billing/handle_revenuecat_webhook.ts`.
 */
export interface RevenueCatEventRow {
  id: string;
  type: string;
  /** RevenueCat's `app_user_id` — the Firebase uid, unless the SDK ran logged out. */
  appUserId: string | null;
  receivedAtMs: number | null;
  productId: string | null;
  expiresAtMs: number | null;
  /** True only once the entitlement write committed. See `handled` below. */
  handled: boolean;
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

/**
 * Coerces a raw event document into the shape the page renders.
 *
 * Defensive throughout: this collection is append-only and long-lived, so a doc
 * written by an older build of the webhook must still render rather than throw.
 *
 * `handled` reads `=== true` rather than truthiness — a missing field is "we saw
 * it but did not act on it", which is precisely what the webhook records for an
 * event type it ignores, and a truthy coercion of `undefined` would be the same
 * answer for the wrong reason.
 */
export function toEventRow(id: string, data: unknown): RevenueCatEventRow {
  const raw = (
    data != null && typeof data === 'object' ? data : {}
  ) as Record<string, unknown>;

  return {
    id,
    type: asString(raw.type) ?? 'UNKNOWN',
    appUserId: asString(raw.appUserId),
    receivedAtMs: toMillis(raw.receivedAt),
    productId: asString(raw.productId),
    // The shipped webhook writes `expiresAtMs`. `expirationMs` is read as a
    // fallback because that is closer to RevenueCat's own payload field
    // (`expiration_at_ms`), and a hand-written or future doc may use it.
    expiresAtMs: toMillis(raw.expiresAtMs) ?? toMillis(raw.expirationMs),
    handled: raw.handled === true,
  };
}

export interface EventTypeSummary {
  type: string;
  count: number;
  handled: number;
  unhandled: number;
  /** Newest `receivedAt` for this type, or null if none of them carried one. */
  lastSeenMs: number | null;
}

export interface EventSummary {
  total: number;
  handled: number;
  unhandled: number;
  distinctTypes: number;
  /** Newest `receivedAt` across every row. */
  latestMs: number | null;
  /** Newest type first; types with no usable timestamp sort last, by name. */
  byType: EventTypeSummary[];
}

/**
 * Folds a page of events into per-type last-seen counts.
 *
 * Derived in code from ONE fetched page rather than a query per type: a
 * `where('type','==',…)` alongside the `receivedAt` ordering is a composite
 * query, and there would be one per event type. The cost is that every figure
 * here describes the fetched window only — callers must label it that way,
 * because "last seen 3 days ago" and "not seen within the last 100 events" are
 * very different claims.
 */
export function summarizeEvents(
  rows: readonly RevenueCatEventRow[],
): EventSummary {
  const byType = new Map<string, EventTypeSummary>();
  let handled = 0;
  let latestMs: number | null = null;

  for (const row of rows) {
    if (row.handled) handled += 1;
    if (row.receivedAtMs != null && (latestMs == null || row.receivedAtMs > latestMs)) {
      latestMs = row.receivedAtMs;
    }

    const entry = byType.get(row.type) ?? {
      type: row.type,
      count: 0,
      handled: 0,
      unhandled: 0,
      lastSeenMs: null,
    };

    entry.count += 1;
    if (row.handled) entry.handled += 1;
    else entry.unhandled += 1;
    if (
      row.receivedAtMs != null &&
      (entry.lastSeenMs == null || row.receivedAtMs > entry.lastSeenMs)
    ) {
      entry.lastSeenMs = row.receivedAtMs;
    }

    byType.set(row.type, entry);
  }

  return {
    total: rows.length,
    handled,
    unhandled: rows.length - handled,
    distinctTypes: byType.size,
    latestMs,
    byType: [...byType.values()].sort(compareByLastSeen),
  };
}

/**
 * Newest first. A type whose every document was missing `receivedAt` has no
 * position on the timeline, so it sinks to the bottom instead of being treated
 * as infinitely old and displacing a type that really is stale. Name breaks
 * ties so the ordering cannot shuffle between requests.
 */
function compareByLastSeen(a: EventTypeSummary, b: EventTypeSummary): number {
  if (a.lastSeenMs == null && b.lastSeenMs == null) {
    return a.type.localeCompare(b.type);
  }
  if (a.lastSeenMs == null) return 1;
  if (b.lastSeenMs == null) return -1;
  return b.lastSeenMs - a.lastSeenMs || a.type.localeCompare(b.type);
}

/**
 * Whole days until [ms], floored at 0.
 *
 * Rounded UP so an expiry eight hours out reads "1 day" rather than "0" — a
 * subscription that has not lapsed yet must never display as though it has.
 */
export function daysUntil(ms: number | null, nowMs: number): number | null {
  if (ms == null) return null;
  return Math.max(0, Math.ceil((ms - nowMs) / DAY_MS));
}

/**
 * RevenueCat's placeholder id for a device that purchased before signing in.
 *
 * No `users/{uid}` document can match one, so the panel must not offer a link to
 * a page that will 404 — and an operator seeing these should know the mobile app
 * is not calling `Purchases.logIn(uid)` before purchase.
 */
export function isAnonymousAppUserId(id: string | null): boolean {
  return id != null && id.startsWith('$RCAnonymousID:');
}

/* --------------------------------------------------------------- reads ---- */

function describeError(e: unknown): string {
  return e instanceof Error && e.message ? e.message : 'Unknown error.';
}

export interface EventPage {
  rows: RevenueCatEventRow[];
  /** The window every derived figure describes. */
  limit: number;
  nowMs: number;
  /** Set when the read itself failed — distinct from "no events exist". */
  error: string | null;
}

/**
 * The most recent webhook events.
 *
 * A collection that has never been written to returns ZERO ROWS, not an error —
 * which is exactly what a deployment with no RevenueCat webhook configured looks
 * like. Reaching the catch means credentials, IAM, or the network, and the page
 * says so rather than showing that as an empty state.
 */
export async function listRecentEvents(limit = 100): Promise<EventPage> {
  const nowMs = Date.now();

  try {
    const snap = await adminDb()
      .collection(EVENTS)
      .orderBy('receivedAt', 'desc')
      .limit(limit)
      .get();

    return {
      rows: snap.docs.map((doc) => toEventRow(doc.id, doc.data())),
      limit,
      nowMs,
      error: null,
    };
  } catch (e) {
    return { rows: [], limit, nowMs, error: describeError(e) };
  }
}

export interface ExpiringPage {
  rows: UserListRow[];
  days: number;
  /** Row cap. `rows.length === limit` means the list is truncated. */
  limit: number;
  nowMs: number;
  error: string | null;
}

/**
 * Subscriptions whose mirrored expiry falls inside the next [days].
 *
 * BOTH bounds sit on `premiumExpiry`, and the ordering is on the same field.
 * Multiple ranges on one field need no composite index (CLAUDE.md §7) — adding
 * `where('premiumStatus','==','premium')` would, which is why the status is left
 * to the caller to display rather than filter on. That is honest anyway: a row
 * with a future expiry and a `free` status is mirror drift worth seeing.
 */
export async function listExpiringSoon(
  days = 30,
  limit = 100,
): Promise<ExpiringPage> {
  const nowMs = Date.now();
  const cutoff = new Date(nowMs + days * DAY_MS);

  try {
    const snap = await adminDb()
      .collection(USERS)
      .where('premiumExpiry', '>=', new Date(nowMs))
      .where('premiumExpiry', '<=', cutoff)
      .orderBy('premiumExpiry', 'asc')
      .limit(limit)
      .get();

    return {
      rows: snap.docs.map((doc) =>
        toUserRow(doc.id, doc.data() as Partial<UserDocument>),
      ),
      days,
      limit,
      nowMs,
      error: null,
    };
  } catch (e) {
    return { rows: [], days, limit, nowMs, error: describeError(e) };
  }
}

/**
 * Whether the admin-side entitlement refresh can run at all.
 *
 * The panel hides the control when this is false rather than offering a button
 * that can only ever answer 503. Note this is the SAME secret the
 * `refreshEntitlement` Cloud Function uses — a deployment can have it set for
 * Functions and not for the panel, since they are separate runtimes.
 */
export function isRevenueCatConfigured(): boolean {
  return (process.env.REVENUECAT_API_KEY ?? '').trim().length > 0;
}

export interface BillingOverview {
  events: EventPage;
  summary: EventSummary;
  expiring: ExpiringPage;
  revenueCatConfigured: boolean;
}

/**
 * Everything /billing renders, in one call.
 *
 * The clock reads live in `listRecentEvents` / `listExpiringSoon` rather than in
 * the page: server components are held to React's purity rules, and "now" has to
 * be consistent with the rows it describes.
 */
export async function loadBilling(opts?: {
  eventLimit?: number;
  expiringDays?: number;
  expiringLimit?: number;
}): Promise<BillingOverview> {
  const [events, expiring] = await Promise.all([
    listRecentEvents(opts?.eventLimit),
    listExpiringSoon(opts?.expiringDays, opts?.expiringLimit),
  ]);

  return {
    events,
    summary: summarizeEvents(events.rows),
    expiring,
    revenueCatConfigured: isRevenueCatConfigured(),
  };
}

/* ------------------------------------------------------------- refresh ---- */

/** The mirrored entitlement, before and after a refresh. */
export interface EntitlementState {
  premiumStatus: string | null;
  premiumExpiryMs: number | null;
}

export type RefreshFailure =
  /** REVENUECAT_API_KEY is unset in this runtime. */
  | { kind: 'not-configured' }
  /** No `users/{uid}` document — refusing to create one. */
  | { kind: 'no-such-user' }
  /** RevenueCat answered, but not with something we can act on. */
  | { kind: 'upstream'; detail: string };

export type RefreshResult =
  | {
      ok: true;
      uid: string;
      before: EntitlementState;
      after: EntitlementState;
      /** False when RevenueCat agreed with what Firestore already said. */
      changed: boolean;
    }
  | { ok: false; failure: RefreshFailure; message: string };

interface RevenueCatSubscriberResponse {
  subscriber?: {
    entitlements?: Record<string, { expires_date?: string | null }>;
  };
}

/**
 * The entitlement name RevenueCat is expected to grant. Hardcoded because the
 * mobile client and `refreshEntitlement` both read literally `premium`; a
 * differently-named entitlement in the RevenueCat dashboard grants nothing
 * anywhere in this product.
 */
const ENTITLEMENT = 'premium';

/** 100 years out. See the comment at the write below — this is load-bearing. */
const LIFETIME_MS = 100 * 365 * 24 * 60 * 60 * 1000;

/**
 * Re-reads one user's entitlement from RevenueCat and rewrites the mirror.
 *
 * WHY THIS IS NOT THE CLOUD FUNCTION. `refreshEntitlement`
 * (apps/functions/src/billing/refresh_entitlement.ts) only ever refreshes
 * `request.auth.uid`, so an admin literally cannot use it for someone else. The
 * REST lookup and the write are therefore repeated here — deliberately mirroring
 * that function's semantics field for field, so the two writers cannot disagree.
 *
 * Idempotent: calling it twice with an unchanged subscription writes the same
 * values the second time.
 */
export async function refreshEntitlement(uid: string): Promise<RefreshResult> {
  const apiKey = (process.env.REVENUECAT_API_KEY ?? '').trim();
  if (!apiKey) {
    return {
      ok: false,
      failure: { kind: 'not-configured' },
      message:
        'REVENUECAT_API_KEY is not set for the admin panel, so RevenueCat cannot be queried. Nothing was written.',
    };
  }

  const ref = adminDb().collection(USERS).doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    // A merge write would CREATE this document — a user record with nothing but
    // an entitlement on it, for a uid that may simply be a typo.
    return {
      ok: false,
      failure: { kind: 'no-such-user' },
      message: `No users/${uid} document exists. Nothing was written — refusing to create a user document from a billing refresh.`,
    };
  }

  const data = snap.data() as Partial<UserDocument> | undefined;
  const before: EntitlementState = {
    premiumStatus: data?.premiumStatus ?? null,
    premiumExpiryMs: toMillis(data?.premiumExpiry),
  };

  // Web subscribers pay through Paystack, which RevenueCat knows nothing
  // about — a RevenueCat "not premium" answer must not downgrade them.
  const source = (data as { premiumSource?: string } | undefined)?.premiumSource;
  if (
    source === 'paystack' &&
    before.premiumStatus === 'premium' &&
    (before.premiumExpiryMs ?? 0) > Date.now()
  ) {
    return {
      ok: false,
      failure: { kind: 'upstream', detail: 'paystack-entitlement' },
      message:
        'This user has an active Premium plan bought on the web via Paystack. RevenueCat refresh skipped — nothing was written.',
    };
  }

  const lookup = await fetchEntitlement(uid, apiKey);
  if (!lookup.ok) {
    return {
      ok: false,
      failure: { kind: 'upstream', detail: lookup.message },
      message: lookup.message,
    };
  }

  const { isPremium, expiryMs } = lookup;

  await ref.set(
    {
      premiumStatus: isPremium ? 'premium' : 'free',
      // CRITICAL: a premium grant must never store a null expiry. The server's
      // `evaluateQuota` (apps/functions/src/quota/quota_logic.ts) requires a
      // non-null expiry in the FUTURE, so `{ premiumStatus: 'premium',
      // premiumExpiry: null }` reads as FREE everywhere it matters and would
      // silently grant nothing. A RevenueCat entitlement with no `expires_date`
      // (a lifetime purchase) is therefore stored as ~100 years out — the same
      // trick handleRevenueCatWebhook uses for NON_RENEWING_PURCHASE.
      premiumExpiry:
        isPremium && expiryMs != null ? Timestamp.fromMillis(expiryMs) : null,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const after: EntitlementState = {
    premiumStatus: isPremium ? 'premium' : 'free',
    premiumExpiryMs: isPremium ? expiryMs : null,
  };

  return {
    ok: true,
    uid,
    before,
    after,
    changed:
      before.premiumStatus !== after.premiumStatus ||
      before.premiumExpiryMs !== after.premiumExpiryMs,
  };
}

type EntitlementLookup =
  | { ok: true; isPremium: boolean; expiryMs: number | null }
  | { ok: false; message: string };

const FREE: EntitlementLookup = { ok: true, isPremium: false, expiryMs: null };

/**
 * GET https://api.revenuecat.com/v1/subscribers/{app_user_id}
 *
 * Only the entitlement named `premium` is read, exactly as the callable does.
 * A 404 means RevenueCat has no subscriber record at all, which is a definite
 * "free" rather than an error — that is how a user who never purchased looks.
 */
async function fetchEntitlement(
  uid: string,
  apiKey: string,
): Promise<EntitlementLookup> {
  let response: Response;
  try {
    response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      {
        method: 'GET',
        headers: { Authorization: `Bearer ${apiKey}` },
        // The callable is bounded by its 30s function timeout; a Next route
        // handler has no such ceiling, so bound it here rather than let a hung
        // upstream hold the request open.
        signal: AbortSignal.timeout(15_000),
      },
    );
  } catch (e) {
    return {
      ok: false,
      message: `Could not reach RevenueCat: ${describeError(e)}. Nothing was written.`,
    };
  }

  if (response.status === 404) return FREE;

  if (!response.ok) {
    return {
      ok: false,
      message: `RevenueCat returned ${response.status}. Nothing was written — the mirror is unchanged.`,
    };
  }

  let body: RevenueCatSubscriberResponse;
  try {
    body = (await response.json()) as RevenueCatSubscriberResponse;
  } catch (e) {
    return {
      ok: false,
      message: `RevenueCat returned a response that is not JSON: ${describeError(e)}. Nothing was written.`,
    };
  }

  const entitlement = body.subscriber?.entitlements?.[ENTITLEMENT];
  if (!entitlement) return FREE;

  if (!entitlement.expires_date) {
    // Lifetime — no expiry to parse. See LIFETIME_MS and the write above.
    return { ok: true, isPremium: true, expiryMs: Date.now() + LIFETIME_MS };
  }

  const expires = Date.parse(entitlement.expires_date);
  if (!Number.isFinite(expires)) {
    // DELIBERATE DIVERGENCE from the callable, which does not guard this: an
    // unparseable date there fails the `expires > now` test and quietly writes
    // `free`, REVOKING a paying user's entitlement over a formatting change
    // upstream. Refusing to write is the safe direction.
    return {
      ok: false,
      message: `RevenueCat returned an unparseable expires_date ("${entitlement.expires_date}"). Nothing was written, to avoid downgrading a subscriber on a value we cannot read.`,
    };
  }

  // An entitlement already in the past is not a grant. Matches the callable.
  return expires > Date.now()
    ? { ok: true, isPremium: true, expiryMs: expires }
    : FREE;
}
