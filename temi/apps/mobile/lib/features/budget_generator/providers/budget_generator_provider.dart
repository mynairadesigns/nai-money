import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/budget_generator_service.dart';
import '../data/budget_plan_result.dart';

/// One-shot AI budget plan fetch. The sheet rebuilds against this so the
/// suggestion list lands as soon as the callable returns.
final budgetPlanProvider = FutureProvider.autoDispose<BudgetPlanResult>(
  (ref) async {
    final service = ref.watch(budgetGeneratorServiceProvider);
    return service.generate();
  },
);
