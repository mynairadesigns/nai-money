import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';

import { getRcNumber } from '../providers/select_provider';
import { evaluateQuota } from './quota_logic';

if (!admin.apps.length) admin.initializeApp();

/**
 * Atomically reads the current month's per-feature counter for [uid] and
 * increments it. Throws `HttpsError('resource-exhausted', ...)` if the
 * new value would exceed the free-tier ceiling.
 *
 * - Doc: `users/{uid}/aiUsage/{YYYY-MM}`.
 * - Field: [opts.field] (e.g. `categorize`, `scan`, `fx`).
 * - Limit: read from Remote Config `free_tier_ai_quota` (default 5).
 *
 * Premium bypass (P6): users whose `users/{uid}.premiumStatus == 'premium'`
 * and whose `premiumExpiry` is in the future skip the ceiling entirely. Their
 * usage is still tracked under a separate `premiumCalls` field (no ceiling,
 * never throws) for analytics. The user-doc read happens INSIDE the
 * transaction so the entitlement check is consistent with the counter write.
 *
 * Rejections are counted too, in a `rejected` field, so the admin panel can
 * see how often the free tier actually bites. That is why the transaction
 * *returns* the decision instead of throwing inside it: a transaction that
 * throws is rolled back, so a counter written next to the throw would never
 * commit. The throw happens after `runTransaction` resolves — caller-visible
 * behaviour (same error code, same message) is unchanged.
 */
export async function checkAndIncrementQuota(opts: {
  uid: string;
  field: string;
  /** Optional override; defaults to RC `free_tier_ai_quota` (else 5). */
  limitOverride?: number;
}): Promise<{ refund: () => Promise<void> }> {
  const { uid, field } = opts;
  const limit = opts.limitOverride ?? (await getRcNumber('free_tier_ai_quota', 5));
  const yearMonth = _yearMonth(new Date());
  const ref = admin.firestore().doc(`users/${uid}/aiUsage/${yearMonth}`);
  const userRef = admin.firestore().doc(`users/${uid}`);

  const decision = await admin.firestore().runTransaction(async (tx) => {
    const [snap, userSnap] = await Promise.all([tx.get(ref), tx.get(userRef)]);

    // Premium bypass — check entitlement BEFORE the ceiling.
    const userData = userSnap.exists ? userSnap.data() : undefined;
    const premiumStatus = userData?.premiumStatus as string | undefined;
    const premiumExpiry = userData?.premiumExpiry as
      | admin.firestore.Timestamp
      | null
      | undefined;

    // Convert Timestamp to millis (null means absent/null in Firestore).
    const premiumExpiryMs =
      premiumExpiry instanceof admin.firestore.Timestamp
        ? premiumExpiry.toMillis()
        : null;

    const current = (snap.exists ? (snap.data()?.[field] as number | undefined) : 0) ?? 0;
    const decision = evaluateQuota({
      premiumStatus,
      premiumExpiryMs,
      nowMs: Date.now(),
      currentCount: current,
      limit,
    });

    if (decision.action === 'bypass') {
      // Premium users bypass the ceiling entirely. Track the call for
      // analytics in a separate field (no ceiling, never throws).
      const currentPremium =
        (snap.exists ? (snap.data()?.premiumCalls as number | undefined) : 0) ?? 0;
      tx.set(ref, { premiumCalls: currentPremium + 1 }, { merge: true });
      return decision.action;
    }

    if (decision.action === 'reject') {
      // Count the denial; the caller throws once this commits.
      const currentRejected =
        (snap.exists ? (snap.data()?.rejected as number | undefined) : 0) ?? 0;
      tx.set(ref, { rejected: currentRejected + 1 }, { merge: true });
      return decision.action;
    }

    tx.set(ref, { [field]: current + 1 }, { merge: true });
    return decision.action;
  });

  if (decision === 'reject') {
    throw new HttpsError('resource-exhausted', 'AI quota reached for this month');
  }

  // Lets the caller hand the unit back when the AI provider fails, so
  // outages / misconfiguration don't burn the user's monthly allowance.
  const countedField = decision === 'bypass' ? 'premiumCalls' : field;
  return {
    refund: async () => {
      try {
        await ref.set(
          { [countedField]: admin.firestore.FieldValue.increment(-1) },
          { merge: true },
        );
      } catch (e) {
        console.warn('quota refund failed', e);
      }
    },
  };
}

function _yearMonth(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}
