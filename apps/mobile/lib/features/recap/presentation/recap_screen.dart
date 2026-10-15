import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../data/recap_result.dart';
import '../providers/recap_provider.dart';

/// Full-screen weekly recap — calls `generateWeeklyRecap` on mount and
/// renders the structured result (PRD §11.7-ish, P5.3 spec).
class RecapScreen extends ConsumerWidget {
  const RecapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(weeklyRecapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('This week')),
      body: async.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Crunching the numbers…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              "Couldn't load this week's recap.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        data: (recap) => _RecapBody(recap: recap),
      ),
    );
  }
}

class _RecapBody extends StatelessWidget {
  const _RecapBody({required this.recap});
  final WeeklyRecapResult recap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savings = recap.savingsThisWeek;
    final savingsColor = savings >= 0
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(recap.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),

        // --- Highlights -----------------------------------------------
        if (recap.highlights.isNotEmpty) ...[
          for (final h in recap.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(h, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // --- Biggest spend -------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: AppBorderRadius.full,
                  ),
                  child: Icon(
                    Icons.trending_up,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Biggest spend',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${recap.biggestSpend.categoryName}: '
                        '${recap.biggestSpend.currency} '
                        '${recap.biggestSpend.amount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // --- Savings this week ---------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  savings >= 0
                      ? Icons.savings_outlined
                      : Icons.report_gmailerrorred_outlined,
                  color: savingsColor,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Savings this week',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${savings >= 0 ? '+' : ''}'
                        '${savings.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: savingsColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Insight closer ------------------------------------------
        if (recap.insight.trim().isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      recap.insight,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
