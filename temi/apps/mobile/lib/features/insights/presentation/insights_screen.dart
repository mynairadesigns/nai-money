import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../providers/insights_providers.dart';
import '../widgets/anomalies_card.dart';
import '../widgets/forecast_card.dart';

/// Full-screen AI insights drill-down reached from the AI Coach tab
/// (PRD §11.5). Reuses the same self-contained [ForecastCard] +
/// [AnomaliesCard] used on Home — each streams its own AsyncValue and
/// renders nothing on error/null.
///
/// Those cards shrink to nothing when empty, which is fine inline on Home
/// but would leave this dedicated screen blank — so we watch the same
/// providers and show a friendly explanation when both resolve empty.
class AIInsightsScreen extends ConsumerWidget {
  const AIInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(forecastProvider);
    final anomalies = ref.watch(anomaliesProvider);

    // Both calls have returned, and both came back empty (no data, offline,
    // or quota exhausted — the providers swallow errors into null).
    final bothEmpty = forecast.hasValue &&
        forecast.value == null &&
        anomalies.hasValue &&
        anomalies.value == null;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Insights')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const ForecastCard(),
            const SizedBox(height: AppSpacing.md),
            const AnomaliesCard(),
            if (bothEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const _EmptyState(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shown when neither the forecast nor the anomaly scan has anything to
/// report — guides the user toward the data that makes insights work.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(
            Icons.insights_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No insights yet',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add a few transactions and we’ll forecast where your month '
            'lands and flag anything unusual. Insights need a connection.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
