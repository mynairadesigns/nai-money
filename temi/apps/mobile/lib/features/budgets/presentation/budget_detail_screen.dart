import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../transactions/widgets/transaction_row.dart';
import '../providers/budgets_controller.dart';
import '../widgets/budget_progress_card.dart';

/// `/budget/:id` — per-budget detail view. Header is the
/// [BudgetProgressCard]; body lists the matching transactions for the
/// budget's `[startDate, endDate)` window, grouped by day.
class BudgetDetailScreen extends ConsumerWidget {
  const BudgetDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final budgetAsync = ref.watch(_budgetByIdProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) =>
                _onAction(context, ref, action, budgetAsync.value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: budgetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load this budget.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        data: (budget) {
          if (budget == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This budget no longer exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return _DetailBody(budget: budget);
        },
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Budget? budget,
  ) async {
    if (budget == null) return;
    switch (action) {
      case 'edit':
        context.push('/budget/add', extra: budget);
        break;
      case 'delete':
        await _confirmDelete(context, ref, budget);
        break;
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Budget budget,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this budget?'),
        content: const Text(
          'This removes the budget. Transactions are not affected.',
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
    await ref.read(budgetsControllerProvider.notifier).delete(budget.id);
    if (!context.mounted) return;
    final result = ref.read(budgetsControllerProvider);
    if (result.hasError) return;
    context.pop();
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final end = budget.endDate ??
        DateTime.now().add(const Duration(days: 365));
    final txAsync = ref.watch(transactionDaoProvider).watchByDateRangeForUser(
          userId: budget.userId,
          start: budget.startDate,
          end: end,
        );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        BudgetProgressCard(budgetId: budget.id),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Transactions in this period',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        StreamBuilder<List<Transaction>>(
          stream: txAsync,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final matching = snap.data!.where((t) {
              if (t.type != 'expense') return false;
              if (budget.categoryId != null &&
                  t.categoryId != budget.categoryId) {
                return false;
              }
              if (budget.walletId != null && t.walletId != budget.walletId) {
                return false;
              }
              return true;
            }).toList()
              ..sort((a, b) => b.date.compareTo(a.date));

            if (matching.isEmpty) {
              return _EmptyTxRow(theme: theme);
            }
            return _GroupedTxList(transactions: matching);
          },
        ),
      ],
    );
  }
}

class _GroupedTxList extends StatelessWidget {
  const _GroupedTxList({required this.transactions});
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Group by local calendar day.
    final groups = <DateTime, List<Transaction>>{};
    for (final t in transactions) {
      final d = t.date.toLocal();
      final key = DateTime(d.year, d.month, d.day);
      (groups[key] ??= []).add(t);
    }
    final orderedDays = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final day in orderedDays) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Text(
              formatTransactionDayHeader(day),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < groups[day]!.length; i++) ...[
                  if (i > 0) const Divider(height: 0),
                  TransactionRow(
                    transaction: groups[day]![i],
                    onTap: () => GoRouter.of(context)
                        .push('/transaction/${groups[day]![i].id}'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyTxRow extends StatelessWidget {
  const _EmptyTxRow({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'No matching transactions yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot Drift lookup keyed by budget id; rebuilds when the DAO stream
/// emits. Mirrors the `_walletByIdProvider` pattern.
final _budgetByIdProvider =
    StreamProvider.family<Budget?, String>((ref, id) async* {
  final dao = ref.watch(budgetDaoProvider);
  await for (final rows in dao.watchAll()) {
    yield rows.where((b) => b.id == id).firstOrNull;
  }
});
