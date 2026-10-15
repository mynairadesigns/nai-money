import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneymind/data/local/app_database.dart';
import 'package:moneymind/features/recurring/data/recurring_catalog.dart';
import 'package:moneymind/features/recurring/providers/recurring_controller.dart';

import '../../helpers/test_harness.dart';

/// `RecurringController` owns create/edit/delete/pause/resume on recurring
/// rules. `nextDueDate` is computed via `addRecurringInterval` (the same
/// helper the server `addInterval` mirrors — arithmetic is covered by
/// recurring_interval_test.dart, so here we only verify the WIRING: that the
/// controller feeds the right args and persists the result). Every mutation
/// re-flags `syncStatus='pending'` (CLAUDE.md §8 write-through). The
/// transaction payload is round-tripped through `decodeRecurringTemplate`.
void main() {
  RecurringController ctrl(ProviderContainer c) =>
      c.read(recurringControllerProvider.notifier);

  Future<RecurringRule> onlyRule(AppDatabase db) async {
    final rows = await db.recurringRuleDao.watchAll().first;
    expect(rows, hasLength(1));
    return rows.single;
  }

  // A ready form anchored to a fixed start so expected `nextDueDate` is
  // deterministic (we still derive it via the same helper, not by hand).
  RecurringFormData readyForm({
    String? id,
    String frequency = 'monthly',
    int interval = 1,
    DateTime? startDate,
  }) =>
      RecurringFormData(
        id: id,
        walletId: 'w1',
        categoryId: 'c1',
        type: 'expense',
        amount: 25,
        note: 'Netflix',
        frequency: frequency,
        interval: interval,
        startDate: startDate ?? DateTime(2026, 1, 15),
      );

  group('create', () {
    test('writes a pending rule, encodes the template, computes nextDueDate',
        () async {
      final h = buildTestContainer();
      final start = DateTime(2026, 1, 15);

      await ctrl(h.container)
          .create(readyForm(startDate: start, frequency: 'monthly', interval: 1));

      final r = await onlyRule(h.db);
      expect(r.userId, 'u1');
      expect(r.isPaused, isFalse);
      expect(r.syncStatus, 'pending'); // fresh insert defaults to pending
      expect(r.frequency, 'monthly');
      expect(r.interval, 1);
      // First occurrence fires AFTER the start date — verify via the same
      // helper the controller uses (this tests the wiring, not the math).
      expect(r.nextDueDate, addRecurringInterval(start, 'monthly', 1));

      final tpl = decodeRecurringTemplate(r.transactionTemplate);
      expect(tpl, {
        'type': 'expense',
        'amount': 25,
        'walletId': 'w1',
        'categoryId': 'c1',
        'note': 'Netflix',
      });
    });

    test('rejects an unready form (zero amount) and writes nothing', () async {
      final h = buildTestContainer();
      // amount 0 → !isReady → StateError caught into AsyncError.
      await ctrl(h.container).create(
        RecurringFormData(walletId: 'w1', categoryId: 'c1', amount: 0),
      );

      expect(h.container.read(recurringControllerProvider).hasError, isTrue);
      expect(await h.db.recurringRuleDao.watchAll().first, isEmpty);
    });

    test('rejects an unready form (missing wallet/category)', () async {
      final h = buildTestContainer();
      await ctrl(h.container).create(RecurringFormData(amount: 10));

      expect(h.container.read(recurringControllerProvider).hasError, isTrue);
      expect(await h.db.recurringRuleDao.watchAll().first, isEmpty);
    });
  });

  group('edit', () {
    test('recomputes nextDueDate, preserves isPaused + createdAt, re-flags sync',
        () async {
      final h = buildTestContainer();
      final start = DateTime(2026, 1, 15);
      await ctrl(h.container).create(readyForm(startDate: start));
      final before = await onlyRule(h.db);
      // Pretend the row was already mirrored so we can prove the flip back.
      await h.db.recurringRuleDao.markSynced(before.id);

      // Edit with a changed cadence; new start anchors a deterministic value.
      final newStart = DateTime(2026, 2, 1);
      await ctrl(h.container).edit(readyForm(
        id: before.id,
        startDate: newStart,
        frequency: 'weekly',
        interval: 2,
      ));

      final after = await h.db.recurringRuleDao.getById(before.id);
      expect(after!.frequency, 'weekly');
      expect(after.interval, 2);
      expect(after.nextDueDate, addRecurringInterval(newStart, 'weekly', 2));
      expect(after.isPaused, before.isPaused); // preserved
      expect(after.createdAt, before.createdAt); // preserved
      expect(after.syncStatus, 'pending'); // re-flagged
    });

    test('with a null id throws ArgumentError synchronously', () async {
      final h = buildTestContainer();
      // The null-id guard is OUTSIDE AsyncValue.guard, so it propagates
      // rather than landing in the AsyncError state.
      await expectLater(
        () => ctrl(h.container).edit(readyForm()),
        throwsArgumentError,
      );
    });
  });

  group('pause / resume', () {
    test('pause sets isPaused true + pending; resume flips back + pending',
        () async {
      final h = buildTestContainer();
      await ctrl(h.container).create(readyForm());
      final r = await onlyRule(h.db);
      await h.db.recurringRuleDao.markSynced(r.id);

      await ctrl(h.container).pause(r.id);
      var after = await h.db.recurringRuleDao.getById(r.id);
      expect(after!.isPaused, isTrue);
      expect(after.syncStatus, 'pending');

      // Re-mark synced so we can prove resume flips it back too.
      await h.db.recurringRuleDao.markSynced(r.id);
      await ctrl(h.container).resume(r.id);
      after = await h.db.recurringRuleDao.getById(r.id);
      expect(after!.isPaused, isFalse);
      expect(after.syncStatus, 'pending');
    });
  });

  test('delete removes the row', () async {
    final h = buildTestContainer();
    await ctrl(h.container).create(readyForm());
    final r = await onlyRule(h.db);

    await ctrl(h.container).delete(r.id);

    expect(await h.db.recurringRuleDao.getById(r.id), isNull);
  });

  group('decodeRecurringTemplate', () {
    test('round-trips a real template', () async {
      final h = buildTestContainer();
      await ctrl(h.container).create(readyForm());
      final r = await onlyRule(h.db);

      final tpl = decodeRecurringTemplate(r.transactionTemplate);
      expect(tpl['type'], 'expense');
      expect(tpl['walletId'], 'w1');
      expect(tpl['categoryId'], 'c1');
      expect(tpl['note'], 'Netflix');
    });

    test('returns an empty map on empty or malformed input', () {
      expect(decodeRecurringTemplate(''), isEmpty);
      expect(decodeRecurringTemplate('not json{'), isEmpty);
    });
  });
}
