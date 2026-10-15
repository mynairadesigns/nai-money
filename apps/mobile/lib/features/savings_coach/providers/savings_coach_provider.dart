import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/savings_coach_service.dart';
import '../data/savings_plan_result.dart';

/// One-shot AI savings plan fetch keyed by goal id. Auto-disposes per
/// sheet open so re-entry re-fetches a fresh plan.
final savingsPlanProvider =
    FutureProvider.autoDispose.family<SavingsPlanResult, String>(
  (ref, goalId) async {
    final service = ref.watch(savingsCoachServiceProvider);
    return service.plan(goalId: goalId);
  },
);
