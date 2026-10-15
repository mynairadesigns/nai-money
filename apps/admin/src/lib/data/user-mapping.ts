import {
  QUOTA_COUNTED_FIELDS,
  type AiUsageDocument,
  type UserDocument,
} from '@/lib/types/user-document';

/**
 * Pure mapping from a raw `users/{uid}` document to the shape the UI renders.
 *
 * Import-clean on purpose — no `firebase-admin` here — so it can be unit
 * tested directly. This mirrors the convention in apps/functions, where the
 * logic a handler needs lives in a `*_logic.ts` sibling and the handler does
 * only the Firestore I/O.
 */

export interface UserListRow {
  uid: string;
  email: string | null;
  displayName: string | null;
  defaultCurrency: string | null;
  premiumStatus: string | null;
  premiumExpiryMs: number | null;
  createdAtMs: number | null;
  lastSyncAtMs: number | null;
}

interface TimestampLike {
  toMillis(): number;
}

/**
 * Firestore hands back Timestamp objects, but a document written by an older
 * client (or a test fixture) may carry a Date or a raw number instead. Coerce
 * all three; anything else becomes null rather than NaN, so the UI can render
 * an honest em-dash instead of "Invalid Date".
 */
export function toMillis(value: unknown): number | null {
  if (value == null) return null;

  if (typeof (value as TimestampLike)?.toMillis === 'function') {
    return (value as TimestampLike).toMillis();
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.getTime();
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  return null;
}

/**
 * Everything the detail page shows that the list does not. Kept as a separate
 * shape so the list query never carries fields it will not render.
 */
export interface UserDetailRow extends UserListRow {
  photoUrl: string | null;
  monthlyIncome: number | null;
  financialHealthScore: number | null;
  setupCompletedAtMs: number | null;
  updatedAtMs: number | null;
}

export function toUserRow(
  uid: string,
  data: Partial<UserDocument> | undefined,
): UserListRow {
  return {
    uid,
    email: data?.email ?? null,
    displayName: data?.displayName ?? null,
    defaultCurrency: data?.defaultCurrency ?? null,
    premiumStatus: data?.premiumStatus ?? null,
    premiumExpiryMs: toMillis(data?.premiumExpiry),
    createdAtMs: toMillis(data?.createdAt),
    lastSyncAtMs: toMillis(data?.lastSyncAt),
  };
}

export function toUserDetailRow(
  uid: string,
  data: Partial<UserDocument> | undefined,
): UserDetailRow {
  return {
    ...toUserRow(uid, data),
    photoUrl: data?.photoUrl ?? null,
    monthlyIncome: data?.monthlyIncome ?? null,
    financialHealthScore: data?.financialHealthScore ?? null,
    setupCompletedAtMs: toMillis(data?.setupCompletedAt),
    updatedAtMs: toMillis(data?.updatedAt),
  };
}

/**
 * Whether a user is entitled to premium RIGHT NOW.
 *
 * Deliberately mirrors the server's `evaluateQuota` in
 * apps/functions/src/quota/quota_logic.ts: a `premiumStatus` of 'premium' with
 * a NULL `premiumExpiry` does NOT count as premium. The RevenueCat webhook
 * works around that by writing a +100-year timestamp for lifetime purchases.
 *
 * If the panel ever grants premium manually it must do the same — writing
 * `{ premiumStatus: 'premium' }` alone silently grants nothing.
 */
export function isPremiumNow(row: UserListRow, nowMs: number): boolean {
  return (
    row.premiumStatus === 'premium' &&
    row.premiumExpiryMs != null &&
    row.premiumExpiryMs > nowMs
  );
}

/**
 * Flags a user whose stored entitlement disagrees with the live one — either
 * marked premium but expired, or marked free while an unexpired expiry sits on
 * the document. Both mean the Firestore mirror has drifted from RevenueCat.
 */
export function entitlementDrift(
  row: UserListRow,
  nowMs: number,
): 'expired-but-marked-premium' | 'free-but-has-future-expiry' | null {
  const hasFutureExpiry = row.premiumExpiryMs != null && row.premiumExpiryMs > nowMs;

  if (row.premiumStatus === 'premium' && !hasFutureExpiry) {
    return 'expired-but-marked-premium';
  }
  if (row.premiumStatus === 'free' && hasFutureExpiry) {
    return 'free-but-has-future-expiry';
  }
  return null;
}

/**
 * `fx` is the one counter the free-tier Remote Config ceiling does not govern —
 * getFxRate hardcodes its own monthly cap (CLAUDE.md §7). Duplicated here
 * because there is no key to read it from; if the callable's constant changes,
 * change this too.
 */
export const FX_MONTHLY_CEILING = 1000;

/**
 * The AI calls that count against `free_tier_ai_quota`. Excludes `fx` (own
 * ceiling), `premiumCalls` (analytics, no ceiling), and `rejected` (denials,
 * not usage) — summing those in would overstate how close a user is to being
 * blocked, which is the whole question this number answers.
 */
export function quotaCountedTotal(
  usage: AiUsageDocument | null | undefined,
): number {
  if (!usage) return 0;

  let total = 0;
  for (const field of QUOTA_COUNTED_FIELDS) {
    const value = usage[field];
    if (typeof value === 'number' && Number.isFinite(value)) total += value;
  }
  return total;
}

/**
 * Start of the current UTC month.
 *
 * UTC, not local, so this lines up with the `YYYY-MM` aiUsage document ids —
 * which `yearMonth()` also derives in UTC. Note the mobile client enforces its
 * own monthly transaction ceiling against the DEVICE's local month, so near a
 * boundary the panel's count can differ from what the app counted.
 */
export function startOfMonthUtc(nowMs: number): number {
  const d = new Date(nowMs);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1);
}

/**
 * Recognises Firestore's "this query needs a composite index" failure.
 *
 * A fresh buyer project that has not run `firebase deploy --only
 * firestore:indexes` will throw this for the premium filter — the only
 * composite query in the panel. Left uncaught it renders as a 500, which reads
 * as "the admin panel is broken" rather than "deploy your indexes", so callers
 * translate it into that instruction instead.
 *
 * FAILED_PRECONDITION also covers an index that exists but is still building;
 * both resolve the same way from the operator's side.
 */
export function isMissingIndexError(error: unknown): boolean {
  if (error == null || typeof error !== 'object') return false;

  const code = (error as { code?: unknown }).code;
  // gRPC surfaces FAILED_PRECONDITION as 9; the REST transport uses the name.
  const failedPrecondition =
    code === 9 ||
    (typeof code === 'string' && code.toLowerCase() === 'failed-precondition');
  if (!failedPrecondition) return false;

  const message = String((error as { message?: unknown }).message ?? '');
  return /index/i.test(message);
}
