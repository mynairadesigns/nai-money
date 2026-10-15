import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'subscription_candidate.dart';

/// Wraps the two subscription callables (P5.3 spec).
///
/// `detectSubscriptions` is a no-LLM, no-quota heuristic over the user's
/// transactions — returns possible recurring payments. `confirmSubscription`
/// creates a server-side `recurringRules` doc; the next pull-direction sync
/// hydrates it into Drift on the client.
class SubscriptionsService {
  SubscriptionsService(this._functions);
  final FirebaseFunctions _functions;

  Future<List<SubscriptionCandidate>> detect() async {
    final callable = _functions.httpsCallable('detectSubscriptions');
    final result = await callable.call<Map<dynamic, dynamic>>();
    final raw = (result.data['candidates'] as List?) ?? const [];
    return [
      for (final c in raw)
        SubscriptionCandidate.fromMap((c as Map).cast<dynamic, dynamic>()),
    ];
  }

  /// Returns the new recurringRuleId. The recurring rule itself lands in
  /// Drift on the next pull-direction sync (CLAUDE.md §8); callers should
  /// not write it locally.
  Future<String> confirm({
    required String candidateId,
    required String merchant,
    required double amount,
    required String currency,
    required String frequency,
    required String walletId,
    required String categoryId,
    required DateTime startDate,
  }) async {
    final callable = _functions.httpsCallable('confirmSubscription');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'candidateId': candidateId,
      'merchant': merchant,
      'amount': amount,
      'currency': currency,
      'frequency': frequency,
      'walletId': walletId,
      'categoryId': categoryId,
      'startDate': startDate.toIso8601String(),
    });
    return result.data['recurringRuleId'] as String? ?? '';
  }
}

final subscriptionsFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
);

final subscriptionsServiceProvider = Provider<SubscriptionsService>(
  (ref) => SubscriptionsService(ref.watch(subscriptionsFunctionsProvider)),
);
