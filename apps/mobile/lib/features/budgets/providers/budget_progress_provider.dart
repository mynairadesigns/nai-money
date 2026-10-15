import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// Derived progress for a single budget. UI colour buckets:
///   green  — pctUsed < thresholdPercent
///   yellow — thresholdPercent ≤ pctUsed ≤ 100
///   red    — pctUsed > 100 (over budget)
enum BudgetStatus { green, yellow, red }

class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spent,
    required this.pctUsed,
    required this.status,
    required this.daysRemaining,
  });

  final Budget budget;
  final double spent;

  /// `spent / budget.amount` * 100, can exceed 100.
  final double pctUsed;
  final BudgetStatus status;

  /// Days from now until [Budget.endDate]; 0 if past or unset.
  final int daysRemaining;

  double get remaining => budget.amount - spent;
}

/// Live progress for [budgetId]. Watches the matching transactions in
/// the budget's `[startDate, endDate)` window and sums expenses where:
///   - categoryId matches (if budget.categoryId != null)
///   - walletId matches (if budget.walletId != null)
///   - both must match if both are set (category within wallet)
final budgetProgressProvider =
    StreamProvider.family<BudgetProgress?, String>((ref, budgetId) async* {
  final dao = ref.watch(budgetDaoProvider);
  final budget = await dao.getById(budgetId);
  if (budget == null) {
    yield null;
    return;
  }

  final end = budget.endDate ?? DateTime.now().add(const Duration(days: 365));
  final txStream = ref.watch(transactionDaoProvider).watchByDateRangeForUser(
        userId: budget.userId,
        start: budget.startDate,
        end: end,
      );

  await for (final txs in txStream) {
    yield _aggregate(budget, txs);
  }
});

BudgetProgress _aggregate(Budget budget, List<Transaction> txs) {
  var spent = 0.0;
  for (final t in txs) {
    if (t.type != 'expense') continue;
    if (budget.userId != t.userId) continue;
    if (budget.categoryId != null && t.categoryId != budget.categoryId) {
      continue;
    }
    if (budget.walletId != null && t.walletId != budget.walletId) continue;
    spent += t.amount;
  }

  final pct = budget.amount == 0 ? 0.0 : (spent / budget.amount) * 100;
  final BudgetStatus status;
  if (pct > 100) {
    status = BudgetStatus.red;
  } else if (pct >= budget.thresholdPercent) {
    status = BudgetStatus.yellow;
  } else {
    status = BudgetStatus.green;
  }

  int days = 0;
  final end = budget.endDate;
  if (end != null) {
    final diff = end.difference(DateTime.now()).inDays;
    days = diff < 0 ? 0 : diff;
  }

  return BudgetProgress(
    budget: budget,
    spent: spent,
    pctUsed: pct,
    status: status,
    daysRemaining: days,
  );
}

/// All active budgets with their live progress, sorted by [BudgetProgress.pctUsed]
/// descending. Used by the notification coordinator (P7.2) to trigger alerts
/// at 50 / 80 / 100 / over-budget thresholds across every active budget —
/// not just the top-3 subset.
final allActiveBudgetProgressProvider =
    Provider<AsyncValue<List<BudgetProgress>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const AsyncData([]);
  final list = ref.watch(_activeProgressProvider);
  return list.whenData((all) {
    return [...all]..sort((a, b) => b.pctUsed.compareTo(a.pctUsed));
  });
});

/// Top 3 most-stressed active budgets (highest pctUsed first). Drives the
/// Home dashboard widget per PRD §11.1.
final topActiveBudgetProgressProvider =
    Provider<AsyncValue<List<BudgetProgress>>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const AsyncData([]);
  final list = ref.watch(_activeProgressProvider);
  return list.whenData((all) {
    final sorted = [...all]..sort((a, b) => b.pctUsed.compareTo(a.pctUsed));
    return sorted.take(3).toList();
  });
});

/// Active budgets + their live progress. Internal — Home consumes the
/// top-3 view above.
final _activeProgressProvider =
    StreamProvider<List<BudgetProgress>>((ref) async* {
  // Subscribe to budgetsListProvider via its async value rather than its
  // stream so we don't double-watch the underlying Drift stream.
  while (true) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      yield const [];
      return;
    }
    final budgetsAsync = ref.watch(budgetDaoProvider).watchAll();
    await for (final budgets in budgetsAsync) {
      final mine = budgets.where((b) => b.userId == user.uid).toList();
      final now = DateTime.now();
      final active = mine.where((b) {
        if (now.isBefore(b.startDate)) return false;
        final end = b.endDate;
        if (end != null && !now.isBefore(end)) return false;
        return true;
      }).toList();

      // Aggregate each in parallel against the same tx stream snapshot.
      final txDao = ref.watch(transactionDaoProvider);
      // We watch every active budget's range once per emission — cheap
      // because watchByDateRangeForUser filters at the SQL layer.
      final progressList = <BudgetProgress>[];
      for (final b in active) {
        final end = b.endDate ?? DateTime.now().add(const Duration(days: 365));
        final txs = await txDao
            .watchByDateRangeForUser(
              userId: b.userId,
              start: b.startDate,
              end: end,
            )
            .first;
        progressList.add(_aggregate(b, txs));
      }
      yield progressList;
    }
  }
});

