import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Web billing via Paystack. Thin client over the Paystack Cloud Functions
/// in `apps/functions/src/billing/paystack.ts` — the secret key never
/// leaves the server, and premium is granted server-side by writing
/// `users/{uid}.premiumStatus` (the same field RevenueCat uses), so
/// `isPremiumProvider` picks it up from its Firestore stream with no
/// extra wiring.
///
/// Flow:
///   1. [startCheckout] → Paystack hosted-checkout URL + reference.
///   2. The browser goes to Paystack (same tab).
///   3. Paystack redirects back to `callbackUrl?trxref=…&reference=…`.
///   4. `main.dart` captures `reference` → [PaystackReturnHandler] calls
///      [verify]. The webhook usually gets there first anyway.
enum PaystackPlan { monthly, yearly, lifetime }

class PaystackPrice {
  const PaystackPrice({required this.amount, required this.currency});

  /// Smallest currency unit (kobo for NGN).
  final int amount;
  final String currency;

  /// "₦4,500" style label. Drops the decimals when they're zero.
  String get label {
    final major = amount / 100;
    final whole = major == major.roundToDouble();
    final digits = whole ? major.toStringAsFixed(0) : major.toStringAsFixed(2);
    final parts = digits.split('.');
    final withCommas = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final symbol = switch (currency) {
      'NGN' => '₦',
      'GHS' => 'GH₵',
      'ZAR' => 'R',
      'KES' => 'KSh ',
      'USD' => r'$',
      _ => '$currency ',
    };
    return '$symbol$withCommas${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  static PaystackPrice? fromJson(Object? json) {
    if (json is! Map) return null;
    final amount = json['amount'];
    final currency = json['currency'];
    if (amount is! num || currency is! String) return null;
    return PaystackPrice(amount: amount.toInt(), currency: currency);
  }
}

class PaystackPrices {
  const PaystackPrices({this.monthly, this.yearly, this.lifetime});
  final PaystackPrice? monthly;
  final PaystackPrice? yearly;
  final PaystackPrice? lifetime;

  PaystackPrice? operator [](PaystackPlan plan) => switch (plan) {
        PaystackPlan.monthly => monthly,
        PaystackPlan.yearly => yearly,
        PaystackPlan.lifetime => lifetime,
      };

  bool get isEmpty => monthly == null && yearly == null && lifetime == null;
}

class PaystackBillingService {
  PaystackBillingService(this._functions);
  final FirebaseFunctions _functions;

  Future<PaystackPrices> getPrices() async {
    final res = await _functions
        .httpsCallable('getPaystackPrices')
        .call<Map<dynamic, dynamic>>();
    final d = res.data;
    return PaystackPrices(
      monthly: PaystackPrice.fromJson(d['monthly']),
      yearly: PaystackPrice.fromJson(d['yearly']),
      lifetime: PaystackPrice.fromJson(d['lifetime']),
    );
  }

  Future<({Uri authorizationUrl, String reference})> startCheckout({
    required PaystackPlan plan,
    required Uri callbackUrl,
  }) async {
    final res = await _functions
        .httpsCallable('startPaystackCheckout')
        .call<Map<dynamic, dynamic>>({
      'plan': plan.name,
      'callbackUrl': callbackUrl.toString(),
    });
    return (
      authorizationUrl: Uri.parse(res.data['authorizationUrl'] as String),
      reference: res.data['reference'] as String,
    );
  }

  /// Returns true when the payment succeeded and premium is now active.
  Future<bool> verify(String reference) async {
    final res = await _functions
        .httpsCallable('verifyPaystackPayment')
        .call<Map<dynamic, dynamic>>({'reference': reference});
    return res.data['isPremium'] == true;
  }

  /// Paystack-hosted page where the user can cancel or change card.
  /// Null when the user has no Paystack subscription (e.g. lifetime).
  Future<Uri?> manageLink() async {
    final res = await _functions
        .httpsCallable('getPaystackManageLink')
        .call<Map<dynamic, dynamic>>();
    final link = res.data['link'];
    return link is String && link.isNotEmpty ? Uri.parse(link) : null;
  }
}

final paystackBillingServiceProvider = Provider<PaystackBillingService>(
  (_) => PaystackBillingService(
    FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
  ),
);
