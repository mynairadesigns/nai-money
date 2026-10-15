import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../data/anomalies_result.dart';
import '../providers/insights_providers.dart';

/// Anomalies card — surfaces unusual spending events (PRD §7.5 / §11.5).
///
/// Quiet empty state when no anomalies; otherwise lists the top 3 with
/// severity dots + amount aligned right.
class AnomaliesCard extends ConsumerWidget {
  const AnomaliesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(anomaliesProvider);
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
  final AnomaliesResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (result.anomalies.isEmpty) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  result.summary.isNotEmpty
                      ? result.summary
                      : 'No unusual activity this week.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final top = result.anomalies.take(3).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unusual activity',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _AnomalyRow(item: top[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnomalyRow extends StatelessWidget {
  const _AnomalyRow({required this.item});
  final AnomalyItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        // Reserved: navigate to the underlying transaction once a
        // filtered-transactions route is available.
      },
      borderRadius: AppBorderRadius.base,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _severityColor(theme, item.severity),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                item.summary.isNotEmpty
                    ? item.summary
                    : item.categoryName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${item.currency} ${item.amount.toStringAsFixed(0)}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(ThemeData theme, AnomalySeverity s) {
    switch (s) {
      case AnomalySeverity.low:
        return theme.colorScheme.secondary;
      case AnomalySeverity.medium:
        return theme.colorScheme.tertiary;
      case AnomalySeverity.high:
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
