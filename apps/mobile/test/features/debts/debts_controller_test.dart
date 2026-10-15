import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homa_finance/core/providers/firestore_provider.dart';
import 'package:homa_finance/data/local/app_database.dart';
import 'package:homa_finance/features/debts/data/debt_status.dart';
import 'package:homa_finance/features/debts/providers/debts_controller.dart';

import '../../helpers/test_harness.dart';

/// `DebtsController` owns debt create/edit/delete + the payment math that
/// decrements `remainingAmount` atomically and stamps `settledAt` when the
/// balance reaches zero (CLAUDE.md §6 — payment + parent flip in one Drift
/// transaction, both rows reset to `syncStatus='pending'`). `debtStatus` is
/// the pure UI-facing derivation (the persisted `status` column is ignored).
void main() {
  DebtsController ctrl(ProviderContainer c) =>
      c.read(debtsControllerProvider.notifier);

  Future<Debt> onlyDebt(AppDatabase db) async {
    final rows = await db.debtDao.watchAll().first;
    expect(rows, hasLength(1));
    return rows.single;
  }

  group('create', () {
    test('seeds remainingAmount = originalAmount, status open', () async {
      final h = buildTestContainer();
      await ctrl(h.container).create(
        DebtFormData(type: 'lent', contactName: 'Alice', originalAmount: 250),
      );

      final d = await onlyDebt(h.db);
      expect(d.contactName, 'Alice');
      expect(d.originalAmount, 250);
      expect(d.remainingAmount, 250);
      expect(d.status, 'open');
      expect(d.settledAt, isNull);
      expect(d.userId, 'u1');
      expect(d.syncStatus, 'pending'); // fresh insert defaults to pending
    });

    test('rejects a form with no contact or zero amount', () async {
      final h = buildTestContainer();
      await ctrl(h.container).create(DebtFormData(contactName: '', originalAmount: 0));
      expect(h.container.read(debtsControllerProvider).hasError, isTrue);
    });
  });

  group('addPayment', () {
    test('partial payment decrements remaining, leaves it open', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Bob', originalAmount: 100));
      final d = await onlyDebt(h.db);

      await ctrl(h.container).addPayment(debtId: d.id, amount: 40);

      final after = await h.db.debtDao.getById(d.id);
      expect(after!.remainingAmount, 60);
      expect(after.settledAt, isNull);
      expect(after.syncStatus, 'pending');
      // The payment row landed in the same transaction.
      final payments = await h.db.debtDao.watchPaymentsForDebt(d.id).first;
      expect(payments, hasLength(1));
      expect(payments.single.amount, 40);
    });

    test('full payment zeroes remaining and stamps settledAt', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Bob', originalAmount: 100));
      final d = await onlyDebt(h.db);

      await ctrl(h.container).addPayment(debtId: d.id, amount: 100);

      final after = await h.db.debtDao.getById(d.id);
      expect(after!.remainingAmount, 0);
      expect(after.settledAt, isNotNull);
    });

    test('overpayment clamps remaining to 0 (never negative)', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Bob', originalAmount: 100));
      final d = await onlyDebt(h.db);

      await ctrl(h.container).addPayment(debtId: d.id, amount: 150);

      final after = await h.db.debtDao.getById(d.id);
      expect(after!.remainingAmount, 0);
      expect(after.settledAt, isNotNull);
    });

    test('rejects a non-positive amount', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Bob', originalAmount: 100));
      final d = await onlyDebt(h.db);

      await ctrl(h.container).addPayment(debtId: d.id, amount: 0);
      expect(h.container.read(debtsControllerProvider).hasError, isTrue);
      // No payment row written.
      final payments = await h.db.debtDao.watchPaymentsForDebt(d.id).first;
      expect(payments, isEmpty);
    });
  });

  test('markSettled zeroes remaining and stamps settledAt', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(DebtFormData(contactName: 'Carol', originalAmount: 80));
    final d = await onlyDebt(h.db);

    await ctrl(h.container).markSettled(d.id);

    final after = await h.db.debtDao.getById(d.id);
    expect(after!.remainingAmount, 0);
    expect(after.settledAt, isNotNull);
    expect(after.syncStatus, 'pending');
  });

  test('edit preserves remainingAmount and resets syncStatus', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(DebtFormData(contactName: 'Dan', originalAmount: 200));
    var d = await onlyDebt(h.db);
    await ctrl(h.container).addPayment(debtId: d.id, amount: 50);
    // Mark synced so we can prove edit flips it back to pending.
    await h.db.debtDao.markDebtSynced(d.id);

    d = (await h.db.debtDao.getById(d.id))!;
    await ctrl(h.container).edit(
      DebtFormData(
        id: d.id,
        type: d.type,
        contactName: 'Daniel',
        originalAmount: 999, // changing the original must NOT touch remaining
      ),
    );

    final after = await h.db.debtDao.getById(d.id);
    expect(after!.contactName, 'Daniel');
    expect(after.originalAmount, 999);
    expect(after.remainingAmount, 150); // payment math owns this
    expect(after.syncStatus, 'pending');
  });

  test('delete removes the row', () async {
    final h = buildTestContainer();
    await ctrl(h.container)
        .create(DebtFormData(contactName: 'Eve', originalAmount: 10));
    final d = await onlyDebt(h.db);

    await ctrl(h.container).delete(d.id);

    expect(await h.db.debtDao.getById(d.id), isNull);
  });

  group('delete cascades to payments', () {
    test('payments go with the debt instead of being orphaned', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Frank', originalAmount: 100));
      final d = await onlyDebt(h.db);
      await ctrl(h.container).addPayment(debtId: d.id, amount: 30);
      await ctrl(h.container).addPayment(debtId: d.id, amount: 20);
      expect(await h.db.debtDao.getPaymentsForDebt(d.id), hasLength(2));

      await ctrl(h.container).delete(d.id);

      expect(await h.db.debtDao.getById(d.id), isNull);
      // Previously these survived: they kept syncing to Firestore and
      // "Reset all data" cascaded via surviving debts, so it missed them.
      expect(await h.db.debtDao.getPaymentsForDebt(d.id), isEmpty);
    });

    test('leaves other debts and their payments untouched', () async {
      final h = buildTestContainer();
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Gina', originalAmount: 100));
      final keep = await onlyDebt(h.db);
      await ctrl(h.container).addPayment(debtId: keep.id, amount: 10);

      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Hank', originalAmount: 50));
      final rows = await h.db.debtDao.watchAll().first;
      final doomed = rows.firstWhere((r) => r.id != keep.id);
      await ctrl(h.container).addPayment(debtId: doomed.id, amount: 5);

      await ctrl(h.container).delete(doomed.id);

      expect(await h.db.debtDao.getPaymentsForDebt(doomed.id), isEmpty);
      expect(await h.db.debtDao.getPaymentsForDebt(keep.id), hasLength(1));
      expect(await h.db.debtDao.getById(keep.id), isNotNull);
    });

    test('mirrors the debt + payment deletes to Firestore', () async {
      final h = buildTestContainer();
      final firestore = h.container.read(firestoreProvider);
      await ctrl(h.container)
          .create(DebtFormData(contactName: 'Ivy', originalAmount: 100));
      final d = await onlyDebt(h.db);
      await ctrl(h.container).addPayment(debtId: d.id, amount: 25);
      final paymentId = (await h.db.debtDao.getPaymentsForDebt(d.id)).single.id;

      // Stand in for the write-through engine having already mirrored
      // both rows — the delete must clear them, not leave them behind.
      await firestore.doc('users/u1/debts/${d.id}').set({'id': d.id});
      await firestore
          .doc('users/u1/debtPayments/$paymentId')
          .set({'id': paymentId});

      await ctrl(h.container).delete(d.id);

      expect((await firestore.doc('users/u1/debts/${d.id}').get()).exists,
          isFalse);
      expect(
        (await firestore.doc('users/u1/debtPayments/$paymentId').get()).exists,
        isFalse,
      );
    });
  });

  group('debtStatus derivation', () {
    final now = DateTime(2026, 5, 27, 10); // fixed clock

    // Build a real Debt row, then vary fields via copyWith.
    Future<Debt> baseDebt(AppDatabase db) async {
      final ts = DateTime.utc(2026, 1, 1);
      await db.debtDao.insertOne(
        DebtsCompanion(
          id: const Value('d1'),
          userId: const Value('u1'),
          type: const Value('lent'),
          contactName: const Value('X'),
          originalAmount: const Value(100),
          remainingAmount: const Value(100),
          currency: const Value('USD'),
          status: const Value('open'),
          createdAt: Value(ts),
          updatedAt: Value(ts),
        ),
      );
      return (await db.debtDao.getById('d1'))!;
    }

    test('settled when remaining is ~0 regardless of due date', () async {
      final h = buildTestContainer();
      final d = await baseDebt(h.db);
      expect(
        debtStatus(d.copyWith(remainingAmount: 0, dueDate: Value(now)), now: now),
        DebtStatus.settled,
      );
    });

    test('open when there is no due date', () async {
      final h = buildTestContainer();
      final d = await baseDebt(h.db);
      expect(debtStatus(d, now: now), DebtStatus.open);
    });

    test('overdue when due date is before today', () async {
      final h = buildTestContainer();
      final d = await baseDebt(h.db);
      final yesterday = now.subtract(const Duration(days: 1));
      expect(
        debtStatus(d.copyWith(dueDate: Value(yesterday)), now: now),
        DebtStatus.overdue,
      );
    });

    test('dueSoon when due within 7 days (inclusive)', () async {
      final h = buildTestContainer();
      final d = await baseDebt(h.db);
      final in3 = now.add(const Duration(days: 3));
      final in7 = now.add(const Duration(days: 7));
      expect(debtStatus(d.copyWith(dueDate: Value(in3)), now: now), DebtStatus.dueSoon);
      expect(debtStatus(d.copyWith(dueDate: Value(in7)), now: now), DebtStatus.dueSoon);
    });

    test('open when due more than 7 days out', () async {
      final h = buildTestContainer();
      final d = await baseDebt(h.db);
      final in30 = now.add(const Duration(days: 30));
      expect(debtStatus(d.copyWith(dueDate: Value(in30)), now: now), DebtStatus.open);
    });
  });
}
