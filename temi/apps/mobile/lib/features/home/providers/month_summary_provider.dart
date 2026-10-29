import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../transactions/providers/transactions_list_provider.dart';
import '../../wallets/providers/wallets_list_provider.dart';

/// Income / expense / net for the calendar month currently in progress,
/// powering the Home dashboard's "This month" card.
///
/// Transfers are excluded — moving money between your own wallets is
/// neither income nor spending. Mirrors `ReportsData`'s treatment so the
/// two screens can't disagree.
class MonthSummary {
  const MonthSummary({
    required this.income,
    required this.expenses,
    required this.currencyCode,
    required this.isMixedCurrency,
  });

  final double income;
  final double expenses;

  /// The single currency every counted row used, or the fallback wallet
  /// currency when the month is empty. Null only when rows genuinely
  /// span multiple currencies.
  final String? currencyCode;

  /// True when the month's rows span more than one currency. Totals are
  /// then a raw sum across currencies, so the UI must say so rather than
  /// stamp one code onto a meaningless number. (Cross-currency
  /// normalization is deferred — same caveat as `ReportsData`.)
  final bool isMixedCurrency;

  double get net => income - expenses;
  bool get isEmpty => income == 0 && expenses == 0;
}

/// Derived from [transactionsListProvider] (already scoped to the
/// signed-in user) rather than a fresh date-ranged query, so the month
/// window is recomputed on every emission — an app left open across
/// midnight on the 1st rolls over instead of showing a stale month.
final monthSummaryProvider = Provider<AsyncValue<MonthSummary>>((ref) {
  final wallets = ref.watch(visibleWalletsProvider).value ?? const <Wallet>[];
  // With no transactions yet there's no currency to infer, so borrow the
  // first wallet's — otherwise an empty month renders a bare "0.00".
  final fallback = wallets.isEmpty ? null : wallets.first.currency;

  return ref.watch(transactionsListProvider).whenData((rows) {
    final now = DateTime.now();
    return summarizeMonth(
      rows,
      monthStart: DateTime(now.year, now.month),
      // Month 13 rolls to January of the next year — Dart normalizes it.
      monthEnd: DateTime(now.year, now.month + 1),
      fallbackCurrency: fallback,
    );
  });
});

/// Pure aggregation over `[monthStart, monthEnd)`. Exposed for tests.
MonthSummary summarizeMonth(
  List<Transaction> rows, {
  required DateTime monthStart,
  required DateTime monthEnd,
  String? fallbackCurrency,
}) {
  var income = 0.0;
  var expenses = 0.0;
  final currencies = <String>{};

  for (final t in rows) {
    if (t.type == 'transfer') continue;
    // Half-open range, matching the budget-progress convention: a row
    // stamped exactly midnight on the 1st belongs to the NEXT month.
    if (t.date.isBefore(monthStart) || !t.date.isBefore(monthEnd)) continue;
    currencies.add(t.currency);
    if (t.type == 'income') {
      income += t.amount;
    } else if (t.type == 'expense') {
      expenses += t.amount;
    }
  }

  return MonthSummary(
    income: income,
    expenses: expenses,
    currencyCode: switch (currencies.length) {
      0 => fallbackCurrency,
      1 => currencies.first,
      _ => null,
    },
    isMixedCurrency: currencies.length > 1,
  );
}
