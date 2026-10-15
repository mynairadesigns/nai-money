import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/categories.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Stream<List<Category>> watchAll() => select(categories).watch();

  Future<Category?> getById(String id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<void> insertOne(CategoriesCompanion row) =>
      into(categories).insert(row);

  Future<void> upsertOne(CategoriesCompanion row) =>
      into(categories).insertOnConflictUpdate(row);

  Future<bool> updateOne(CategoriesCompanion row) =>
      update(categories).replace(row);

  Future<int> deleteById(String id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();

  /// Rows owned by [userId] that are still waiting to mirror to Firestore.
  /// [FirestoreSyncService] subscribes to this stream per user.
  Stream<List<Category>> watchPendingForUser(String userId) =>
      (select(categories)
            ..where(
              (c) => c.userId.equals(userId) & c.syncStatus.equals('pending'),
            ))
          .watch();

  /// Flips a single row's `syncStatus` to `'synced'`. Called by the sync
  /// engine after a successful Firestore mirror write.
  Future<void> markSynced(String id) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(syncStatus: Value('synced')));
}
