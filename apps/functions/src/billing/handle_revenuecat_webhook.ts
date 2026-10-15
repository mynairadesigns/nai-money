import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';

import { REGION } from '../utils/region';

if (!admin.apps.length) {
  admin.initializeApp();
}

const REVENUECAT_WEBHOOK_SECRET = defineSecret('REVENUECAT_WEBHOOK_SECRET');

/**
 * RevenueCat → Firestore webhook. Sets `users/{uid}.premiumStatus` and
 * `premiumExpiry` based on the event type. Server-authoritative entitlement
 * source — the client may also write these fields for fast UX, but the
 * webhook is the eventually-consistent source of truth.
 *
 * Auth: `Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>`. 401 on miss.
 * Returns 200 even on unknown events so RevenueCat doesn't retry forever.
 *
 * Secret setup (run once per Firebase project):
 *   firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
 */
export const handleRevenueCatWebhook = onRequest(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    secrets: [REVENUECAT_WEBHOOK_SECRET],
  },
  async (req, res) => {
    // 1. Validate bearer auth.
    const auth = req.header('authorization') ?? '';
    const expected = `Bearer ${process.env.REVENUECAT_WEBHOOK_SECRET ?? ''}`;
    if (auth !== expected) {
      console.warn('RevenueCat webhook: invalid bearer');
      res.status(401).send('unauthorized');
      return;
    }

    // 2. Parse event.
    const body = (req.body ?? {}) as Record<string, unknown>;
    const event = body.event as Record<string, unknown> | undefined;
    if (!event || typeof event !== 'object') {
      console.warn('RevenueCat webhook: missing event');
      res.status(200).send('ignored: no event'); // 200 so they don't retry
      return;
    }

    const type = String(event.type ?? '');
    const uid = String(event.app_user_id ?? '');
    if (!uid) {
      console.warn('RevenueCat webhook: missing app_user_id', type);
      res.status(200).send('ignored: no uid');
      return;
    }

    // 3. Map event → Firestore update.
    const userRef = admin.firestore().doc(`users/${uid}`);
    const expirationMs =
      typeof event.expiration_at_ms === 'number' ? event.expiration_at_ms : null;
    const productId =
      typeof event.product_id === 'string' ? event.product_id : null;

    const grantEvents = new Set([
      'INITIAL_PURCHASE',
      'RENEWAL',
      'PRODUCT_CHANGE',
      'UNCANCELLATION',
      'NON_RENEWING_PURCHASE',
    ]);
    const revokeEvents = new Set([
      'EXPIRATION',
      'CANCELLATION',
      'BILLING_ISSUE',
    ]);

    // `handled` flips to true only once the entitlement write has committed,
    // so the log distinguishes "we acted on it" from "we saw it".
    let handled = false;
    let responseCode = 200;
    let responseBody = 'ok';

    try {
      if (grantEvents.has(type)) {
        // For lifetime purchases (NON_RENEWING_PURCHASE) expirationMs may
        // be null — treat as ~100 years out.
        const expiry = expirationMs
          ? admin.firestore.Timestamp.fromMillis(expirationMs)
          : admin.firestore.Timestamp.fromMillis(
              Date.now() + 100 * 365 * 24 * 60 * 60 * 1000,
            );
        await userRef.set(
          {
            premiumStatus: 'premium',
            premiumExpiry: expiry,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        handled = true;
        console.log(`RevenueCat: granted premium to ${uid} (${type})`);
      } else if (revokeEvents.has(type)) {
        await userRef.set(
          {
            premiumStatus: 'free',
            premiumExpiry: null,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        handled = true;
        console.log(`RevenueCat: revoked premium from ${uid} (${type})`);
      } else {
        console.log(`RevenueCat: ignoring event ${type} for ${uid}`);
      }
    } catch (e) {
      console.error('RevenueCat webhook: firestore write failed', e);
      responseCode = 500;
      responseBody = 'internal';
    }

    // Audit trail BEFORE responding: Cloud Run may throttle CPU once the
    // response is flushed, so a write started after `res.send()` can be
    // dropped. `_logEvent` never throws, so it cannot turn a successful
    // entitlement update into a retry-triggering 500.
    await _logEvent({ type, uid, productId, expirationMs, handled });

    res.status(responseCode).send(responseBody);
  },
);

/**
 * Appends one `revenueCatEvents/{autoId}` doc — the billing audit trail the
 * admin panel reads when a user disputes their entitlement state.
 *
 * **Best-effort by design.** RevenueCat retries any non-2xx response, so a
 * failed log write must never turn a successful entitlement update into a
 * retry: that would re-run the grant/revoke and append a duplicate. Errors
 * are logged and swallowed; this function never throws.
 *
 * **Operator action required:** this collection grows one doc per webhook
 * forever. Firestore TTL policies cannot be declared in
 * `firestore.indexes.json`, so set one by hand in the Firebase console
 * (Firestore → TTL) on collection `revenueCatEvents`, field `receivedAt`,
 * with a 90-day expiry, and the collection self-prunes.
 */
async function _logEvent(entry: {
  type: string;
  uid: string;
  productId: string | null;
  expirationMs: number | null;
  handled: boolean;
}): Promise<void> {
  try {
    const doc: Record<string, unknown> = {
      type: entry.type,
      appUserId: entry.uid,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
      handled: entry.handled,
    };
    if (entry.productId !== null) doc.productId = entry.productId;
    if (entry.expirationMs !== null) doc.expiresAtMs = entry.expirationMs;

    await admin.firestore().collection('revenueCatEvents').add(doc);
  } catch (e) {
    console.error('RevenueCat webhook: event log write failed (ignored)', e);
  }
}
