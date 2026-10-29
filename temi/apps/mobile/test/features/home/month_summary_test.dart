import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:temi_finance/data/local/app_database.dart';
import 'package:temi_finance/features/home/providers/month_summary_provider.dart';
import 'package:temi_finance/features/transactions/providers/transactions_list_provider.dart';

import '../../helpers/test_harness.dart';

/// Home's "This month" card. It used to be hardcoded `$0` markup, so it
/// never moved no matter what the user recorded. These lock down the
/// aggregation that replaced it.
void main() {
  final start = DateTime(2026, 8);
  final end = DateTime(2026, 9);

  Transaction tx({
    required String id,
    required String type,
    required double amount,
    required DateTime date,
    String currency = 'USD',
  }) =>
      Transaction(
        id: id,
        userId: 'u1',
        walletId: 'w1',
        categoryId: 'c1',
        type: type,
        amount: amount,
        currency: currency,
        date: date,
        createdAt: date,
        updatedAt: date,
        syncStatus: 'pending',
        aiCategorySuggested: false,
        isRecurring: false,
      );

  group('summarizeMonth', () {
    test('sums income and expenses inside the month', () {
      final summary = summarizeMonth(
        [
          tx(id: '1', type: 'income', amount: 3000, date: DateTime(2026, 8, 1)),
          tx(id: '2', type: 'expense', amount: 42.5, date: DateTime(2026, 8, 9)),
          tx(id: '3', type: 'expense', amount: 7.5, date: DateTime(2026, 8, 30)),
        ],
        monthStart: start,
        monthEnd: end,
      );

      expect(summary.income, 3000);
      expect(summary.expenses, 50);
      expect(summary.net, 2950);
      expect(summary.currencyCode, 'USD');
      expect(summary.isMixedCurrency, isFalse);
    });

    test('excludes transfers — moving your own money is not income', () {
      final summary = summarizeMonth(
        [
          tx(id: '1', type: 'transfer', amount: 500, date: DateTime(2026, 8, 5)),
        ],
        monthStart: start,
        monthEnd: end,
      );

      expect(summary.income, 0);
      expect(summary.expenses, 0);
      expect(summary.isEmpty, isTrue);
    });

    test('excludes rows outside the month on a half-open range', () {
      final summary = summarizeMonth(
        [
          // Last microsecond of the previous month.
          tx(
            id: '1',
            type: 'expense',
            amount: 10,
            date: DateTime(2026, 7, 31, 23, 59, 59),
          ),
          // Exactly midnight on the 1st of the month — included.
          tx(id: '2', type: 'expense', amount: 20, date: start),
          // Exactly midnight on the 1st of NEXT month — excluded.
          tx(id: '3', type: 'expense', amount: 40, date: end),
        ],
        monthStart: start,
        monthEnd: end,
      );

      expect(summary.expenses, 20);
    });

    test('flags mixed currencies instead of stamping one code on the sum', () {
      final summary = summarizeMonth(
        [
          tx(id: '1', type: 'expense', amount: 10, date: DateTime(2026, 8, 2)),
          tx(
            id: '2',
            type: 'expense',
            amount: 20,
            date: DateTime(2026, 8, 3),
            currency: 'EUR',
          ),
        ],
        monthStart: start,
        monthEnd: end,
      );

      expect(summary.expenses, 30);
      expect(summary.isMixedCurrency, isTrue);
      expect(summary.currencyCode, isNull);
    });

    test('an empty month borrows the fallback wallet currency', () {
      final summary = summarizeMonth(
        const [],
        monthStart: start,
        monthEnd: end,
        fallbackCurrency: 'KHR',
      );

      expect(summary.isEmpty, isTrue);
      expect(summary.currencyCode, 'KHR');
      expect(summary.isMixedCurrency, isFalse);
    });

    test('net goes negative when spending outruns income', () {
      final summary = summarizeMonth(
        [
          tx(id: '1', type: 'income', amount: 100, date: DateTime(2026, 8, 4)),
          tx(id: '2', type: 'expense', amount: 250, date: DateTime(2026, 8, 6)),
        ],
        monthStart: start,
        monthEnd: end,
      );

      expect(summary.net, -150);
    });
  });

  group('monthSummaryProvider', () {
    test('recomputes when a transaction lands in Drift', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 0);

      final sub = h.container.listen<AsyncValue<List<Transaction>>>(
        transactionsListProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      await _waitFor(
        h.container,
        () => h.container.read(monthSummaryProvider).hasValue,
      );
      expect(h.container.read(monthSummaryProvider).value!.isEmpty, isTrue);

      final now = DateTime.now();
      await seedTransaction(
        h.db,
        id: 't1',
        date: now,
        amount: 125.5,
        type: 'expense',
      );

      await _waitFor(
        h.container,
        () =>
            (h.container.read(monthSummaryProvider).value?.expenses ?? 0) > 0,
      );
      final summary = h.container.read(monthSummaryProvider).value!;
      expect(summary.expenses, 125.5);
      expect(summary.net, -125.5);
    });
  });
}

/// Polls until [condition] holds. Drift emits asynchronously after a
/// write, so the assertion has to wait for the next emission.
Future<void> _waitFor(
  ProviderContainer container,
  bool Function() condition,
) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition never held');
}
