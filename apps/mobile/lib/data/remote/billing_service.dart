import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/providers/firestore_provider.dart';

/// Thin wrapper over the RevenueCat (`purchases_flutter`) SDK. Owns SDK
/// init, user identification, fetching offerings, purchase + restore
/// flows, and mirroring entitlement state to Firestore so the
/// server-side AI quota bypass picks up changes immediately (the
/// RevenueCat → Firebase webhook is the slower authoritative path).
///
/// Initialization is **deferred to post-auth** — RevenueCat needs the
/// signed-in uid + the Remote-Config-driven API key, neither of which
/// is available at cold start. See `syncLifecycleProvider` for the
/// actual `configure(...)` + `identify(...)` calls.
class BillingService {
  BillingService(this._firestore);
  // Kept for API compatibility (tests / provider wiring); entitlement
  // writes now go through the `refreshEntitlement` callable.
  // ignore: unused_field
  final FirebaseFirestore _firestore;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> configure(String apiKey) async {
    if (_initialized) return;
    try {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _initialized = true;
    } catch (e) {
      debugPrint('BillingService.configure failed: $e');
    }
  }

  Future<void> identify(String uid) async {
    if (!_initialized) return;
    try {
      await Purchases.logIn(uid);
    } catch (e) {
      debugPrint('BillingService.identify failed: $e');
    }
  }

  Future<void> logOut() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      // RC throws if no user is identified — swallow.
      debugPrint('BillingService.logOut: $e');
    }
  }

  Future<Offerings?> getOfferings() async {
    if (!_initialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('BillingService.getOfferings failed: $e');
      return null;
    }
  }

  Future<CustomerInfo?> getCustomerInfo() async {
    if (!_initialized) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (_) {
      return null;
    }
  }

  /// Returns the new [CustomerInfo] on success. Mirrors entitlement to
  /// Firestore for the server-side quota bypass to pick up immediately
  /// (the webhook is the slower authoritative path).
  Future<CustomerInfo> purchasePackage(Package pkg) async {
    final result = await Purchases.purchase(PurchaseParams.package(pkg));
    await _mirrorToFirestore(result.customerInfo);
    return result.customerInfo;
  }

  Future<CustomerInfo> restorePurchases() async {
    final info = await Purchases.restorePurchases();
    await _mirrorToFirestore(info);
    return info;
  }

  /// True if the active "premium" entitlement is present AND not expired.
  /// Lifetime entitlements have a null `expirationDate` and resolve to
  /// true forever.
  bool isPremium(CustomerInfo? info) {
    final ent = info?.entitlements.active['premium'];
    if (ent == null) return false;
    final expiresDate = ent.expirationDate; // ISO String?
    if (expiresDate == null) return true;
    return DateTime.tryParse(expiresDate)?.isAfter(DateTime.now()) ?? false;
  }

  /// Asks the server to re-read the entitlement from RevenueCat and write
  /// `users/{uid}.premiumStatus` itself. The client can no longer write
  /// those fields directly (firestore.rules protects them — otherwise any
  /// user could grant themselves premium).
  Future<void> _mirrorToFirestore(CustomerInfo info) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (kDebugMode) {
      // Diagnostic: if a purchase succeeds but premium stays free, the
      // granted entitlement isn't named exactly `premium` (or no product is
      // attached to it).
      debugPrint(
        'BillingService mirror: active=${info.entitlements.active.keys.toList()} '
        'all=${info.entitlements.all.keys.toList()}',
      );
    }
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('refreshEntitlement')
          .call<Map<dynamic, dynamic>>();
    } catch (e) {
      // Best-effort — the RevenueCat webhook is the authoritative path and
      // the local RC entitlement already unlocks premium in the UI.
      debugPrint('BillingService._mirrorToFirestore (refreshEntitlement) failed: $e');
    }
  }
}

final billingServiceProvider = Provider<BillingService>((ref) {
  return BillingService(ref.watch(firestoreProvider));
});

/// Live [CustomerInfo] stream from the RevenueCat SDK. Re-emits when
/// CustomerInfo changes (purchases, restores, expirations).
///
/// First yields the initial poll (which may be null if RC isn't
/// configured yet); subsequent emissions come from RC's listener.
final customerInfoProvider = StreamProvider<CustomerInfo?>((ref) async* {
  // Web has no app-store billing — premium comes from the Firestore mirror
  // written by the Paystack functions (see isPremiumProvider).
  if (kIsWeb) {
    yield null;
    return;
  }
  final billing = ref.watch(billingServiceProvider);
  final initial = await billing.getCustomerInfo();
  yield initial;

  final controller = StreamController<CustomerInfo>();
  void listener(CustomerInfo info) {
    if (!controller.isClosed) controller.add(info);
  }

  Purchases.addCustomerInfoUpdateListener(listener);
  ref.onDispose(() {
    Purchases.removeCustomerInfoUpdateListener(listener);
    controller.close();
  });

  yield* controller.stream;
});
