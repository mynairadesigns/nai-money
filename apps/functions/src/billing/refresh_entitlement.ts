import * as admin from 'firebase-admin';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION } from '../utils/region';

if (!admin.apps.length) {
  admin.initializeApp();
}

const REVENUECAT_API_KEY = defineSecret('REVENUECAT_API_KEY');

interface RevenueCatSubscriberResponse {
  subscriber?: {
    entitlements?: Record<string, { expires_date?: string | null }>;
  };
}

interface RefreshEntitlementResponse {
  isPremium: boolean;
  expiryMs: number | null;
}

/**
 * Client-triggered fallback for webhook lag. Used when the client knows
 * it just purchased but Firestore hasn't reflected the entitlement yet.
 *
 * Fetches the subscriber's entitlements from RevenueCat REST API and
 * mirrors them to Firestore. Idempotent.
 *
 * Endpoint: GET https://api.revenuecat.com/v1/subscribers/{app_user_id}
 *   Authorization: Bearer <REVENUECAT_API_KEY>
 *
 * Response shape (subset we care about):
 *   { subscriber: { entitlements: { premium: { expires_date: "2026-..." } } } }
 *
 * Secret setup (run once per Firebase project):
 *   firebase functions:secrets:set REVENUECAT_API_KEY
 */
export const refreshEntitlement = onCall(
  {
    region: REGION,
    memory: '256MiB',
    timeoutSeconds: 30,
    secrets: [REVENUECAT_API_KEY],
  },
  async (request): Promise<RefreshEntitlementResponse> => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }
    const uid = request.auth.uid;
    const apiKey = process.env.REVENUECAT_API_KEY ?? '';
    if (!apiKey) {
      throw new HttpsError('failed-precondition', 'RevenueCat not configured');
    }

    let isPremium = false;
    let expiryMs: number | null = null;
    try {
      const resp = await fetch(
        `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
        {
          method: 'GET',
          headers: { Authorization: `Bearer ${apiKey}` },
        },
      );
      if (!resp.ok) {
        // 404 = no subscriber record = definitely free; fall through to
        // write the `free` mirror. Any other status is an error.
        if (resp.status !== 404) {
          throw new HttpsError(
            'internal',
            `RevenueCat API returned ${resp.status}`,
          );
        }
      } else {
        const data = (await resp.json()) as RevenueCatSubscriberResponse;
        const ent = data.subscriber?.entitlements?.premium;
        if (ent) {
          const expires = ent.expires_date
            ? Date.parse(ent.expires_date)
            : Date.now() + 100 * 365 * 24 * 60 * 60 * 1000;
          if (expires > Date.now()) {
            isPremium = true;
            expiryMs = expires;
          }
        }
      }
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error('refreshEntitlement: RC API failed', e);
      throw new HttpsError('internal', 'Could not refresh entitlement');
    }

    await admin.firestore().doc(`users/${uid}`).set(
      {
        premiumStatus: isPremium ? 'premium' : 'free',
        premiumExpiry:
          isPremium && expiryMs
            ? admin.firestore.Timestamp.fromMillis(expiryMs)
            : null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { isPremium, expiryMs };
  },
);
