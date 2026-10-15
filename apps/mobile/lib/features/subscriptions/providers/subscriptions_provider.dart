import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/subscription_candidate.dart';
import '../data/subscriptions_service.dart';

/// All detected subscription candidates. Auto-disposes so each visit to
/// the screen re-runs the heuristic. After a successful `confirm` the
/// caller invalidates this provider to drop the row from the list.
final subscriptionCandidatesProvider =
    FutureProvider.autoDispose<List<SubscriptionCandidate>>(
  (ref) async {
    final service = ref.watch(subscriptionsServiceProvider);
    return service.detect();
  },
);

/// Cheap derived count for the Settings banner — depends on the same
/// underlying call so we don't double-fetch.
final subscriptionsCountProvider = FutureProvider.autoDispose<int>(
  (ref) async {
    final list = await ref.watch(subscriptionCandidatesProvider.future);
    return list.length;
  },
);
