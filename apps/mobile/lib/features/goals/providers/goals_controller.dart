import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';
import '../data/goal_catalog.dart';

/// Form payload for create / edit. Mutable POJO updated in place by
/// AddGoalScreen; submitted via [GoalsController.create] / `.edit`.
class GoalFormData {
  GoalFormData({
    this.id,
    this.name = '',
    this.targetAmount = 0,
    this.currency = 'NGN',
    this.deadline,
    this.walletId,
    String? iconName,
    String? colorHex,
  })  : iconName = iconName ?? kCategoryIconCatalog.keys.first,
        colorHex = colorHex ?? kCategoryColorCatalog.first;

  /// Non-null when editing.
  String? id;

  String name;
  double targetAmount;
  String currency;

  /// Optional — when null the goal just tracks progress with no deadline.
  DateTime? deadline;

  /// Optional grouping; doesn't enforce balance interactions.
  String? walletId;

  String iconName;
  String colorHex;

  bool get isReady => name.trim().isNotEmpty && targetAmount > 0;
}

final goalsControllerProvider =
    AsyncNotifierProvider<GoalsController, void>(GoalsController.new);

/// AsyncNotifier driving goal create / edit / delete + manual
/// contributions. UI watches the AsyncValue for loading + error.
///
/// Naming: `edit` (not `update`) to avoid colliding with
/// `AsyncNotifier.update`. The AI savings plan (`Goal.aiPlan`) is left
/// `null` in P3 — populated by the AI coach in P5.
class GoalsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(GoalFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a goal while signed out');
      }
      if (!form.isReady) {
        throw ArgumentError('Goal form missing name or amount');
      }
      final dao = ref.read(goalDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_g_${now.microsecondsSinceEpoch}';

      await dao.insertOne(
        GoalsCompanion(
          id: Value(id),
          userId: Value(user.uid),
          name: Value(form.name.trim()),
          targetAmount: Value(form.targetAmount),
          currentAmount: const Value(0),
          currency: Value(form.currency),
          deadline: Value(form.deadline),
          walletId: Value(form.walletId),
          iconName: Value(form.iconName),
          color: Value(form.colorHex),
          aiPlan: const Value(null),
          createdAt: Value(now),
          completedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> edit(GoalFormData form) async {
    final id = form.id;
    if (id == null) throw ArgumentError('edit requires a non-null id');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!form.isReady) {
        throw ArgumentError('Goal form missing name or amount');
      }
      final dao = ref.read(goalDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Goal $id not found');
      final now = DateTime.now().toUtc();

      await dao.updateOne(
        GoalsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          name: Value(form.name.trim()),
          targetAmount: Value(form.targetAmount),
          // currentAmount intentionally left untouched — contributions own it.
          currentAmount: Value(existing.currentAmount),
          currency: Value(form.currency),
          deadline: Value(form.deadline),
          walletId: Value(form.walletId),
          iconName: Value(form.iconName),
          color: Value(form.colorHex),
          aiPlan: Value(existing.aiPlan),
          createdAt: Value(existing.createdAt),
          completedAt: Value(existing.completedAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(goalDaoProvider).deleteById(id);
    });
  }

  /// Increments `currentAmount` by [amount] in a single Drift transaction.
  /// If the new amount meets or exceeds `targetAmount` and the goal isn't
  /// already completed, also stamps `completedAt = now`. Caller (UI)
  /// inspects the pre/post rows to decide whether to celebrate.
  Future<void> addContribution(String goalId, double amount) async {
    if (amount <= 0) {
      throw ArgumentError('Contribution must be greater than 0');
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(appDatabaseProvider);
      final dao = ref.read(goalDaoProvider);
      final now = DateTime.now().toUtc();

      await db.transaction(() async {
        final existing = await dao.getById(goalId);
        if (existing == null) throw StateError('Goal $goalId not found');

        final newAmount = existing.currentAmount + amount;
        final shouldComplete =
            existing.completedAt == null && newAmount >= existing.targetAmount;

        await dao.updateOne(
          GoalsCompanion(
            id: Value(existing.id),
            userId: Value(existing.userId),
            name: Value(existing.name),
            targetAmount: Value(existing.targetAmount),
            currentAmount: Value(newAmount),
            currency: Value(existing.currency),
            deadline: Value(existing.deadline),
            walletId: Value(existing.walletId),
            iconName: Value(existing.iconName),
            color: Value(existing.color),
            aiPlan: Value(existing.aiPlan),
            createdAt: Value(existing.createdAt),
            completedAt:
                Value(shouldComplete ? now : existing.completedAt),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
      });
    });
  }

  /// Explicit one-tap "mark completed" — stamps `completedAt` and tops
  /// `currentAmount` up to the target (never decreases it).
  Future<void> markCompleted(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(goalDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Goal $id not found');
      final now = DateTime.now().toUtc();
      final topped = existing.currentAmount > existing.targetAmount
          ? existing.currentAmount
          : existing.targetAmount;

      await dao.updateOne(
        GoalsCompanion(
          id: Value(existing.id),
          userId: Value(existing.userId),
          name: Value(existing.name),
          targetAmount: Value(existing.targetAmount),
          currentAmount: Value(topped),
          currency: Value(existing.currency),
          deadline: Value(existing.deadline),
          walletId: Value(existing.walletId),
          iconName: Value(existing.iconName),
          color: Value(existing.color),
          aiPlan: Value(existing.aiPlan),
          createdAt: Value(existing.createdAt),
          completedAt: Value(existing.completedAt ?? now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  /// True when [next] is the first row to flip [Goal.completedAt] from
  /// null to a real timestamp relative to [prev]. UI uses this to decide
  /// whether to show the celebration SnackBar.
  bool isNewlyCompleted(Goal? prev, Goal? next) {
    if (prev == null || next == null) return false;
    return prev.completedAt == null && next.completedAt != null;
  }
}
