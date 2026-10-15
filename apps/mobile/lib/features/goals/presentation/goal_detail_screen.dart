import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../data/local/app_database.dart';
import '../../savings_coach/presentation/savings_coach_sheet.dart';
import '../data/goal_catalog.dart';
import '../providers/goal_progress_provider.dart';
import '../providers/goals_controller.dart';

/// Per-goal view (PRD §6.8): header with progress ring, key stats, and
/// a manual "Add contribution" action. AI plan section is reserved for
/// P5 and only renders when [Goal.aiPlan] is non-null.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goalAsync = ref.watch(_goalByIdProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) =>
                _onAction(context, ref, action, goalAsync.value),
            itemBuilder: (_) {
              final goal = goalAsync.value;
              final isCompleted = goal?.completedAt != null;
              return [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!isCompleted)
                  const PopupMenuItem(
                    value: 'complete',
                    child: Text('Mark completed'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ];
            },
          ),
        ],
      ),
      body: goalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load this goal.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        data: (goal) {
          if (goal == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This goal no longer exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return _DetailBody(goal: goal);
        },
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Goal? goal,
  ) async {
    if (goal == null) return;
    final ctrl = ref.read(goalsControllerProvider.notifier);
    switch (action) {
      case 'edit':
        context.push('/goal/add', extra: goal);
        break;
      case 'complete':
        await ctrl.markCompleted(goal.id);
        if (!context.mounted) return;
        final result = ref.read(goalsControllerProvider);
        if (result.hasError) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal marked as completed.')),
        );
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this goal?'),
            content: const Text(
              'This removes the goal and its contribution history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        await ctrl.delete(goal.id);
        if (!context.mounted) return;
        final result = ref.read(goalsControllerProvider);
        if (result.hasError) return;
        context.pop();
        break;
    }
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(goalProgressProvider(goal.id));
    final pct = progress?.pct ?? 0.0;
    final days = progress?.daysRemaining;
    final perMonth = progress?.requiredPerMonth;
    final color = Color(int.parse('FF${goal.color}', radix: 16));
    final icon = iconForCategory(goal.iconName);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // --- Header card ---------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 8,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AppBorderRadius.full,
                        ),
                        child: Icon(icon, color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        goal.name,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${goal.currency} ${goal.currentAmount.toStringAsFixed(2)}'
                        ' of '
                        '${goal.currency} ${goal.targetAmount.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (goal.completedAt != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: theme.colorScheme.secondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Completed',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // --- Get a plan with AI (P5.3) -------------------------------
        if (goal.completedAt == null)
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Get a plan with AI'),
            onPressed: () => showSavingsCoach(context, goalId: goal.id),
          ),
        const SizedBox(height: AppSpacing.lg),

        // --- Stats grid ----------------------------------------------
        Row(
          children: [
            _Stat(
              label: 'Days left',
              value: days == null ? '—' : '$days',
              color: theme.colorScheme.onSurface,
            ),
            _Stat(
              label: 'Per month',
              value: perMonth == null
                  ? '—'
                  : '${goal.currency} ${perMonth.toStringAsFixed(0)}',
              color: theme.colorScheme.primary,
            ),
            _Stat(
              label: 'Complete',
              value: '${(pct * 100).toStringAsFixed(0)}%',
              color: theme.colorScheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        // --- Add contribution ----------------------------------------
        if (goal.completedAt == null)
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add contribution'),
            onPressed: () => _openContributionSheet(context, ref, goal),
          ),

        // AI plan placeholder — populated in P5 only.
        if (goal.aiPlan != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'AI plan available',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openContributionSheet(
    BuildContext context,
    WidgetRef ref,
    Goal goal,
  ) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => _ContributionSheet(goal: goal),
    );
    if (ok == true && context.mounted) {
      // After a successful contribution, check whether this is the
      // transition into "completed" and celebrate if so.
      final fresh = await ref.read(goalDaoProvider).getById(goal.id);
      if (!context.mounted) return;
      final ctrl = ref.read(goalsControllerProvider.notifier);
      if (ctrl.isNewlyCompleted(goal, fresh)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 Goal reached!')),
        );
      }
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
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
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContributionSheet extends ConsumerStatefulWidget {
  const _ContributionSheet({required this.goal});
  final Goal goal;

  @override
  ConsumerState<_ContributionSheet> createState() =>
      _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<_ContributionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountCtrl.text.trim());
    final ctrl = ref.read(goalsControllerProvider.notifier);
    await ctrl.addContribution(widget.goal.id, amount);
    if (!mounted) return;
    final result = ref.read(goalsControllerProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save contribution.')),
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commitState = ref.watch(goalsControllerProvider);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add contribution', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${widget.goal.currency}  ',
                ),
                validator: (v) =>
                    Validators.amount(v, label: 'Contribution'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: commitState.isLoading ? null : _save,
                child: commitState.isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-shot Drift lookup keyed by goal id; rebuilds when the DAO stream
/// emits (since [goalDaoProvider.watchAll] is the underlying source).
final _goalByIdProvider =
    StreamProvider.family<Goal?, String>((ref, id) async* {
  final dao = ref.watch(goalDaoProvider);
  await for (final rows in dao.watchAll()) {
    Goal? hit;
    for (final g in rows) {
      if (g.id == id) {
        hit = g;
        break;
      }
    }
    yield hit;
  }
});
