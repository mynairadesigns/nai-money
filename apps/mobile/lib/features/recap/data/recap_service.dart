import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recap_result.dart';

/// Thin wrapper over the `generateWeeklyRecap` callable. Auth + quota
/// + rate-limit live on the server (CLAUDE.md §7).
class RecapService {
  RecapService(this._functions);
  final FirebaseFunctions _functions;

  Future<WeeklyRecapResult> recap({DateTime? weekStart}) async {
    final callable = _functions.httpsCallable('generateWeeklyRecap');
    final result = await callable.call<Map<dynamic, dynamic>>({
      if (weekStart != null) 'weekStart': weekStart.toIso8601String(),
    });
    return WeeklyRecapResult.fromMap(result.data);
  }
}

/// Pinned to `asia-southeast1` to match Functions deployment region
/// (CLAUDE.md §7). Duplicated per service file by design — keeps each
/// AI module independent.
final recapFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
);

final recapServiceProvider = Provider<RecapService>(
  (ref) => RecapService(ref.watch(recapFunctionsProvider)),
);
