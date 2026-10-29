import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';
import 'reports_state_provider.dart';

/// One slice of the pie / one row in the breakdown.
class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.amount,
  });
  final String categoryId;
  final double amount;
}

/// Aggregated totals for the Reports tab.
///
/// Multi-currency normalization to the user's `defaultCurrency` is
/// deferred — for v1 every amount is summed in its raw stored currency
/// (PRD §5.1 stores `Transaction.currency` per row; the destination
/// currency for transfers). If the user has wallets in multiple
/// currencies the totals will be the simple sum, which the UI labels
/// as "mixed" when applicable. Pie + bars only consider expenses /
/// income — transfers are excluded from both totals and the breakdown.
class ReportsData {
  const ReportsData({
    required this.incomeTotal,
    required this.expenseTotal,
    required this.byCategory,
    required this.currencyHint,
  });

  final double incomeTotal;
  final double expenseTotal;

  /// Expense breakdown by `categoryId`. Income excluded by design —
  /// pie chart shows where money WENT.
  final List<CategorySlice> byCategory;

  /// Currency code most rows used, or null if mixed / empty.
  final String? currencyHint;

  double get net => incomeTotal - expenseTotal;
  bool get isEmpty => incomeTotal == 0 && expenseTotal == 0;
}

/// Live-derived ReportsData for the current [reportsFilterProvider]
/// selection. Recomputes whenever the filter or the transaction set
/// changes within the chosen range.
final reportsDataProvider = StreamProvider<ReportsData>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final filter = ref.watch(reportsFilterProvider);
  final range = filter.range();
  final dao = ref.watch(transactionDaoProvider);
  return dao
      .watchByDateRangeForUser(
        userId: user.uid,
        start: range.start,
        end: range.end,
      )
      .map(_aggregate);
});

ReportsData _aggregate(List<Transaction> rows) {
  var income = 0.0;
  var expense = 0.0;
  final byCat = <String, double>{};
  final currencies = <String, int>{};
  for (final t in rows) {
    if (t.type == 'transfer') continue;
    currencies[t.currency] = (currencies[t.currency] ?? 0) + 1;
    if (t.type == 'income') {
      income += t.amount;
    } else if (t.type == 'expense') {
      expense += t.amount;
      final key = t.categoryId.isEmpty ? '_uncategorized' : t.categoryId;
      byCat[key] = (byCat[key] ?? 0) + t.amount;
    }
  }

  final slices = byCat.entries
      .map((e) => CategorySlice(categoryId: e.key, amount: e.value))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  String? hint;
  if (currencies.length == 1) {
    hint = currencies.keys.first;
  } else if (currencies.isEmpty) {
    hint = null;
  } else {
    hint = null; // mixed → caller renders "Mixed currencies"
  }

  return ReportsData(
    incomeTotal: income,
    expenseTotal: expense,
    byCategory: slices,
    currencyHint: hint,
  );
}
