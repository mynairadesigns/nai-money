import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'savings_plan_result.dart';

/// Thin wrapper over the `generateSavingsPlan` callable (P5.3 spec).
class SavingsCoachService {
  SavingsCoachService(this._functions);
  final FirebaseFunctions _functions;

  Future<SavingsPlanResult> plan({required String goalId}) async {
    final callable = _functions.httpsCallable('generateSavingsPlan');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'goalId': goalId,
    });
    return SavingsPlanResult.fromMap(result.data);
  }
}

final savingsCoachFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
);

final savingsCoachServiceProvider = Provider<SavingsCoachService>(
  (ref) => SavingsCoachService(ref.watch(savingsCoachFunctionsProvider)),
);
