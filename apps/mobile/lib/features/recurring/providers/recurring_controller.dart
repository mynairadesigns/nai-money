import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';
import '../data/recurring_catalog.dart';

/// Form payload for create/edit. Mutable POJO updated in place by the
/// AddRecurringScreen; submitted via [RecurringController.create] / `.edit`.
class RecurringFormData {
  RecurringFormData({
    this.id,
    this.walletId,
    this.categoryId,
    this.type = 'expense',
    this.amount = 0,
    this.note,
    this.frequency = 'monthly',
    this.interval = 1,
    this.mode = 'auto',
    DateTime? startDate,
    this.endDate,
  }) : startDate = startDate ?? DateTime.now();

  /// Non-null when editing an existing rule.
  String? id;

  String? walletId;
  String? categoryId;

  /// 'expense' | 'income'. Transfer recurrences aren't supported in v1 —
  /// the form's Type segment only exposes the two.
  String type;
  double amount;
  String? note;

  String frequency; // daily | weekly | monthly | yearly
  int interval; // >= 1
  String mode; // auto | reminder

  DateTime startDate;
  DateTime? endDate;

  bool get hasScope => walletId != null && categoryId != null;
  bool get isReady => amount > 0 && hasScope && interval >= 1;
}

final recurringControllerProvider =
    AsyncNotifierProvider<RecurringController, void>(RecurringController.new);

/// Drives create / edit / delete / pause / resume on recurring rules.
/// UI watches the [AsyncValue] for loading + error toasts.
///
/// Naming mirrors [BudgetsController] — `edit` (not `update`) to avoid
/// colliding with the framework's `AsyncNotifier.update`.
class RecurringController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(RecurringFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a recurring rule while signed out');
      }
      if (!form.isReady) {
        throw ArgumentError(
          'Recurring form missing amount, wallet, or category',
        );
      }
      final dao = ref.read(recurringRuleDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_rr_${now.microsecondsSinceEpoch}';

      // First occurrence fires AFTER the start date (the start anchors
      // the cadence, it isn't itself an occurrence).
      final nextDue =
          addRecurringInterval(form.startDate, form.frequency, form.interval);

      await dao.insertOne(
        RecurringRulesCompanion(
          id: Value(id),
          userId: Value(user.uid),
          transactionTemplate: Value(_encodeTemplate(form)),
          frequency: Value(form.frequency),
          interval: Value(form.interval),
          startDate: Value(form.startDate),
          endDate: Value(form.endDate),
          nextDueDate: Value(nextDue),
          mode: Value(form.mode),
          isPaused: const Value(false),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> edit(RecurringFormData form) async {
    final id = form.id;
    if (id == null) throw ArgumentError('edit requires a non-null id');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(recurringRuleDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Recurring rule $id not found');
      final now = DateTime.now().toUtc();

      // Recompute `nextDueDate` from the (possibly edited) startDate /
      // frequency / interval. This avoids the cursor drifting backwards
      // when a user shortens the cadence.
      final nextDue =
          addRecurringInterval(form.startDate, form.frequency, form.interval);

      await dao.updateOne(
        RecurringRulesCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          transactionTemplate: Value(_encodeTemplate(form)),
          frequency: Value(form.frequency),
          interval: Value(form.interval),
          startDate: Value(form.startDate),
          endDate: Value(form.endDate),
          nextDueDate: Value(nextDue),
          mode: Value(form.mode),
          isPaused: Value(existing.isPaused),
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
      await ref.read(recurringRuleDaoProvider).deleteById(id);
    });
  }

  Future<void> pause(String id) => _setPaused(id, true);
  Future<void> resume(String id) => _setPaused(id, false);

  Future<void> _setPaused(String id, bool paused) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(recurringRuleDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Recurring rule $id not found');
      final now = DateTime.now().toUtc();
      await dao.updateOne(
        RecurringRulesCompanion(
          id: Value(existing.id),
          userId: Value(existing.userId),
          transactionTemplate: Value(existing.transactionTemplate),
          frequency: Value(existing.frequency),
          interval: Value(existing.interval),
          startDate: Value(existing.startDate),
          endDate: Value(existing.endDate),
          nextDueDate: Value(existing.nextDueDate),
          mode: Value(existing.mode),
          isPaused: Value(paused),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  String _encodeTemplate(RecurringFormData form) {
    return jsonEncode({
      'type': form.type,
      'amount': form.amount,
      'walletId': form.walletId,
      'categoryId': form.categoryId,
      'note': form.note,
    });
  }
}

/// Helper for screens that need to read a rule's stored template back out
/// (e.g. the detail header). Returns an empty map on parse errors so the
/// UI degrades to a minimal view instead of crashing.
Map<String, dynamic> decodeRecurringTemplate(String raw) {
  if (raw.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    // fall through
  }
  return const <String, dynamic>{};
}
