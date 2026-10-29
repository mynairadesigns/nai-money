import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/onboarding_state_provider.dart';
import '../../../data/remote/paystack_billing_service.dart';

/// SharedPreferences (localStorage on web) key holding the reference of a
/// Paystack checkout that hasn't been verified yet. Written just before
/// redirecting to Paystack, and again by `main.dart` from the `?reference=`
/// Paystack appends when it sends the user back.
const kPaystackPendingRefKey = 'mm_paystack_pending_ref';

/// Prices for the web paywall, read live from the Paystack plans.
final paystackPricesProvider = FutureProvider.autoDispose<PaystackPrices>(
  (ref) async {
    return ref.read(paystackBillingServiceProvider).getPrices();
  },
  // Riverpod 3 retries failed providers forever by default, which left the
  // paywall spinning. Fail fast and show the "not available" card instead.
  retry: (_, _) => null,
);

enum PaystackReturnStatus { idle, verifying, success, pending, failed }

/// Verifies a pending Paystack checkout once the user is signed in again
/// after the redirect back from Paystack. Watched from `TemiApp` on
/// web only; the app shows a snackbar when the status changes.
///
/// Belt-and-braces: the `handlePaystackWebhook` function normally grants
/// premium within seconds and `isPremiumProvider` streams it in — this just
/// closes the gap if the webhook is slow or misconfigured.
class PaystackReturnHandler extends Notifier<PaystackReturnStatus> {
  bool _running = false;

  @override
  PaystackReturnStatus build() {
    if (!kIsWeb) return PaystackReturnStatus.idle;
    ref.listen(authStateProvider, (_, next) {
      if (next.value != null) {
        // Defer: state can't be modified while providers are building.
        scheduleMicrotask(_checkPending);
      }
    }, fireImmediately: true);
    return PaystackReturnStatus.idle;
  }

  Future<void> _checkPending() async {
    if (_running) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final reference = prefs.getString(kPaystackPendingRefKey);
    if (reference == null || reference.isEmpty) return;
    _running = true;
    state = PaystackReturnStatus.verifying;
    try {
      final ok = await ref.read(paystackBillingServiceProvider).verify(reference);
      // Paid → done. Not (yet) successful → the user abandoned checkout or
      // the bank is still processing; either way stop retrying on every
      // launch — the webhook will still grant premium if it goes through.
      await prefs.remove(kPaystackPendingRefKey);
      state = ok ? PaystackReturnStatus.success : PaystackReturnStatus.pending;
    } catch (e) {
      debugPrint('PaystackReturnHandler: verify failed: $e');
      // Keep the reference so the next launch retries.
      state = PaystackReturnStatus.failed;
    } finally {
      _running = false;
    }
  }
}

final paystackReturnHandlerProvider =
    NotifierProvider<PaystackReturnHandler, PaystackReturnStatus>(
  PaystackReturnHandler.new,
);
