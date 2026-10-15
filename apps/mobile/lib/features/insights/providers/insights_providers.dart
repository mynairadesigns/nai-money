import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/anomalies_result.dart';
import '../data/forecast_result.dart';
import '../data/health_score_result.dart';
import '../data/insights_service.dart';

/// Home dashboard insights — one async cache per card.
///
/// All three swallow errors and resolve to `null` instead of throwing —
/// the card widgets read that as "render nothing" so a failed call
/// (network, quota exhausted, server hiccup) quietly drops the card
/// rather than splattering an error UI across Home.
///
/// Each one fires on first read of the Home screen and consumes 1 quota
/// call per cold start. Acceptable for v1; can add caching / staleness
/// guards later.

final forecastProvider = FutureProvider.autoDispose<ForecastResult?>(
  (ref) async {
    try {
      return await ref.read(insightsServiceProvider).forecast();
    } catch (_) {
      return null;
    }
  },
);

final anomaliesProvider = FutureProvider.autoDispose<AnomaliesResult?>(
  (ref) async {
    try {
      return await ref.read(insightsServiceProvider).anomalies();
    } catch (_) {
      return null;
    }
  },
);

final healthScoreProvider = FutureProvider.autoDispose<HealthScoreResult?>(
  (ref) async {
    try {
      return await ref.read(insightsServiceProvider).healthScore();
    } catch (_) {
      return null;
    }
  },
);
