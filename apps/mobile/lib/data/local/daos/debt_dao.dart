import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/debt_payments.dart';
import '../tables/debts.dart';

part 'debt_dao.g.dart';

@DriftAccessor(tables: [Debts, DebtPayments])
class DebtDao extends DatabaseAccessor<AppDatabase> with _$DebtDaoMixin {
  DebtDao(super.db);

  // --- Debts ---

  Stream<List<Debt>> watchAll() => select(debts).watch();

  Future<Debt?> getById(String id) =>
      (select(debts)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<void> insertOne(DebtsCompanion row) => into(debts).insert(row);

  Future<void> upsertDebt(DebtsCompanion row) =>
      into(debts).insertOnConflictUpdate(row);

  Future<bool> updateOne(DebtsCompanion row) => update(debts).replace(row);

  Future<int> deleteById(String id) =>
      (delete(debts)..where((d) => d.id.equals(id))).go();

  // --- DebtPayments (folded in per task convention) ---

  Stream<List<DebtPayment>> watchPaymentsForDebt(String debtId) =>
      (select(debtPayments)..where((p) => p.debtId.equals(debtId))).watch();

  /// One-shot read of a debt's payments. Used by the delete path, which
  /// needs the ids before the rows are gone and must not hold a stream
  /// subscription open inside a Drift transaction.
  Future<List<DebtPayment>> getPaymentsForDebt(String debtId) =>
      (select(debtPayments)..where((p) => p.debtId.equals(debtId))).get();

  /// Removes every payment recorded against [debtId]. The FK in
  /// `debt_payments` has no `ON DELETE CASCADE` and SQLite isn't running
  /// with `PRAGMA foreign_keys = ON`, so the cascade has to be explicit —
  /// otherwise deleting a debt strands its payments.
  Future<int> deletePaymentsForDebt(String debtId) =>
      (delete(debtPayments)..where((p) => p.debtId.equals(debtId))).go();

  Future<void> addPayment(DebtPaymentsCompanion row) =>
      into(debtPayments).insert(row);

  Future<void> upsertPayment(DebtPaymentsCompanion row) =>
      into(debtPayments).insertOnConflictUpdate(row);

  // --- Sync streams (both subtables) ---

  Stream<List<Debt>> watchPendingDebtsForUser(String userId) =>
      (select(debts)
            ..where(
              (d) => d.userId.equals(userId) & d.syncStatus.equals('pending'),
            ))
          .watch();

  Future<void> markDebtSynced(String id) =>
      (update(debts)..where((d) => d.id.equals(id)))
          .write(const DebtsCompanion(syncStatus: Value('synced')));

  Stream<List<DebtPayment>> watchPendingPaymentsForUser(String userId) =>
      (select(debtPayments)
            ..where(
              (p) => p.userId.equals(userId) & p.syncStatus.equals('pending'),
            ))
          .watch();

  Future<void> markPaymentSynced(String id) =>
      (update(debtPayments)..where((p) => p.id.equals(id)))
          .write(const DebtPaymentsCompanion(syncStatus: Value('synced')));
}
