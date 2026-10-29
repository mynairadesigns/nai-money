import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';

/// One row in the transactions list. Leading colored category icon,
/// title (category name or note), trailing amount (signed + colored).
class TransactionRow extends ConsumerWidget {
  const TransactionRow({
    required this.transaction,
    required this.onTap,
    super.key,
  });

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Streaming category lookup keeps the row reactive if the category
    // gets renamed/recolored from /category/manage.
    final categories = ref.watch(categoryDaoProvider).watchAll();
    return StreamBuilder<List<Category>>(
      stream: categories,
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

        final color = category != null
            ? Color(int.parse('FF${category.color}', radix: 16))
            : theme.colorScheme.surfaceContainerHighest;
        final icon = iconForCategory(category?.iconName ?? '');
        final title = category?.name ?? _fallbackTitle();
        final isIncome = transaction.type == 'income';
        final isTransfer = transaction.type == 'transfer';
        final sign = isIncome ? '+' : '−';
        final amountColor = isIncome
            ? theme.colorScheme.secondary
            : (isTransfer
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.primary);

        return InkWell(
          onTap: onTap,
          borderRadius: AppBorderRadius.lg,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
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
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if ((transaction.note ?? '').isNotEmpty)
                        Text(
                          transaction.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '$sign${transaction.currency} ${_format(transaction.amount)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fallbackTitle() {
    switch (transaction.type) {
      case 'transfer':
        return 'Transfer';
      case 'income':
        return 'Income';
      case 'expense':
        return 'Expense';
      default:
        return 'Transaction';
    }
  }

  String _format(double n) {
    final abs = n.abs();
    return abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
  }
}

/// "Today" / "Yesterday" / "Mon, 12 May" header used by the
/// date-grouped transaction list.
String formatTransactionDayHeader(DateTime date, {DateTime? now}) {
  final today = (now ?? DateTime.now()).toLocal();
  final d = date.toLocal();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfDate = DateTime(d.year, d.month, d.day);
  final diffDays = startOfToday.difference(startOfDate).inDays;
  if (diffDays == 0) return 'Today';
  if (diffDays == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final wd = weekdays[(d.weekday - 1) % 7];
  return '$wd, ${d.day} ${months[d.month - 1]}';
}
