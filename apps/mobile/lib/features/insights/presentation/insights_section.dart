import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../widgets/anomalies_card.dart';
import '../widgets/forecast_card.dart';
import '../widgets/health_score_card.dart';

/// Single Home dashboard import point for the P5.2 AI insights cluster
/// (PRD §11.5). Stacks: forecast → anomalies → health score, each card
/// streaming its own AsyncValue. Failed calls render nothing — so the
/// section quietly shrinks rather than splattering errors.
class InsightsSection extends ConsumerWidget {
  const InsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'AI insights',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const ForecastCard(),
        const SizedBox(height: AppSpacing.sm),
        const AnomaliesCard(),
        const SizedBox(height: AppSpacing.sm),
        const HealthScoreCard(),
      ],
    );
  }
}
