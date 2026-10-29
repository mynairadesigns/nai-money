import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:temi_finance/data/local/app_database.dart';

import '../helpers/test_harness.dart';

TransactionsCompanion _tx({
  required String id,
  required String userId,
  required DateTime date,
  double amount = 10,
  String walletId = 'w1',
  String syncStatus = 'pending',
}) {
  final now = DateTime.now().toUtc();
  return TransactionsCompanion(
    id: Value(id),
    userId: Value(userId),
    walletId: Value(walletId),
    categoryId: const Value('c1'),
    type: const Value('expense'),
    amount: Value(amount),
    currency: const Value('USD'),
    date: Value(date),
    createdAt: Value(now),
    updatedAt: Value(now),
    syncStatus: Value(syncStatus),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = newTestDatabase());
  tearDown(() => db.close());

  group('countForMonth', () {
    test('counts only this user, this month, within [start, end)', () async {
      final dao = db.transactionDao;
      await dao.insertOne(_tx(id: 't1', userId: 'u1', date: DateTime(2026, 5, 2)));
      await dao.insertOne(_tx(id: 't2', userId: 'u1', date: DateTime(2026, 5, 31)));
      // Boundary: June 1 is the exclusive end → not counted.
      await dao.insertOne(_tx(id: 't3', userId: 'u1', date: DateTime(2026, 6, 1)));
      // Different user, same month → not counted.
      await dao.insertOne(_tx(id: 't4', userId: 'u2', date: DateTime(2026, 5, 10)));

      final count = await dao.countForMonth(
        userId: 'u1',
        start: DateTime(2026, 5),
        end: DateTime(2026, 6),
      );
      expect(count, 2);
    });

    test('returns 0 when the user has no rows in range', () async {
      final count = await db.transactionDao.countForMonth(
        userId: 'nobody',
        start: DateTime(2026, 5),
        end: DateTime(2026, 6),
      );
      expect(count, 0);
    });
  });

  group('watchByDateRangeForUser', () {
    test('excludes other users — Drift survives sign-out', () async {
      final dao = db.transactionDao;
      await dao.insertOne(
        _tx(id: 't1', userId: 'u1', date: DateTime(2026, 5, 2), amount: 10),
      );
      // A second account that signed in on this same device. Summing
      // these together was the reports/budgets data bug.
      await dao.insertOne(
        _tx(id: 't2', userId: 'u2', date: DateTime(2026, 5, 3), amount: 999),
      );

      final rows = await dao
          .watchByDateRangeForUser(
            userId: 'u1',
            start: DateTime(2026, 5),
            end: DateTime(2026, 6),
          )
          .first;

      expect(rows.map((t) => t.id), ['t1']);
    });

    test('range is half-open — end belongs to the next period', () async {
      final dao = db.transactionDao;
      // Last instant before the window.
      await dao.insertOne(
        _tx(id: 'before', userId: 'u1', date: DateTime(2026, 4, 30, 23, 59)),
      );
      // Exactly the inclusive start → included.
      await dao.insertOne(
        _tx(id: 'start', userId: 'u1', date: DateTime(2026, 5)),
      );
      await dao.insertOne(
        _tx(id: 'mid', userId: 'u1', date: DateTime(2026, 5, 15)),
      );
      // Exactly the exclusive end → excluded. Previously `isBetweenValues`
      // counted this row in BOTH May and June.
      await dao.insertOne(
        _tx(id: 'end', userId: 'u1', date: DateTime(2026, 6)),
      );

      final rows = await dao
          .watchByDateRangeForUser(
            userId: 'u1',
            start: DateTime(2026, 5),
            end: DateTime(2026, 6),
          )
          .first;

      expect(rows.map((t) => t.id).toSet(), {'start', 'mid'});
    });

    test('agrees with countForMonth on the same window', () async {
      final dao = db.transactionDao;
      for (final d in [
        DateTime(2026, 5),
        DateTime(2026, 5, 20),
        DateTime(2026, 6), // boundary — excluded by both
      ]) {
        await dao.insertOne(
          _tx(id: 't${d.month}${d.day}', userId: 'u1', date: d),
        );
      }

      final rows = await dao
          .watchByDateRangeForUser(
            userId: 'u1',
            start: DateTime(2026, 5),
            end: DateTime(2026, 6),
          )
          .first;
      final count = await dao.countForMonth(
        userId: 'u1',
        start: DateTime(2026, 5),
        end: DateTime(2026, 6),
      );

      expect(rows.length, count);
    });

    test('returns newest first', () async {
      final dao = db.transactionDao;
      await dao.insertOne(
        _tx(id: 'old', userId: 'u1', date: DateTime(2026, 5, 2)),
      );
      await dao.insertOne(
        _tx(id: 'new', userId: 'u1', date: DateTime(2026, 5, 28)),
      );

      final rows = await dao
          .watchByDateRangeForUser(
            userId: 'u1',
            start: DateTime(2026, 5),
            end: DateTime(2026, 6),
          )
          .first;

      expect(rows.map((t) => t.id), ['new', 'old']);
    });
  });

  group('setReceiptAttachment', () {
    test('repoints url, clears local path, and re-flags for sync', () async {
      final dao = db.transactionDao;
      final now = DateTime.now().toUtc();
      await dao.insertOne(
        _tx(id: 't1', userId: 'u1', date: DateTime(2026, 5, 2), syncStatus: 'synced')
            .copyWith(
          attachmentLocalPath: const Value('users/u1/receipts/temp/123.jpg'),
        ),
      );

      await dao.setReceiptAttachment(
        id: 't1',
        attachmentUrl: 'https://storage/perm/t1.jpg',
        updatedAt: now,
      );

      final row = await dao.getById('t1');
      expect(row!.attachmentUrl, 'https://storage/perm/t1.jpg');
      expect(row.attachmentLocalPath, isNull);
      expect(row.syncStatus, 'pending');
    });
  });

  group('pending sync lifecycle', () {
    test('watchPendingForUser surfaces pending rows; markSynced clears', () async {
      final dao = db.transactionDao;
      await dao.insertOne(_tx(id: 't1', userId: 'u1', date: DateTime(2026, 5, 2)));

      final pendingBefore = await dao.watchPendingForUser('u1').first;
      expect(pendingBefore.map((t) => t.id), ['t1']);

      await dao.markSynced('t1');

      final pendingAfter = await dao.watchPendingForUser('u1').first;
      expect(pendingAfter, isEmpty);
    });
  });
}
