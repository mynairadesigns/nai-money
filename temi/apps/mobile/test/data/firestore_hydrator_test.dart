import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temi_finance/data/local/app_database.dart';
import 'package:temi_finance/data/sync/firestore_hydrator.dart';

import '../helpers/test_harness.dart';

/// `FirestoreHydrator` pulls every synced subcollection into Drift on
/// sign-in, applying last-write-wins by `updatedAt` and SKIPPING any local
/// row still flagged `syncStatus='pending'` (the write-through engine wins
/// that race) — CLAUDE.md §8 "Pull-direction hydrate".
void main() {
  const uid = 'u1';
  final older = DateTime.utc(2026, 1, 1);
  final newer = DateTime.utc(2026, 5, 1);

  Future<void> putRemoteGoal(
    FakeFirebaseFirestore fs, {
    required String id,
    required String name,
    required DateTime updatedAt,
    double target = 1000,
  }) {
    return fs.collection('users/$uid/goals').doc(id).set({
      'id': id,
      'name': name,
      'targetAmount': target,
      'currentAmount': 0,
      'currency': 'USD',
      'iconName': 'label',
      'color': '8a4f37',
      'createdAt': Timestamp.fromDate(older),
      'updatedAt': Timestamp.fromDate(updatedAt),
    });
  }

  Future<void> seedLocalGoal(
    AppDatabase db, {
    required String id,
    required String name,
    required DateTime updatedAt,
    String syncStatus = 'synced',
  }) {
    return db.goalDao.insertOne(
      GoalsCompanion(
        id: Value(id),
        userId: const Value(uid),
        name: Value(name),
        targetAmount: const Value(1000),
        currentAmount: const Value(0),
        currency: const Value('USD'),
        iconName: const Value('label'),
        color: const Value('8a4f37'),
        createdAt: Value(older),
        updatedAt: Value(updatedAt),
        syncStatus: Value(syncStatus),
      ),
    );
  }

  Future<Goal?> localGoal(AppDatabase db, String id) =>
      db.goalDao.getById(id);

  test('upserts a remote row that has no local counterpart', () async {
    final h = buildTestContainer();
    final fs = FakeFirebaseFirestore();
    await putRemoteGoal(fs, id: 'g1', name: 'From cloud', updatedAt: newer);

    await FirestoreHydrator(fs, h.db).hydrate(uid);

    final g = await localGoal(h.db, 'g1');
    expect(g, isNotNull);
    expect(g!.name, 'From cloud');
    expect(g.syncStatus, 'synced'); // mapper stamps synced on pull
  });

  test('remote wins when its updatedAt is newer than the local row', () async {
    final h = buildTestContainer();
    final fs = FakeFirebaseFirestore();
    await seedLocalGoal(h.db, id: 'g1', name: 'stale local', updatedAt: older);
    await putRemoteGoal(fs, id: 'g1', name: 'fresh remote', updatedAt: newer);

    await FirestoreHydrator(fs, h.db).hydrate(uid);

    expect((await localGoal(h.db, 'g1'))!.name, 'fresh remote');
  });

  test('local wins when it is the same age or newer than remote', () async {
    final h = buildTestContainer();
    final fs = FakeFirebaseFirestore();
    await seedLocalGoal(h.db, id: 'g1', name: 'newer local', updatedAt: newer);
    await putRemoteGoal(fs, id: 'g1', name: 'older remote', updatedAt: older);

    await FirestoreHydrator(fs, h.db).hydrate(uid);

    expect((await localGoal(h.db, 'g1'))!.name, 'newer local');
  });

  test('a pending local row is never clobbered, even if remote is newer',
      () async {
    final h = buildTestContainer();
    final fs = FakeFirebaseFirestore();
    await seedLocalGoal(
      h.db,
      id: 'g1',
      name: 'unsynced edit',
      updatedAt: older,
      syncStatus: 'pending',
    );
    await putRemoteGoal(fs, id: 'g1', name: 'remote', updatedAt: newer);

    await FirestoreHydrator(fs, h.db).hydrate(uid);

    final g = await localGoal(h.db, 'g1');
    expect(g!.name, 'unsynced edit'); // write-through engine wins this race
    expect(g.syncStatus, 'pending'); // still queued for push
  });

  test('only rows under the given uid are pulled', () async {
    final h = buildTestContainer();
    final fs = FakeFirebaseFirestore();
    await putRemoteGoal(fs, id: 'mine', name: 'mine', updatedAt: newer);
    // A goal under a different user's path must not bleed into u1's Drift.
    await fs.collection('users/u2/goals').doc('theirs').set({
      'id': 'theirs',
      'name': 'theirs',
      'targetAmount': 1000,
      'currentAmount': 0,
      'currency': 'USD',
      'iconName': 'label',
      'color': '8a4f37',
      'createdAt': Timestamp.fromDate(older),
      'updatedAt': Timestamp.fromDate(newer),
    });

    await FirestoreHydrator(fs, h.db).hydrate(uid);

    expect(await localGoal(h.db, 'mine'), isNotNull);
    expect(await localGoal(h.db, 'theirs'), isNull);
  });

  test('an empty Firestore leaves Drift untouched', () async {
    final h = buildTestContainer();
    final fs = FakeFirebaseFirestore();
    await seedLocalGoal(h.db, id: 'g1', name: 'local only', updatedAt: newer);

    await FirestoreHydrator(fs, h.db).hydrate(uid);

    expect((await localGoal(h.db, 'g1'))!.name, 'local only');
  });
}
