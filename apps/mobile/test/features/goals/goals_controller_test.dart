import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homa_finance/data/local/app_database.dart';
import 'package:homa_finance/features/goals/providers/goal_progress_provider.dart';
import 'package:homa_finance/features/goals/providers/goals_controller.dart';
import 'package:homa_finance/features/goals/providers/goals_list_provider.dart';

import '../../helpers/test_harness.dart';

/// `GoalsController` drives goal create/edit/delete + contributions. The
/// contribution path increments `currentAmount` in a Drift transaction and
/// stamps `completedAt` the first time the running total reaches the target
/// (CLAUDE.md §6). `goalProgressProvider` is the pure progress derivation.
void main() {
  GoalsController ctrl(ProviderContainer c) =>
      c.read(goalsControllerProvider.notifier);

  Future<Goal> onlyGoal(AppDatabase db) async {
    final rows = await db.goalDao.watchAll().first;
    expect(rows, hasLength(1));
    return rows.single;
  }

  group('create', () {
    test('seeds currentAmount 0, completedAt null', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 1000));

      final g = await onlyGoal(h.db);
      expect(g.name, 'Trip');
      expect(g.targetAmount, 1000);
      expect(g.currentAmount, 0);
      expect(g.completedAt, isNull);
      expect(g.userId, 'u1');
      expect(g.syncStatus, 'pending');
    });

    test('rejects a form with no name or zero target', () async {
      final h = buildTestContainer();
      await ctrl(h.container).create(GoalFormData(name: '', targetAmount: 0));
      expect(h.container.read(goalsControllerProvider).hasError, isTrue);
    });
  });

  group('addContribution', () {
    test('partial contribution increments without completing', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 1000));
      final g = await onlyGoal(h.db);

      await ctrl(h.container).addContribution(g.id, 300);

      final after = await h.db.goalDao.getById(g.id);
      expect(after!.currentAmount, 300);
      expect(after.completedAt, isNull);
      expect(after.syncStatus, 'pending');
    });

    test('reaching the target stamps completedAt', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 1000));
      final g = await onlyGoal(h.db);

      await ctrl(h.container).addContribution(g.id, 600);
      await ctrl(h.container).addContribution(g.id, 400);

      final after = await h.db.goalDao.getById(g.id);
      expect(after!.currentAmount, 1000);
      expect(after.completedAt, isNotNull);
    });

    test('completedAt is stamped once and not overwritten on later adds',
        () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 100));
      final g = await onlyGoal(h.db);

      await ctrl(h.container).addContribution(g.id, 100);
      final firstStamp = (await h.db.goalDao.getById(g.id))!.completedAt;
      await ctrl(h.container).addContribution(g.id, 50);
      final after = await h.db.goalDao.getById(g.id);

      expect(after!.currentAmount, 150);
      expect(after.completedAt, firstStamp); // unchanged
    });

    test('rejects a non-positive contribution', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 100));
      final g = await onlyGoal(h.db);

      await expectLater(
        () => ctrl(h.container).addContribution(g.id, 0),
        throwsArgumentError,
      );
      final after = await h.db.goalDao.getById(g.id);
      expect(after!.currentAmount, 0);
    });
  });

  test('markCompleted tops up to target and stamps completedAt', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(GoalFormData(name: 'Trip', targetAmount: 1000));
    final g = await onlyGoal(h.db);

    await ctrl(h.container).markCompleted(g.id);

    final after = await h.db.goalDao.getById(g.id);
    expect(after!.currentAmount, 1000);
    expect(after.completedAt, isNotNull);
  });

  test('markCompleted never decreases an over-funded goal', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(GoalFormData(name: 'Trip', targetAmount: 1000));
    var g = await onlyGoal(h.db);
    await ctrl(h.container).addContribution(g.id, 1500); // over target
    g = (await h.db.goalDao.getById(g.id))!;

    await ctrl(h.container).markCompleted(g.id);

    final after = await h.db.goalDao.getById(g.id);
    expect(after!.currentAmount, 1500); // kept, not clamped down to target
  });

  test('edit preserves currentAmount and completedAt', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(GoalFormData(name: 'Trip', targetAmount: 1000));
    var g = await onlyGoal(h.db);
    await ctrl(h.container).addContribution(g.id, 250);
    g = (await h.db.goalDao.getById(g.id))!;

    await ctrl(h.container).edit(
      GoalFormData(id: g.id, name: 'Big Trip', targetAmount: 2000),
    );

    final after = await h.db.goalDao.getById(g.id);
    expect(after!.name, 'Big Trip');
    expect(after.targetAmount, 2000);
    expect(after.currentAmount, 250); // untouched
    expect(after.syncStatus, 'pending');
  });

  test('delete removes the row', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(GoalFormData(name: 'Trip', targetAmount: 1000));
    final g = await onlyGoal(h.db);

    await ctrl(h.container).delete(g.id);

    expect(await h.db.goalDao.getById(g.id), isNull);
  });

  group('isNewlyCompleted', () {
    test('true only when completedAt flips null → set', () async {
      final h = buildTestContainer();
      final c = ctrl(h.container);
      await c.create(GoalFormData(name: 'G', targetAmount: 100));
      final open = await onlyGoal(h.db);
      final done = open.copyWith(completedAt: Value(DateTime.now()));

      expect(c.isNewlyCompleted(open, done), isTrue);
      expect(c.isNewlyCompleted(open, open), isFalse); // still open
      expect(c.isNewlyCompleted(done, done), isFalse); // already done
      expect(c.isNewlyCompleted(null, done), isFalse); // no prior row
    });
  });

  group('goalProgressProvider', () {
    // The provider reads through goalsListProvider (a Drift stream), so read
    // its first emission via a listener rather than a one-shot `.read`.
    Future<GoalProgress?> progress(ProviderContainer c, String id) async {
      final completer = Completer<GoalProgress?>();
      // Listening keeps the list provider's Drift stream alive AND drives the
      // re-read; reading goalProgressProvider directly never subscribes it.
      final sub = c.listen(
        goalsListProvider,
        (_, _) {
          final v = c.read(goalProgressProvider(id));
          if (v != null && !completer.isCompleted) completer.complete(v);
        },
        fireImmediately: true,
      );
      try {
        return await completer.future.timeout(const Duration(seconds: 5));
      } finally {
        sub.close();
      }
    }

    test('pct is currentAmount / targetAmount, clamped to 1', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 1000));
      var g = await onlyGoal(h.db);
      await ctrl(h.container).addContribution(g.id, 250);

      final p = await progress(h.container, g.id);
      expect(p!.pct, closeTo(0.25, 1e-9));
    });

    test('pct clamps to 1 when over target', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 100));
      final g = await onlyGoal(h.db);
      await ctrl(h.container).addContribution(g.id, 250);

      final p = await progress(h.container, g.id);
      expect(p!.pct, 1.0);
    });

    test('daysRemaining + requiredPerMonth derive from the deadline', () async {
      final h = buildTestContainer();
      final deadline = DateTime.now().add(const Duration(days: 60));
      await ctrl(h.container).create(
        GoalFormData(name: 'Trip', targetAmount: 1200, deadline: deadline),
      );
      final g = await onlyGoal(h.db);

      final p = await progress(h.container, g.id);
      expect(p!.daysRemaining, inInclusiveRange(58, 60));
      // remaining 1200 over ~2 months → ~600/mo.
      expect(p.requiredPerMonth, closeTo(600, 60));
    });

    test('no deadline → null daysRemaining and requiredPerMonth', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 1000));
      final g = await onlyGoal(h.db);

      final p = await progress(h.container, g.id);
      expect(p!.daysRemaining, isNull);
      expect(p.requiredPerMonth, isNull);
    });

    test('returns null for an unknown goal id', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(GoalFormData(name: 'Trip', targetAmount: 1000));

      // Wait for the list stream to emit (avoid `.future` — it leaves a
      // pending completer that errors at dispose), then read the unknown id.
      final ready = Completer<void>();
      final sub = h.container.listen<AsyncValue<List<Goal>>>(
        goalsListProvider,
        (_, next) {
          if (next.hasValue && !ready.isCompleted) ready.complete();
        },
        fireImmediately: true,
      );
      try {
        await ready.future.timeout(const Duration(seconds: 5));
        expect(h.container.read(goalProgressProvider('nope')), isNull);
      } finally {
        sub.close();
      }
    });
  });
}
