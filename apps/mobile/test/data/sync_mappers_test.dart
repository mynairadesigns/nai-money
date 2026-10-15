import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:homa_finance/data/sync/sync_mappers.dart';

import '../helpers/test_harness.dart';

/// The sync mappers are the contract between Drift and Firestore. Two things
/// must hold and have regressed before (P5): dates round-trip as Firestore
/// `Timestamp` (not ISO strings), and remote numbers coerce to double. The
/// reverse mappers also stamp `syncStatus: 'synced'` so a hydrated row isn't
/// immediately re-pushed.
void main() {
  group('walletToFirestore ↔ walletFromFirestore', () {
    test('round-trips through an in-memory row preserving values + dates',
        () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      await seedWallet(db, id: 'w1', balance: 123.45, currency: 'EUR');

      final wallet = (await db.walletDao.watchAll().first).single;
      final doc = walletToFirestore(wallet);

      // Dates serialize as Firestore Timestamps, not strings.
      expect(doc['createdAt'], isA<Timestamp>());
      expect(doc['updatedAt'], isA<Timestamp>());
      expect(doc.containsKey('userId'), isFalse); // implicit in the doc path
      expect(doc.containsKey('syncStatus'), isFalse); // local-only

      final companion = walletFromFirestore(doc, 'u1');
      expect(companion.id.value, 'w1');
      expect(companion.userId.value, 'u1');
      expect(companion.balance.value, 123.45);
      expect(companion.currency.value, 'EUR');
      expect(companion.createdAt.value, wallet.createdAt);
      expect(companion.updatedAt.value, wallet.updatedAt);
      expect(companion.syncStatus.value, 'synced');
    });
  });

  group('transactionFromFirestore', () {
    test('coerces int amounts to double and reads Timestamp dates', () {
      final date = DateTime(2026, 5, 25, 10, 30);
      final doc = <String, dynamic>{
        'id': 't1',
        'walletId': 'w1',
        'categoryId': 'c1',
        'type': 'expense',
        'amount': 30, // arrives as an int from Firestore
        'currency': 'USD',
        'date': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(date),
        'updatedAt': Timestamp.fromDate(date),
      };

      final c = transactionFromFirestore(doc, 'u1');
      expect(c.amount.value, 30.0);
      expect(c.amount.value, isA<double>());
      expect(c.date.value, date);
      expect(c.userId.value, 'u1');
      expect(c.syncStatus.value, 'synced');
    });

    test('applies safe defaults for missing optional fields', () {
      final doc = <String, dynamic>{
        'id': 't2',
        'date': Timestamp.fromDate(DateTime(2026, 5, 25)),
      };
      final c = transactionFromFirestore(doc, 'u1');
      expect(c.type.value, 'expense');
      expect(c.amount.value, 0.0);
      expect(c.currency.value, 'USD');
      expect(c.isRecurring.value, false);
    });
  });

  group('budgetFromFirestore', () {
    test('reads nullable endDate Timestamp and number coercions', () {
      final start = DateTime(2026, 5, 1);
      final c = budgetFromFirestore(<String, dynamic>{
        'id': 'b1',
        'amount': 500, // int → double
        'startDate': Timestamp.fromDate(start),
        'endDate': null,
      }, 'u1');
      expect(c.amount.value, 500.0);
      expect(c.startDate.value, start);
      expect(c.endDate.value, isNull);
      expect(c.thresholdPercent.value, 80); // default
      expect(c.syncStatus.value, 'synced');
    });
  });
}
