/**
 * Pure quota-decision logic — zero firebase imports.
 *
 * Extracted from `check_quota.ts` so the premium-bypass + ceiling evaluation
 * can be unit-tested without initialising firebase-admin or running a
 * Firestore transaction.
 */

/**
 * The three possible outcomes when evaluating a quota for a user action.
 *
 * - `bypass`    — user is premium (not expired), skip the ceiling, track
 *                 in premiumCalls for analytics (no ceiling, never throws).
 * - `increment` — user is free-tier and below the limit; allow and count.
 * - `reject`    — user is free-tier and at/above the ceiling; deny.
 */
export type QuotaDecision =
  | { action: 'bypass' }
  | { action: 'increment' }
  | { action: 'reject' };

/**
 * Evaluates whether the caller should be bypassed (premium), allowed
 * (increment), or blocked (reject).
 *
 * Premium detection mirrors `check_quota.ts` exactly:
 *  - `premiumStatus === 'premium'`
 *  - AND `premiumExpiryMs` is non-null (i.e. expiry Timestamp existed in
 *    Firestore — lifetime premium with null expiry does NOT bypass, matching
 *    the existing server behaviour which requires
 *    `premiumExpiry instanceof Timestamp`).
 *  - AND `premiumExpiryMs > nowMs` (not expired).
 *
 * Ceiling: free-tier users are rejected when `currentCount + 1 > limit`.
 */
export function evaluateQuota(args: {
  premiumStatus?: string;
  /** Milliseconds since epoch; null means expiry Timestamp was absent/null in Firestore. */
  premiumExpiryMs?: number | null;
  nowMs: number;
  currentCount: number;
  limit: number;
}): QuotaDecision {
  const { premiumStatus, premiumExpiryMs, nowMs, currentCount, limit } = args;

  const isPremium =
    premiumStatus === 'premium' &&
    premiumExpiryMs != null &&
    premiumExpiryMs > nowMs;

  if (isPremium) {
    return { action: 'bypass' };
  }

  if (currentCount + 1 > limit) {
    return { action: 'reject' };
  }

  return { action: 'increment' };
}
