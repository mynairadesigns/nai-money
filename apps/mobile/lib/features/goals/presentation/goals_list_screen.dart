import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../data/goal_catalog.dart';
import '../providers/goal_progress_provider.dart';
import '../providers/goals_list_provider.dart';

/// `/goals` route — two-section list of the user's goals (Active +
/// Completed) with a FAB that opens the create form. PRD §6.8.
class GoalsListScreen extends ConsumerWidget {
  const GoalsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeAsync = ref.watch(activeGoalsProvider);
    final completedAsync = ref.watch(completedGoalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/goal/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add goal'),
      ),
      body: SafeArea(
        child: activeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load goals.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (active) {
            final completed = completedAsync.value ?? const <Goal>[];
            if (active.isEmpty && completed.isEmpty) {
              return _EmptyState(theme: theme);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl, // leave room for the FAB
              ),
              children: [
                if (active.isNotEmpty) ...[
                  const _SectionHeader(label: 'Active'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final g in active) _GoalListRow(goal: g),
                ],
                if (active.isNotEmpty && completed.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                if (completed.isNotEmpty) ...[
                  const _SectionHeader(label: 'Completed'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final g in completed) _GoalListRow(goal: g),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GoalListRow extends ConsumerWidget {
  const _GoalListRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(goalProgressProvider(goal.id));
    final pct = progress?.pct ?? 0.0;
    final days = progress?.daysRemaining;

    final color = Color(int.parse('FF${goal.color}', radix: 16));
    final icon = iconForCategory(goal.iconName);

    final subtitle = StringBuffer()
      ..write('${goal.currency} ${goal.currentAmount.toStringAsFixed(2)}')
      ..write(' of ')
      ..write('${goal.currency} ${goal.targetAmount.toStringAsFixed(2)}');
    if (days != null) {
      subtitle.write(' · $days days left');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/goal/${goal.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppBorderRadius.full,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: AppBorderRadius.full,
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No goals yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap Add goal to start saving toward something',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
