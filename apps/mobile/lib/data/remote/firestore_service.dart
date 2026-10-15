import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around Firestore writes that don't belong to a specific
/// feature repository — currently just the post-auth `users/{uid}` seed.
///
/// Keep the field set here in sync with the server-side trigger at
/// `apps/functions/src/auth/on_user_create.ts`. Both writes are idempotent
/// (`SetOptions(merge: true)`), so the race between trigger and client is a no-op.
class FirestoreService {
  FirestoreService(this._firestore);

  final FirebaseFirestore _firestore;

  /// Seeds `users/{uid}` on first sign-in. Called from `AuthController` on
  /// sign-up (email) and on first-time social sign-in (Google, Apple).
  /// Safe to call on returning users — `merge: true` won't overwrite fields
  /// the user has since edited via `/setup` or settings.
  Future<void> seedUserDocument({
    required String uid,
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _firestore.doc('users/$uid').set(
      {
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'defaultCurrency': 'USD',
        'monthlyIncome': null,
        // premiumStatus / premiumExpiry are seeded server-side by the
        // `onUserCreate` trigger and are write-protected in firestore.rules.
        // (Writing 'free' here also used to reset returning premium users.)
        'financialHealthScore': null,
        'createdAt': now,
        'lastSyncAt': now,
      },
      SetOptions(merge: true),
    );
  }

  /// Persists the choices made in the initial setup wizard (PRD §6.1).
  /// Stamps `setupCompletedAt` so future cold starts can route signed-in
  /// users straight to `/home` without re-running the wizard.
  Future<void> updateUserSetup({
    required String uid,
    required String defaultCurrency,
    required double? monthlyIncome,
  }) async {
    final now = FieldValue.serverTimestamp();
    await _firestore.doc('users/$uid').set(
      {
        'defaultCurrency': defaultCurrency,
        'monthlyIncome': monthlyIncome,
        'setupCompletedAt': now,
        'lastSyncAt': now,
      },
      SetOptions(merge: true),
    );
  }
}
