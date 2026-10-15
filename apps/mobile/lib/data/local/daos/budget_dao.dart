import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/budgets.dart';

part 'budget_dao.g.dart';

@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Stream<List<Budget>> watchAll() => select(budgets).watch();

  Future<Budget?> getById(String id) =>
      (select(budgets)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<void> insertOne(BudgetsCompanion row) => into(budgets).insert(row);

  Future<void> upsertOne(BudgetsCompanion row) =>
      into(budgets).insertOnConflictUpdate(row);

  Future<bool> updateOne(BudgetsCompanion row) => update(budgets).replace(row);

  Future<int> deleteById(String id) =>
      (delete(budgets)..where((b) => b.id.equals(id))).go();

  Stream<List<Budget>> watchPendingForUser(String userId) =>
      (select(budgets)
            ..where(
              (b) => b.userId.equals(userId) & b.syncStatus.equals('pending'),
            ))
          .watch();

  Future<void> markSynced(String id) =>
      (update(budgets)..where((b) => b.id.equals(id)))
          .write(const BudgetsCompanion(syncStatus: Value('synced')));
}
