import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'anomalies_result.dart';
import 'forecast_result.dart';
import 'health_score_result.dart';

/// Thin wrapper over the three Home insights callables:
/// `forecastSpending`, `detectAnomalies`, `computeHealthScore`.
///
/// Owns its own `FirebaseFunctions` provider (`insightsFunctionsProvider`)
/// — intentionally duplicates `aiFunctionsProvider` from
/// `data/remote/ai_service.dart` so the insights feature stays
/// self-contained. The integration pass may consolidate later.
class InsightsService {
  InsightsService(this._functions);
  final FirebaseFunctions _functions;

  Future<ForecastResult> forecast() async {
    return _invoke('forecastSpending', ForecastResult.fromMap);
  }

  Future<AnomaliesResult> anomalies() async {
    return _invoke('detectAnomalies', AnomaliesResult.fromMap);
  }

  Future<HealthScoreResult> healthScore() async {
    return _invoke('computeHealthScore', HealthScoreResult.fromMap);
  }

  Future<T> _invoke<T>(
    String name,
    T Function(Map<dynamic, dynamic>) parse,
  ) async {
    debugPrint('insights.$name: dispatching');
    try {
      final result =
          await _functions.httpsCallable(name).call<Map<dynamic, dynamic>>({});
      debugPrint('insights.$name: success');
      return parse(result.data);
    } catch (e, st) {
      debugPrint('insights.$name: threw $e');
      debugPrintStack(stackTrace: st, label: 'insights.$name');
      rethrow;
    }
  }
}

/// FirebaseFunctions instance pinned to Singapore (CLAUDE.md §7).
///
/// Duplicate of `aiFunctionsProvider` — kept independent so the insights
/// module doesn't import from `data/remote/ai_service.dart`.
final insightsFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
);

final insightsServiceProvider = Provider<InsightsService>(
  (ref) => InsightsService(ref.watch(insightsFunctionsProvider)),
);
