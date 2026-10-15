import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneymind/data/local/app_database.dart';
import 'package:moneymind/features/budgets/providers/budget_progress_provider.dart';

import '../../helpers/test_harness.dart';

/// `budgetProgressProvider` derives spend on the fly (CLAUDE.md §8 "Budget
/// progress derivation"): sum of expenses in [startDate, endDate) for this
/// user, AND-filtered by categoryId / walletId when set. Never persisted.
void main() {
  final start = DateTime(2026, 5, 1);
  final end = DateTime(2026, 6, 1);
  final inWindow = DateTime(2026, 5, 15);

  Future<void> seedBudget(
    AppDatabase db, {
    required String id,
    required double amount,
    String? categoryId,
    String? walletId,
    int threshold = 80,
    String userId = 'u1',
  }) {
    final now = DateTime.now().toUtc();
    return db.budgetDao.insertOne(
      BudgetsCompanion(
        id: Value(id),
        userId: Value(userId),
        categoryId: Value(categoryId),
        walletId: Value(walletId),
        period: const Value('monthly'),
        startDate: Value(start),
        endDate: Value(end),
        amount: Value(amount),
        currency: const Value('USD'),
        thresholdPercent: Value(threshold),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  // Read the first emission via a listener rather than `.future`:
  // budgetProgressProvider wraps an *infinite* Drift `watch()` stream, and a
  // `.future` read leaves a pending completer that errors at container dispose.
  Future<BudgetProgress?> progress(ProviderContainer c, String budgetId) async {
    final completer = Completer<BudgetProgress?>();
    final sub = c.listen<AsyncValue<BudgetProgress?>>(
      budgetProgressProvider(budgetId),
      (_, next) {
        next.whenData((v) {
          if (!completer.isCompleted) completer.complete(v);
        });
      },
      fireImmediately: true,
    );
    try {
      return await completer.future;
    } finally {
      sub.close();
    }
  }

  test('sums only expenses in the window, ignoring income', () async {
    final h = buildTestContainer();
    await seedBudget(h.db, id: 'b1', amount: 1000);
    await seedTransaction(h.db, id: 't1', date: inWindow, amount: 100);
    await seedTransaction(h.db, id: 't2', date: inWindow, amount: 200);
    await seedTransaction(h.db, id: 't3', date: inWindow, amount: 500, type: 'income');

    final p = await progress(h.container, 'b1');
    expect(p!.spent, 300);
    expect(p.pctUsed, 30);
    expect(p.status, BudgetStatus.green);
    expect(p.remaining, 700);
  });

  test('category-scoped budget only counts that category', () async {
    final h = buildTestContainer();
    await seedBudget(h.db, id: 'b1', amount: 1000, categoryId: 'food');
    await seedTransaction(h.db, id: 't1', date: inWindow, amount: 100, categoryId: 'food');
    await seedTransaction(h.db, id: 't2', date: inWindow, amount: 200, categoryId: 'fun');

    final p = await progress(h.container, 'b1');
    expect(p!.spent, 100);
  });

  test('wallet-scoped budget only counts that wallet', () async {
    final h = buildTestContainer();
    await seedBudget(h.db, id: 'b1', amount: 1000, walletId: 'w1');
    await seedTransaction(h.db, id: 't1', date: inWindow, amount: 100, walletId: 'w1');
    await seedTransaction(h.db, id: 't2', date: inWindow, amount: 200, walletId: 'w2');

    final p = await progress(h.container, 'b1');
    expect(p!.spent, 100);
  });

  test('category AND wallet must both match when both are set', () async {
    final h = buildTestContainer();
    await seedBudget(h.db, id: 'b1', amount: 1000, categoryId: 'food', walletId: 'w1');
    await seedTransaction(h.db, id: 't1', date: inWindow, amount: 100, categoryId: 'food', walletId: 'w1');
    await seedTransaction(h.db, id: 't2', date: inWindow, amount: 200, categoryId: 'food', walletId: 'w2');
    await seedTransaction(h.db, id: 't3', date: inWindow, amount: 300, categoryId: 'fun', walletId: 'w1');

    final p = await progress(h.container, 'b1');
    expect(p!.spent, 100);
  });

  test('ignores transactions belonging to another user', () async {
    final h = buildTestContainer();
    await seedBudget(h.db, id: 'b1', amount: 1000, userId: 'u1');
    await seedTransaction(h.db, id: 't1', date: inWindow, amount: 100, userId: 'u1');
    await seedTransaction(h.db, id: 't2', date: inWindow, amount: 999, userId: 'u2');

    final p = await progress(h.container, 'b1');
    expect(p!.spent, 100);
  });

  group('status buckets', () {
    test('yellow once spend reaches the threshold', () async {
      final h = buildTestContainer();
      await seedBudget(h.db, id: 'b1', amount: 100, threshold: 80);
      await seedTransaction(h.db, id: 't1', date: inWindow, amount: 85);

      final p = await progress(h.container, 'b1');
      expect(p!.status, BudgetStatus.yellow);
    });

    test('red once spend exceeds 100%', () async {
      final h = buildTestContainer();
      await seedBudget(h.db, id: 'b1', amount: 100, threshold: 80);
      await seedTransaction(h.db, id: 't1', date: inWindow, amount: 120);

      final p = await progress(h.container, 'b1');
      expect(p!.status, BudgetStatus.red);
      expect(p.pctUsed, 120);
    });
  });

  test('returns null for a missing budget', () async {
    final h = buildTestContainer();
    final p = await progress(h.container, 'does-not-exist');
    expect(p, isNull);
  });
}
