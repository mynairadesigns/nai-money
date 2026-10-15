import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../budgets/providers/budgets_controller.dart';
import '../../budgets/providers/budgets_list_provider.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/budget_plan_result.dart';
import '../providers/budget_generator_provider.dart';

/// Standalone AI Budget Generator (PRD §7.9). Unlike the per-budget prefill
/// sheet (`showBudgetGenerator`, used inside Add Budget), this generates a
/// whole monthly plan and creates several budgets in one pass.
///
/// Flow: call `generateBudgetPlan` → show each category suggestion with its
/// reasoning → let the user uncheck any → "Create N budgets" inserts a
/// monthly budget per selection via [BudgetsController]. Categories that
/// already have an active budget are flagged and unchecked by default so we
/// don't silently double-budget them.
class BudgetGeneratorScreen extends ConsumerStatefulWidget {
  const BudgetGeneratorScreen({super.key});

  @override
  ConsumerState<BudgetGeneratorScreen> createState() =>
      _BudgetGeneratorScreenState();
}

class _BudgetGeneratorScreenState
    extends ConsumerState<BudgetGeneratorScreen> {
  /// categoryIds the user has checked. Null until the plan first loads, then
  /// seeded to every suggestion that isn't already budgeted.
  Set<String>? _selected;
  bool _creating = false;

  String _currency() {
    final wallets = ref.read(visibleWalletsProvider).value ?? const [];
    return wallets.isNotEmpty ? wallets.first.currency : 'USD';
  }

  Set<String> _alreadyBudgetedCategoryIds() {
    final active = ref.read(activeBudgetsProvider).value ?? const [];
    return {
      for (final b in active)
        if (b.categoryId != null) b.categoryId!,
    };
  }

  Future<void> _createSelected(List<BudgetSuggestion> suggestions) async {
    final selected = _selected ?? const {};
    final picks =
        suggestions.where((s) => selected.contains(s.categoryId)).toList();
    if (picks.isEmpty) return;

    setState(() => _creating = true);
    final currency = _currency();
    final ctrl = ref.read(budgetsControllerProvider.notifier);

    var created = 0;
    for (final s in picks) {
      await ctrl.create(
        BudgetFormData(
          categoryId: s.categoryId,
          amount: s.suggestedAmount,
          currency: currency,
          period: 'monthly',
        ),
      );
      if (!ref.read(budgetsControllerProvider).hasError) created++;
    }

    if (!mounted) return;
    setState(() => _creating = false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          created == picks.length
              ? 'Created $created budget${created == 1 ? '' : 's'} 🎉'
              : 'Created $created of ${picks.length} budgets',
        ),
      ),
    );
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Seed the checkbox selection the first time the plan resolves.
    ref.listen(budgetPlanProvider, (_, next) {
      next.whenData((plan) {
        if (_selected != null) return;
        final budgeted = _alreadyBudgetedCategoryIds();
        setState(() {
          _selected = {
            for (final s in plan.suggestions)
              if (!budgeted.contains(s.categoryId)) s.categoryId,
          };
        });
      });
    });

    final async = ref.watch(budgetPlanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Budget Plan')),
      body: SafeArea(
        child: async.when(
          loading: () => const _Loading(),
          error: (_, _) => _ErrorState(
            onRetry: () => ref.invalidate(budgetPlanProvider),
          ),
          data: (plan) => plan.suggestions.isEmpty
              ? const _EmptyState()
              : _PlanBody(
                  plan: plan,
                  currency: _currency(),
                  selected: _selected ?? const {},
                  alreadyBudgeted: _alreadyBudgetedCategoryIds(),
                  onToggle: (categoryId, sel) {
                    setState(() {
                      final next = {...?_selected};
                      if (sel) {
                        next.add(categoryId);
                      } else {
                        next.remove(categoryId);
                      }
                      _selected = next;
                    });
                  },
                ),
        ),
      ),
      bottomNavigationBar: async.maybeWhen(
        data: (plan) => plan.suggestions.isEmpty
            ? null
            : _CreateBar(
                count: _selected?.length ?? 0,
                busy: _creating,
                onCreate: () => _createSelected(plan.suggestions),
              ),
        orElse: () => null,
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({
    required this.plan,
    required this.currency,
    required this.selected,
    required this.alreadyBudgeted,
    required this.onToggle,
  });

  final BudgetPlanResult plan;
  final String currency;
  final Set<String> selected;
  final Set<String> alreadyBudgeted;
  final void Function(String categoryId, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        Text(
          'Based on your last 3 months of spending, here’s a suggested '
          'monthly budget. Uncheck anything you don’t want.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final s in plan.suggestions)
          _SuggestionTile(
            suggestion: s,
            currency: currency,
            selected: selected.contains(s.categoryId),
            alreadyBudgeted: alreadyBudgeted.contains(s.categoryId),
            onChanged: (v) => onToggle(s.categoryId, v ?? false),
          ),
        if (plan.notes.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: AppBorderRadius.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(plan.notes, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.currency,
    required this.selected,
    required this.alreadyBudgeted,
    required this.onChanged,
  });

  final BudgetSuggestion suggestion;
  final String currency;
  final bool selected;
  final bool alreadyBudgeted;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CheckboxListTile(
        value: selected,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            Expanded(
              child: Text(
                suggestion.categoryName,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              '$currency ${suggestion.suggestedAmount.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggestion.reasoning.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                suggestion.reasoning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (alreadyBudgeted) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Already budgeted',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateBar extends StatelessWidget {
  const _CreateBar({
    required this.count,
    required this.busy,
    required this.onCreate,
  });

  final int count;
  final bool busy;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(AppSpacing.lg),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: (count == 0 || busy) ? null : onCreate,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(
            busy
                ? 'Creating…'
                : count == 0
                    ? 'Select at least one'
                    : 'Create $count budget${count == 1 ? '' : 's'}',
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Reading your spending patterns…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Couldn't generate a plan right now.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Not enough to suggest yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Log a few weeks of expenses across your categories and we’ll '
              'propose a monthly budget. Needs a connection.',
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
