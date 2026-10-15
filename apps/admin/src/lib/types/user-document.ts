/**
 * MIRRORS: apps/functions/src/types/user_document.ts
 *
 * Deliberately copied rather than imported. A `workspace:*` dependency between
 * these two apps breaks `firebase deploy --only functions` — Firebase's cloud
 * `npm install` cannot resolve pnpm's workspace protocol (see CLAUDE.md §9).
 * Extracting a shared package is the eventual fix, but it needs TS project
 * references or `pnpm deploy --filter` first, and neither deploy path should be
 * put on unvalidated ground to save ~40 lines of declarations.
 *
 * If you change this file, change its counterpart in the same commit — and the
 * Dart mirror in apps/mobile/lib/data/remote/firestore_service.dart.
 */

/**
 * Structural type for a Firestore Timestamp. Matches both the admin SDK's
 * `firebase-admin/firestore` Timestamp and the client SDK's Timestamp.
 */
export interface FirestoreTimestamp {
  toDate(): Date;
  toMillis(): number;
}

/** Shape of the `users/{uid}` document per PRD §5.2. */
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

  /** Written by the entitlement writers; absent until a subscription event. */
  updatedAt?: FirestoreTimestamp;

  /** Stamped by the mobile client once onboarding completes. */
  setupCompletedAt?: FirestoreTimestamp;
}

/**
 * Counter document at `users/{uid}/aiUsage/{YYYY-MM}`.
 *
 * Written ONLY by Cloud Functions — `firestore.rules` denies client writes
 * outright. Every field is optional because the doc is built up with
 * `set(..., { merge: true })` as features are used.
 *
 * `premiumCalls` has no ceiling (premium users bypass the quota entirely and
 * are tracked here for analytics). `fx` has its own separate ceiling of
 * 1000/month, hardcoded in the getFxRate callable rather than Remote Config.
 */
export interface AiUsageDocument {
  categorize?: number;
  scan?: number;
  chat?: number;
  forecast?: number;
  anomalies?: number;
  healthScore?: number;
  recap?: number;
  budgetPlan?: number;
  savingsPlan?: number;
  premiumCalls?: number;
  fx?: number;
  /** Incremented when a call is refused for hitting the free-tier ceiling. */
  rejected?: number;
}

/** The AI counters that share the single `free_tier_ai_quota` ceiling. */
export const QUOTA_COUNTED_FIELDS = [
  'categorize',
  'scan',
  'chat',
  'forecast',
  'anomalies',
  'healthScore',
  'recap',
  'budgetPlan',
  'savingsPlan',
] as const;
