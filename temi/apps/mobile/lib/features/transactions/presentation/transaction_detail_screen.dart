import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../providers/transactions_controller.dart';
import 'add_transaction_sheet.dart';

/// `/transaction/:id` — read-only summary view with Edit + Delete in the
/// app bar. The edit form itself is the shared [showAddTransactionSheet]
/// with `existing` preloaded.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({required this.id, super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final txStream = ref.watch(_txByIdProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final t = txStream.value;
              if (t == null) return;
              final saved = await showAddTransactionSheet(
                context,
                existing: t,
              );
              if (saved == true && context.mounted) context.pop();
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, txStream.value),
          ),
        ],
      ),
      body: txStream.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load this transaction.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        data: (t) {
          if (t == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'This transaction no longer exists.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }
          return _DetailBody(transaction: t);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Transaction? t,
  ) async {
    if (t == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
          'The wallet balance will be adjusted automatically.',
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
    if (confirmed != true) return;
    await ref.read(transactionsControllerProvider.notifier).delete(t.id);
    if (!context.mounted) return;
    context.pop();
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.transaction});
  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoryDaoProvider).watchAll();

    return StreamBuilder<List<Category>>(
      stream: categoriesAsync,
      builder: (context, snap) {
        Category? category;
        if (snap.hasData) {
          for (final c in snap.data!) {
            if (c.id == transaction.categoryId) {
              category = c;
              break;
            }
          }
        }
        final isIncome = transaction.type == 'income';
        final color = isIncome
            ? theme.colorScheme.secondary
            : theme.colorScheme.primary;
        final sign = isIncome ? '+' : '−';

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: Text(
                '$sign${transaction.currency} '
                '${transaction.amount.toStringAsFixed(2)}',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Field(label: 'Type', value: _typeLabel(transaction.type)),
            _Field(
              label: 'Category',
              value: category?.name ?? '—',
              leading: category == null
                  ? null
                  : Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${category.color}', radix: 16)),
                        borderRadius: AppBorderRadius.full,
                      ),
                      child: Icon(
                        iconForCategory(category.iconName),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
            ),
            _Field(label: 'Date', value: _formatDate(transaction.date)),
            if ((transaction.note ?? '').isNotEmpty)
              _Field(label: 'Note', value: transaction.note!),
          ],
        );
      },
    );
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'income':
        return 'Income';
      case 'expense':
        return 'Expense';
      case 'transfer':
        return 'Transfer';
      default:
        return t;
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.leading});
  final String label;
  final String value;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.sm)],
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Streams the transaction with the given id.
final _txByIdProvider =
    StreamProvider.family<Transaction?, String>((ref, id) async* {
  final dao = ref.watch(transactionDaoProvider);
  await for (final rows in dao.watchAll()) {
    yield rows.where((t) => t.id == id).firstOrNull;
  }
});
