import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/wallets.dart';

part 'wallet_dao.g.dart';

@DriftAccessor(tables: [Wallets])
class WalletDao extends DatabaseAccessor<AppDatabase> with _$WalletDaoMixin {
  WalletDao(super.db);

  Stream<List<Wallet>> watchAll() => select(wallets).watch();

  Future<Wallet?> getById(String id) =>
      (select(wallets)..where((w) => w.id.equals(id))).getSingleOrNull();

  Future<void> insertOne(WalletsCompanion row) => into(wallets).insert(row);

  /// Insert-or-replace by primary key. Used by the Firestore→Drift
  /// hydrator (P2.7) to materialise remote rows.
  Future<void> upsertOne(WalletsCompanion row) =>
      into(wallets).insertOnConflictUpdate(row);

  Future<bool> updateOne(WalletsCompanion row) => update(wallets).replace(row);

  Future<int> deleteById(String id) =>
      (delete(wallets)..where((w) => w.id.equals(id))).go();

  /// Rows owned by [userId] that are still waiting to mirror to Firestore.
  /// [FirestoreSyncService] subscribes to this stream per user.
  Stream<List<Wallet>> watchPendingForUser(String userId) =>
      (select(wallets)
            ..where(
              (w) => w.userId.equals(userId) & w.syncStatus.equals('pending'),
            ))
          .watch();

  /// Flips a single row's `syncStatus` to `'synced'`. Called by the sync
  /// engine after a successful Firestore mirror write.
  Future<void> markSynced(String id) =>
      (update(wallets)..where((w) => w.id.equals(id)))
          .write(const WalletsCompanion(syncStatus: Value('synced')));
}
