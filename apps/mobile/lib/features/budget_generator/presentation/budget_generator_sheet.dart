import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../data/budget_plan_result.dart';
import '../providers/budget_generator_provider.dart';

/// Suggestion payload returned to the caller when the user taps a card.
typedef BudgetGeneratorPick = ({
  String categoryId,
  double suggestedAmount,
  String currency,
});

/// Opens the AI budget generator modal sheet. Resolves with the suggestion
/// the user tapped, or `null` if they cancelled.
Future<BudgetGeneratorPick?> showBudgetGenerator(
  BuildContext context, {
  String? defaultCurrency,
}) {
  return showModalBottomSheet<BudgetGeneratorPick?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => BudgetGeneratorSheet(defaultCurrency: defaultCurrency),
  );
}

class BudgetGeneratorSheet extends ConsumerWidget {
  const BudgetGeneratorSheet({this.defaultCurrency, super.key});

  /// Currency to attach to the resulting pick — the callable does not
  /// echo per-suggestion currency, so the form's current currency wins.
  final String? defaultCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(budgetPlanProvider);

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
                    'Generate budget',
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
                        'Reading your spending patterns…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                error: (_, _) => Center(
                  child: Text(
                    "Couldn't generate a plan right now.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                data: (plan) => _SuggestionList(
                  plan: plan,
                  currency: defaultCurrency,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.plan, required this.currency});
  final BudgetPlanResult plan;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = currency ?? 'USD';

    if (plan.suggestions.isEmpty) {
      return Center(
        child: Text(
          'No suggestions yet — add a few more expenses first.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: plan.suggestions.length + (plan.notes.isNotEmpty ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        if (i == plan.suggestions.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              plan.notes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final s = plan.suggestions[i];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: AppBorderRadius.lg,
            onTap: () => Navigator.of(context).pop<BudgetGeneratorPick>((
              categoryId: s.categoryId,
              suggestedAmount: s.suggestedAmount,
              currency: cur,
            )),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.categoryName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '$cur ${s.suggestedAmount.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  if (s.reasoning.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      s.reasoning,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
