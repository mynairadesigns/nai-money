import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../providers/budgets_list_provider.dart';
import '../widgets/budget_progress_card.dart';

/// `/budgets` route — two-section list of the user's budgets (Active +
/// Past) with a FAB that opens the create form. Each row defers its
/// rendering + colour bucket to [BudgetProgressCard].
class BudgetsListScreen extends ConsumerWidget {
  const BudgetsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeAsync = ref.watch(activeBudgetsProvider);
    final pastAsync = ref.watch(pastBudgetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'AI budget plan',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => context.push('/budgets/generate'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/budget/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add budget'),
      ),
      body: SafeArea(
        child: activeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load budgets.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (active) {
            final past = pastAsync.value ?? const <Budget>[];
            if (active.isEmpty && past.isEmpty) {
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
                  _SectionHeader(label: 'Active'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final b in active) _BudgetListRow(budget: b),
                ],
                if (active.isNotEmpty && past.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                if (past.isNotEmpty) ...[
                  _SectionHeader(label: 'Past'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final b in past) _BudgetListRow(budget: b),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BudgetListRow extends StatelessWidget {
  const _BudgetListRow({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: BudgetProgressCard(
        budgetId: budget.id,
        onTap: () => context.push('/budget/${budget.id}'),
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
              Icons.donut_small_outlined,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No budgets yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap Add budget to get started',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => context.push('/budgets/generate'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate with AI'),
            ),
          ],
        ),
      ),
    );
  }
}
