import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All budgets owned by the current user, sorted by createdAt desc.
final budgetsListProvider = StreamProvider<List<Budget>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(budgetDaoProvider).watchAll().map(
        (rows) => rows.where((b) => b.userId == user.uid).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
});

/// Active = `now` falls inside [startDate, endDate). For weekly / monthly
/// the row's endDate is the period boundary (always set at insert time
/// via [defaultRangeForPeriod]); custom rows must have a non-null endDate.
final activeBudgetsProvider = Provider<AsyncValue<List<Budget>>>((ref) {
  final now = DateTime.now();
  return ref.watch(budgetsListProvider).whenData(
        (rows) => rows.where((b) {
          if (now.isBefore(b.startDate)) return false;
          final end = b.endDate;
          if (end != null && !now.isBefore(end)) return false;
          return true;
        }).toList(),
      );
});

/// Past = window ended before `now`. Surfaces in the BudgetsListScreen
/// under a "Past" header so users can revisit historical performance.
final pastBudgetsProvider = Provider<AsyncValue<List<Budget>>>((ref) {
  final now = DateTime.now();
  return ref.watch(budgetsListProvider).whenData(
        (rows) => rows.where((b) {
          final end = b.endDate;
          return end != null && !now.isBefore(end);
        }).toList(),
      );
});
