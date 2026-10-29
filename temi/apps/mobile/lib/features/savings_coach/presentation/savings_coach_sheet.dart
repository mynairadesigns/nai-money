import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../data/savings_plan_result.dart';
import '../providers/savings_coach_provider.dart';

/// Opens the AI savings coach modal sheet for a given goal.
Future<void> showSavingsCoach(
  BuildContext context, {
  required String goalId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => SavingsCoachSheet(goalId: goalId),
  );
}

class SavingsCoachSheet extends ConsumerWidget {
  const SavingsCoachSheet({required this.goalId, super.key});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(savingsPlanProvider(goalId));

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Savings plan',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: async.when(
                loading: () => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Building your plan…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                error: (_, _) => Center(
                  child: Text(
                    "Couldn't build a plan right now.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                data: (plan) => _PlanBody(plan: plan),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan});
  final SavingsPlanResult plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTrackColor = plan.onTrack
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;

    return ListView(
      children: [
        // --- Summary header ------------------------------------------
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      plan.onTrack
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: onTrackColor,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      plan.onTrack ? 'On track' : 'Needs adjustments',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onTrackColor,
                      ),
                    ),
                  ],
                ),
                if (plan.summary.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(plan.summary, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // --- Required per month + timeline ---------------------------
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Per month',
                value: plan.requiredPerMonth.toStringAsFixed(0),
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatChip(
                label: 'Timeline',
                value: '${plan.timelineWeeks} wks',
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Suggestions ---------------------------------------------
        if (plan.suggestions.isNotEmpty) ...[
          Text('Where to cut', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final s in plan.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.categoryName,
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Now: ${s.currentMonthlySpend.toStringAsFixed(2)} '
                        '· cut by ${s.suggestedCut.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '+${s.monthlySavingsImpact.toStringAsFixed(2)} / mo',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
