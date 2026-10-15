import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../data/remote/billing_service.dart';

/// Internal: live user-doc snapshot. Used to read the server-mirrored
/// `premiumStatus` + `premiumExpiry` fields that the RevenueCat webhook
/// (and our local mirror in [BillingService]) write.
final userDocProvider = StreamProvider.family<Map<String, dynamic>?, String>(
  (ref, uid) {
    return ref
        .watch(firestoreProvider)
        .doc('users/$uid')
        .snapshots()
        .map((snap) => snap.data());
  },
);

/// Combined premium signal: RevenueCat entitlement (local fast path)
/// AND/OR Firestore `users/{uid}.premiumStatus` (server-authoritative,
/// updated by the webhook). Either says premium → premium.
///
/// This is the single source of truth read by feature code to gate
/// paywalled functionality. Don't read [customerInfoProvider] directly
/// from features — it skips the Firestore fallback that handles the
/// "user purchased on another device" case.
final isPremiumProvider = Provider<bool>((ref) {
  // Local entitlement (RevenueCat SDK).
  final info = ref.watch(customerInfoProvider).value;
  if (info != null && ref.read(billingServiceProvider).isPremium(info)) {
    return true;
  }

  // Firestore mirror (server-authoritative).
  final user = ref.watch(authStateProvider).value;
  if (user == null) return false;
  final userDoc = ref.watch(userDocProvider(user.uid)).value;
  final status = userDoc?['premiumStatus'] as String? ?? 'free';
  final expiry = userDoc?['premiumExpiry'] as Timestamp?;
  if (status != 'premium') return false;
  if (expiry == null) return true; // Lifetime.
  return expiry.toDate().isAfter(DateTime.now());
});

/// The next renewal / expiration date for the current premium
/// entitlement, if any. `null` for free users AND for lifetime
/// purchases (no expiry). Subscription UI uses this to render
/// "Renews on …" copy, or "Lifetime access" when null + premium.
final premiumExpiryProvider = Provider<DateTime?>((ref) {
  final info = ref.watch(customerInfoProvider).value;
  final ent = info?.entitlements.active['premium'];
  if (ent?.expirationDate != null) {
    return DateTime.tryParse(ent!.expirationDate!);
  }

  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final userDoc = ref.watch(userDocProvider(user.uid)).value;
  final expiry = userDoc?['premiumExpiry'] as Timestamp?;
  return expiry?.toDate();
});
