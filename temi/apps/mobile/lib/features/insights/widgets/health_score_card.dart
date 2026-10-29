import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../data/health_score_result.dart';
import '../providers/insights_providers.dart';

/// Financial health score card (PRD §7.8 / §11.5).
///
/// Circular progress + score number + label + top 2 actionable tips.
class HealthScoreCard extends ConsumerWidget {
  const HealthScoreCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(healthScoreProvider);
    return async.when(
      loading: () => const _Skeleton(),
      error: (_, _) => const SizedBox.shrink(),
      data: (result) {
        if (result == null) return const SizedBox.shrink();
        return _Body(result: result);
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.result});
  final HealthScoreResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = _labelColor(theme, result.label);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Reserved: navigate to a future Health-score detail screen.
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                            value: (result.score / 100).clamp(0.0, 1.0),
                            strokeWidth: 6,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(labelColor),
                          ),
                        ),
                        Text(
                          '${result.score}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Financial health',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          result.label.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: labelColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (result.actionableTips.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final tip in result.actionableTips.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.tips_and_updates_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            tip,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _labelColor(ThemeData theme, HealthScoreLabel label) {
    switch (label) {
      case HealthScoreLabel.excellent:
      case HealthScoreLabel.good:
        return theme.colorScheme.secondary;
      case HealthScoreLabel.fair:
        return theme.colorScheme.tertiary;
      case HealthScoreLabel.poor:
        return theme.colorScheme.error;
    }
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 96,
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppBorderRadius.lg,
          ),
        ),
      ),
    );
  }
}
