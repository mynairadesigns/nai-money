import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/recurring_rules.dart';

part 'recurring_rule_dao.g.dart';

@DriftAccessor(tables: [RecurringRules])
class RecurringRuleDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringRuleDaoMixin {
  RecurringRuleDao(super.db);

  Stream<List<RecurringRule>> watchAll() => select(recurringRules).watch();

  Future<RecurringRule?> getById(String id) =>
      (select(recurringRules)..where((r) => r.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertOne(RecurringRulesCompanion row) =>
      into(recurringRules).insert(row);

  Future<void> upsertOne(RecurringRulesCompanion row) =>
      into(recurringRules).insertOnConflictUpdate(row);

  Future<bool> updateOne(RecurringRulesCompanion row) =>
      update(recurringRules).replace(row);

  Future<int> deleteById(String id) =>
      (delete(recurringRules)..where((r) => r.id.equals(id))).go();

  Stream<List<RecurringRule>> watchPendingForUser(String userId) =>
      (select(recurringRules)
            ..where(
              (r) => r.userId.equals(userId) & r.syncStatus.equals('pending'),
            ))
          .watch();

  Future<void> markSynced(String id) =>
      (update(recurringRules)..where((r) => r.id.equals(id)))
          .write(const RecurringRulesCompanion(syncStatus: Value('synced')));
}
