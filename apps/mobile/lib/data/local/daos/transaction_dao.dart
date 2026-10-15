import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/transactions.dart';

part 'transaction_dao.g.dart';

@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  Stream<List<Transaction>> watchAll() => select(transactions).watch();

  Future<Transaction?> getById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertOne(TransactionsCompanion row) =>
      into(transactions).insert(row);

  Future<void> upsertOne(TransactionsCompanion row) =>
      into(transactions).insertOnConflictUpdate(row);

  Future<bool> updateOne(TransactionsCompanion row) =>
      update(transactions).replace(row);

  Future<int> deleteById(String id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  Stream<List<Transaction>> watchByWallet(String walletId) =>
      (select(transactions)
            ..where((t) => t.walletId.equals(walletId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  /// Rows owned by [userId] with `date` in the half-open range
  /// `[start, end)`, newest first.
  ///
  /// Both constraints matter and both were once missing:
  /// - **`userId`**: Drift survives sign-out, so a device where two
  ///   accounts have signed in holds both users' rows. Without this the
  ///   query summed across accounts.
  /// - **half-open**: every range in the app is built with an exclusive
  ///   end (`defaultRangeForPeriod`, `ReportsFilter.range()`), so the
  ///   inclusive `isBetweenValues` counted a row stamped exactly midnight
  ///   on the 1st in *both* the old and new period — the same
  ///   double-count [countForMonth] documents.
  Stream<List<Transaction>> watchByDateRangeForUser({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) =>
      (select(transactions)
            ..where(
              (t) =>
                  t.userId.equals(userId) &
                  t.date.isBiggerOrEqualValue(start) &
                  t.date.isSmallerThanValue(end),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  /// Counts rows for [userId] with `date` in `[start, end)`. Used by the
  /// P6 free-tier enforcement to gate the 100-tx-per-month ceiling
  /// without loading the rows themselves.
  Future<int> countForMonth({
    required String userId,
    required DateTime start,
    required DateTime end,
  }) async {
    final expr = countAll();
    // Half-open [start, end): `end` is the first instant of the next month,
    // so it must be EXCLUDED — `isBetweenValues` is inclusive and would
    // double-count a midnight-on-the-1st row across two months.
    final query = selectOnly(transactions)
      ..addColumns([expr])
      ..where(
        transactions.userId.equals(userId) &
            transactions.date.isBiggerOrEqualValue(start) &
            transactions.date.isSmallerThanValue(end),
      );
    final row = await query.getSingle();
    return row.read(expr) ?? 0;
  }

  /// All transactions for [userId], newest first.
  Stream<List<Transaction>> watchAllForUser(String userId) =>
      (select(transactions)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  /// Most recent N transactions for [userId], newest first. Used by the
  /// Home dashboard's "Recent" card.
  Stream<List<Transaction>> watchRecentForUser(String userId, int limit) =>
      (select(transactions)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)])
            ..limit(limit))
          .watch();

  /// Rows owned by [userId] that are still waiting to mirror to Firestore.
  /// [FirestoreSyncService] subscribes to this stream per user.
  Stream<List<Transaction>> watchPendingForUser(String userId) =>
      (select(transactions)
            ..where(
              (t) => t.userId.equals(userId) & t.syncStatus.equals('pending'),
            ))
          .watch();

  /// Flips a single row's `syncStatus` to `'synced'`. Called by the sync
  /// engine after a successful Firestore mirror write.
  Future<void> markSynced(String id) =>
      (update(transactions)..where((t) => t.id.equals(id)))
          .write(const TransactionsCompanion(syncStatus: Value('synced')));

  /// Repoints a transaction's attachment to its permanent Storage URL after
  /// the receipt move-on-save (P4.2.1). Clears the temp `attachmentLocalPath`
  /// and re-flags `syncStatus='pending'` so the permanent URL mirrors to
  /// Firestore (the mapper mirrors `attachmentUrl`, never the local path).
  Future<void> setReceiptAttachment({
    required String id,
    required String attachmentUrl,
    required DateTime updatedAt,
  }) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          attachmentUrl: Value(attachmentUrl),
          attachmentLocalPath: const Value(null),
          updatedAt: Value(updatedAt),
          syncStatus: const Value('pending'),
        ),
      );

  /// Bulk delete by ids. Returns the number of rows removed. The caller is
  /// responsible for wallet balance reconciliation and Firestore mirror
  /// cleanup (see `TransactionsController.deleteMany`).
  Future<int> deleteByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(0);
    return (delete(transactions)..where((t) => t.id.isIn(ids))).go();
  }

  /// Loads multiple rows by id in a single query.
  Future<List<Transaction>> getByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(transactions)..where((t) => t.id.isIn(ids))).get();
  }
}
