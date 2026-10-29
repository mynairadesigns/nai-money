import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../providers/reports_data_provider.dart';
import '../providers/reports_state_provider.dart';

/// Expense-by-category pie chart (PRD §6.10). Tapping a slice opens the
/// `/reports/category/:catId` drill-down with the active period passed
/// as `?from=&to=` query params.
class CategoryPie extends ConsumerStatefulWidget {
  const CategoryPie({super.key});
  @override
  ConsumerState<CategoryPie> createState() => _CategoryPieState();
}

class _CategoryPieState extends ConsumerState<CategoryPie> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataAsync = ref.watch(reportsDataProvider);
    final categoriesAsync =
        ref.watch(categoryDaoProvider).watchAll();
    final filter = ref.watch(reportsFilterProvider);

    return StreamBuilder<List<Category>>(
      stream: categoriesAsync,
      builder: (context, snap) {
        final categories = snap.data ?? const <Category>[];
        return dataAsync.when(
          loading: () => const _EmptyShell(child: Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          )),
          error: (e, _) => _EmptyShell(child: Center(
            child: Text(
              'Could not load report.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          )),
          data: (data) {
            if (data.byCategory.isEmpty) {
              return const _EmptyShell(
                child: Center(child: Text('No expenses in this period.')),
              );
            }
            return _PieBody(
              data: data,
              categories: categories,
              filter: filter,
              touchedIndex: _touched,
              onTouched: (i) => setState(() => _touched = i),
            );
          },
        );
      },
    );
  }
}

class _PieBody extends StatelessWidget {
  const _PieBody({
    required this.data,
    required this.categories,
    required this.filter,
    required this.touchedIndex,
    required this.onTouched,
  });
  final ReportsData data;
  final List<Category> categories;
  final ReportsFilter filter;
  final int? touchedIndex;
  final ValueChanged<int?> onTouched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = data.expenseTotal;
    final entries = data.byCategory;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where it went', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 56,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is FlTapUpEvent) {
                        final i = response?.touchedSection?.touchedSectionIndex;
                        if (i != null && i >= 0 && i < entries.length) {
                          _openSlice(context, entries[i].categoryId);
                        }
                      }
                      final i = response?.touchedSection?.touchedSectionIndex;
                      onTouched(i != null && i >= 0 ? i : null);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      _section(i, entries[i], total, theme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < entries.length; i++)
              _LegendRow(
                category: _findCategory(entries[i].categoryId),
                amount: entries[i].amount,
                share: total == 0 ? 0 : entries[i].amount / total,
                currency: data.currencyHint,
                onTap: () => _openSlice(context, entries[i].categoryId),
              ),
          ],
        ),
      ),
    );
  }

  void _openSlice(BuildContext context, String categoryId) {
    final range = filter.range();
    final from = range.start.toIso8601String();
    final to = range.end.toIso8601String();
    GoRouter.of(context).push('/reports/category/$categoryId?from=$from&to=$to');
  }

  Category? _findCategory(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  PieChartSectionData _section(
    int i,
    CategorySlice slice,
    double total,
    ThemeData theme,
  ) {
    final cat = _findCategory(slice.categoryId);
    final color = cat == null
        ? theme.colorScheme.outlineVariant
        : Color(int.parse('FF${cat.color}', radix: 16));
    final isTouched = i == touchedIndex;
    final radius = isTouched ? 64.0 : 56.0;
    final pct = total == 0 ? 0 : (slice.amount / total) * 100;
    return PieChartSectionData(
      value: slice.amount,
      color: color,
      radius: radius,
      title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
      titleStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.category,
    required this.amount,
    required this.share,
    required this.currency,
    required this.onTap,
  });
  final Category? category;
  final double amount;
  final double share;
  final String? currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = category == null
        ? theme.colorScheme.outlineVariant
        : Color(int.parse('FF${category!.color}', radix: 16));
    final icon = iconForCategory(category?.iconName ?? '');
    final name = category?.name ?? 'Uncategorized';
    final amountStr = currency == null
        ? amount.toStringAsFixed(2)
        : '$currency ${amount.toStringAsFixed(2)}';
    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppBorderRadius.full,
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${(share * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(amountStr, style: theme.textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _EmptyShell extends StatelessWidget {
  const _EmptyShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}
