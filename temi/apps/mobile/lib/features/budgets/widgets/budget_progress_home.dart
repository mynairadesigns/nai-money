import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../providers/budget_progress_provider.dart';
import 'budget_progress_card.dart';

/// Home dashboard variant per PRD §11.1 — top 3 active budgets ranked
/// by `pctUsed` desc (most-stressed first). Empty state surfaces an
/// inline CTA so users can create their first budget without leaving
/// Home.
class BudgetProgressHome extends ConsumerWidget {
  const BudgetProgressHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(topActiveBudgetProgressProvider);

    return async.when(
      loading: () => const SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Could not load budgets.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      data: (top) {
        if (top.isEmpty) {
          return _EmptyCta();
        }
        return Column(
          children: [
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              BudgetProgressCard(
                budgetId: top[i].budget.id,
                onTap: () => context.push('/budget/${top[i].budget.id}'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyCta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: AppBorderRadius.lg,
        onTap: () => context.push('/budget/add'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                Icons.donut_small_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Set a budget to track spending against targets',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
