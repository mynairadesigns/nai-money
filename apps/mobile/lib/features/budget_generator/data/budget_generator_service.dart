import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budget_plan_result.dart';

/// Thin wrapper over the `generateBudgetPlan` callable (P5.3 spec).
class BudgetGeneratorService {
  BudgetGeneratorService(this._functions);
  final FirebaseFunctions _functions;

  Future<BudgetPlanResult> generate({
    double? monthlyIncome,
    String? currency,
  }) async {
    final callable = _functions.httpsCallable('generateBudgetPlan');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'monthlyIncome': ?monthlyIncome,
      'currency': ?currency,
    });
    return BudgetPlanResult.fromMap(result.data);
  }
}

final budgetGeneratorFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
);

final budgetGeneratorServiceProvider = Provider<BudgetGeneratorService>(
  (ref) => BudgetGeneratorService(
    ref.watch(budgetGeneratorFunctionsProvider),
  ),
);
