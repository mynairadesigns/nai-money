import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/goals.dart';

part 'goal_dao.g.dart';

@DriftAccessor(tables: [Goals])
class GoalDao extends DatabaseAccessor<AppDatabase> with _$GoalDaoMixin {
  GoalDao(super.db);

  Stream<List<Goal>> watchAll() => select(goals).watch();

  Future<Goal?> getById(String id) =>
      (select(goals)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<void> insertOne(GoalsCompanion row) => into(goals).insert(row);

  Future<void> upsertOne(GoalsCompanion row) =>
      into(goals).insertOnConflictUpdate(row);

  Future<bool> updateOne(GoalsCompanion row) => update(goals).replace(row);

  Future<int> deleteById(String id) =>
      (delete(goals)..where((g) => g.id.equals(id))).go();

  Stream<List<Goal>> watchPendingForUser(String userId) =>
      (select(goals)
            ..where(
              (g) => g.userId.equals(userId) & g.syncStatus.equals('pending'),
            ))
          .watch();

  Future<void> markSynced(String id) =>
      (update(goals)..where((g) => g.id.equals(id)))
          .write(const GoalsCompanion(syncStatus: Value('synced')));
}
