/**
 * Structural type for a Firestore Timestamp. Matches both the admin SDK's
 * `firebase-admin/firestore` Timestamp and the client SDK's Timestamp.
 */
export interface FirestoreTimestamp {
  toDate(): Date;
  toMillis(): number;
}

/**
 * Shape of the `users/{uid}` document per PRD §5.2.
 *
 * Mirrored in TWO other places — keep all three in sync when adding a field:
 *   - `apps/mobile/lib/data/remote/firestore_service.dart` (Dart, can't share TS)
 *   - `apps/admin/src/lib/types/user-document.ts` (see the note there on why
 *     the admin panel copies rather than imports this)
 *
 * The seed lives in `../auth/on_user_create.ts` and is duplicated defensively
 * by `FirestoreService.seedUserDocument` on the client; both use `merge: true`.
 */
export interface UserDocument {
  email: string;
  displayName: string | null;
  photoUrl: string | null;
  defaultCurrency: string;
  monthlyIncome: number | null;
  premiumStatus: 'free' | 'premium';
  premiumExpiry: FirestoreTimestamp | null;
  financialHealthScore: number | null;
  createdAt: FirestoreTimestamp;
  lastSyncAt: FirestoreTimestamp;

  /**
   * Written by the entitlement writers (`billing/handle_revenuecat_webhook.ts`,
   * `billing/refresh_entitlement.ts`) — not part of the initial seed, so it is
   * absent on users who have never had a subscription event.
   */
  updatedAt?: FirestoreTimestamp;

  /**
   * Stamped by the mobile client once onboarding completes
   * (`FirestoreService.updateUserSetup`). Absent until then.
   */
  setupCompletedAt?: FirestoreTimestamp;
}
