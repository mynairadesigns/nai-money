import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../../transactions/widgets/transaction_row.dart';

/// PRD §11.7 — drill-down for a single category from the /reports pie.
///
/// Route: `/reports/category/:catId?from=ISO&to=ISO`
///
/// Reads the period from query params (defaults to start-of-month → now
/// when missing). Shows a header card with the category's avatar + period
/// total, then a date-grouped list of the matching transactions.
class CategoryReportScreen extends ConsumerWidget {
  const CategoryReportScreen({
    required this.categoryId,
    super.key,
  });

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = _resolveRange(context);

    final categoriesStream = ref.watch(categoryDaoProvider).watchAll();
    final txAsync = ref.watch(_categoryReportTxProvider(range));

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<Category>>(
          stream: categoriesStream,
          builder: (context, snap) {
            final cat = _findCategory(snap.data, categoryId);
            return Text(cat?.name ?? 'Category');
          },
        ),
      ),
      body: StreamBuilder<List<Category>>(
        stream: categoriesStream,
        builder: (context, catSnap) {
          if (catSnap.connectionState == ConnectionState.waiting &&
              !catSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cat = _findCategory(catSnap.data, categoryId);
          if (cat == null) {
            return _NotFound(theme: theme);
          }

          return txAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Could not load transactions.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            data: (all) {
              final rows = all
                  .where((t) => t.categoryId == categoryId)
                  .toList()
                ..sort((a, b) => b.date.compareTo(a.date));
              return _Body(
                category: cat,
                rows: rows,
                range: range,
              );
            },
          );
        },
      ),
    );
  }

  Category? _findCategory(List<Category>? list, String id) {
    if (list == null) return null;
    for (final c in list) {
      if (c.id == id) return c;
    }
    return null;
  }

  _Range _resolveRange(BuildContext context) {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final fromRaw = qp['from'];
    final toRaw = qp['to'];
    final now = DateTime.now();
    DateTime? from;
    DateTime? to;
    if (fromRaw != null) {
      from = DateTime.tryParse(fromRaw);
    }
    if (toRaw != null) {
      to = DateTime.tryParse(toRaw);
    }
    from ??= DateTime(now.year, now.month, 1);
    to ??= now;
    return _Range(from: from, to: to);
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.category,
    required this.rows,
    required this.range,
  });

  final Category category;
  final List<Transaction> rows;
  final _Range range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(int.parse('FF${category.color}', radix: 16));
    final icon = iconForCategory(category.iconName);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Card(
            shape: const RoundedRectangleBorder(
              borderRadius: AppBorderRadius.lg,
            ),
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
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          category.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _summaryLine(rows, range),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Text(
            'Transactions',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (rows.isEmpty)
          _EmptyState(theme: theme, categoryName: category.name)
        else
          ..._buildGroupedItems(context, rows),
      ],
    );
  }

  List<Widget> _buildGroupedItems(BuildContext context, List<Transaction> rows) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    DateTime? lastDay;
    for (final t in rows) {
      final dayStart = DateTime(t.date.year, t.date.month, t.date.day);
      if (lastDay == null || dayStart != lastDay) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              formatTransactionDayHeader(dayStart),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
        lastDay = dayStart;
      }
      widgets.add(
        TransactionRow(
          transaction: t,
          onTap: () => context.push('/transaction/${t.id}'),
        ),
      );
    }
    return widgets;
  }

  String _summaryLine(List<Transaction> rows, _Range range) {
    final period = _formatPeriod(range.from, range.to);
    if (rows.isEmpty) {
      return '$period: —';
    }
    final currencies = rows.map((t) => t.currency).toSet();
    if (currencies.length > 1) {
      return '$period: Mixed currencies — see breakdown below';
    }
    final currency = currencies.first;
    // Expense sums are negative, income positive, transfers treated as 0.
    double total = 0;
    for (final t in rows) {
      if (t.type == 'income') {
        total += t.amount;
      } else if (t.type == 'expense') {
        total -= t.amount;
      }
    }
    final sign = total < 0 ? '−' : (total > 0 ? '+' : '');
    final abs = total.abs();
    final formatted =
        abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
    return '$period: $sign$currency $formatted';
  }

  String _formatPeriod(DateTime from, DateTime to) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final f = from.toLocal();
    final t = to.toLocal();
    final sameYear = f.year == t.year;
    if (sameYear) {
      return '${f.day} ${months[f.month - 1]} – ${t.day} ${months[t.month - 1]}';
    }
    return '${f.day} ${months[f.month - 1]} ${f.year} – '
        '${t.day} ${months[t.month - 1]} ${t.year}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme, required this.categoryName});
  final ThemeData theme;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No transactions in $categoryName for this period.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Category not found.',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Immutable period passed to the StreamProvider.family. Equality on
/// (from, to) so identical ranges share the same stream subscription.
@immutable
class _Range {
  const _Range({required this.from, required this.to});
  final DateTime from;
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _Range && other.from == from && other.to == to);

  @override
  int get hashCode => Object.hash(from, to);
}

final _categoryReportTxProvider =
    StreamProvider.family<List<Transaction>, _Range>((ref, range) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(transactionDaoProvider).watchByDateRangeForUser(
        userId: user.uid,
        start: range.from,
        end: range.to,
      );
});
