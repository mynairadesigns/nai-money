import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';

import type { UserDocument } from '../types/user_document';
import { REGION } from '../utils/region';

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Fires once per Firebase Auth user creation (email/password, Google, Apple).
 * Seeds the `users/{uid}` document per PRD §5.2. The mobile client also
 * writes the same shape defensively with `merge: true`, so this trigger
 * is the safety net — not the only path.
 *
 * Note: PRD §8.1 does not list this function; it ships as infrastructure.
 * Keep the seed shape in sync with `FirestoreService.seedUserDocument` in
 * `apps/mobile/lib/data/remote/firestore_service.dart`.
 */
export const onUserCreate = functions
  .region(REGION)
  .auth.user()
  .onCreate(async (user) => {
    const now = admin.firestore.FieldValue.serverTimestamp();
    const seed: Partial<UserDocument> = {
      email: user.email ?? '',
      displayName: user.displayName ?? null,
      photoUrl: user.photoURL ?? null,
      defaultCurrency: 'NGN',
      monthlyIncome: null,
      premiumStatus: 'free',
      premiumExpiry: null,
      financialHealthScore: null,
      createdAt: now as unknown as FirebaseFirestore.Timestamp,
      lastSyncAt: now as unknown as FirebaseFirestore.Timestamp,
    };

    await admin
      .firestore()
      .doc(`users/${user.uid}`)
      .set(seed, { merge: true });
  });
