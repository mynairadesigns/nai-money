import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';
import '../data/budget_catalog.dart';

/// Form payload for create / edit. Mutable POJO updated in place by the
/// AddBudgetScreen; submitted via [BudgetsController.create] / `.edit`.
class BudgetFormData {
  BudgetFormData({
    this.id,
    this.categoryId,
    this.walletId,
    this.period = 'monthly',
    this.amount = 0,
    this.currency = 'NGN',
    this.rollover = false,
    this.thresholdPercent = kDefaultBudgetThresholdPercent,
    DateTime? startDate,
    this.endDate,
  }) : startDate = startDate ?? DateTime.now();

  /// Non-null when editing.
  String? id;

  /// At least one of [categoryId] / [walletId] should be set in v1; both
  /// is allowed (category-within-wallet scope).
  String? categoryId;
  String? walletId;

  String period; // 'weekly' | 'monthly' | 'custom'
  double amount;
  String currency;
  bool rollover;
  int thresholdPercent;
  DateTime startDate;

  /// Required when [period] is 'custom'; auto-computed for weekly/monthly.
  DateTime? endDate;

  bool get hasScope => categoryId != null || walletId != null;
  bool get isReady => amount > 0 && hasScope;
}

final budgetsControllerProvider =
    AsyncNotifierProvider<BudgetsController, void>(BudgetsController.new);

/// AsyncNotifier driving budget create / edit / delete. UI watches the
/// AsyncValue for loading + error.
///
/// Naming: `edit` (not `update`) to avoid colliding with
/// `AsyncNotifier.update`.
class BudgetsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(BudgetFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a budget while signed out');
      }
      if (!form.isReady) {
        throw ArgumentError('Budget form missing amount or scope');
      }
      final dao = ref.read(budgetDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_b_${now.microsecondsSinceEpoch}';
      final range = _resolveRange(form);

      await dao.insertOne(
        BudgetsCompanion(
          id: Value(id),
          userId: Value(user.uid),
          categoryId: Value(form.categoryId),
          walletId: Value(form.walletId),
          period: Value(form.period),
          startDate: Value(range.start),
          endDate: Value(range.end),
          amount: Value(form.amount),
          currency: Value(form.currency),
          rollover: Value(form.rollover),
          thresholdPercent: Value(form.thresholdPercent),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> edit(BudgetFormData form) async {
    final id = form.id;
    if (id == null) throw ArgumentError('edit requires a non-null id');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(budgetDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Budget $id not found');
      final now = DateTime.now().toUtc();
      final range = _resolveRange(form);
      await dao.updateOne(
        BudgetsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          categoryId: Value(form.categoryId),
          walletId: Value(form.walletId),
          period: Value(form.period),
          startDate: Value(range.start),
          endDate: Value(range.end),
          amount: Value(form.amount),
          currency: Value(form.currency),
          rollover: Value(form.rollover),
          thresholdPercent: Value(form.thresholdPercent),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(budgetDaoProvider).deleteById(id);
    });
  }

  ({DateTime start, DateTime end}) _resolveRange(BudgetFormData form) {
    if (form.period == 'custom') {
      final end = form.endDate ?? form.startDate.add(const Duration(days: 30));
      return (start: form.startDate, end: end);
    }
    return defaultRangeForPeriod(form.period, anchor: form.startDate);
  }
}
