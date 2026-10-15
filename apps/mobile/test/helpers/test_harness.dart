import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moneymind/core/providers/auth_provider.dart';
import 'package:moneymind/core/providers/database_provider.dart';
import 'package:moneymind/core/providers/firestore_provider.dart';
import 'package:moneymind/data/local/app_database.dart';
import 'package:moneymind/data/remote/auth_service.dart';
import 'package:moneymind/features/billing/providers/premium_providers.dart';

/// A fresh in-memory [AppDatabase]. Drift's `onCreate` migration runs lazily
/// on first query, so all tables exist by the time a test touches them.
AppDatabase newTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

/// A [ProviderContainer] wired for controller tests:
/// - in-memory Drift DB (all DAO providers cascade from it),
/// - a fake signed-in user (so `currentUser.uid` resolves),
/// - `isPremium = true` to skip the static `FirebaseRemoteConfig` free-tier
///   reads (those can't run without a live Firebase app),
/// - a no-op Firestore so the best-effort delete-mirror doesn't crash.
///
/// Both the container and the DB are torn down automatically.
({ProviderContainer container, AppDatabase db}) buildTestContainer({
  String uid = 'u1',
  bool premium = true,
}) {
  final db = newTestDatabase();
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      authServiceProvider.overrideWithValue(FakeAuthService(uid: uid)),
      isPremiumProvider.overrideWithValue(premium),
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });
  return (container: container, db: db);
}

/// Inserts a wallet straight through the DAO so a test has something to spend
/// against. Mirrors the column set `WalletsController.create` writes.
Future<void> seedWallet(
  AppDatabase db, {
  required String id,
  required double balance,
  String currency = 'USD',
  String userId = 'u1',
}) {
  final now = DateTime.now().toUtc();
  return db.walletDao.insertOne(
    WalletsCompanion(
      id: Value(id),
      userId: Value(userId),
      name: Value('Wallet $id'),
      type: const Value('cash'),
      currency: Value(currency),
      balance: Value(balance),
      iconName: const Value('payments'),
      color: const Value('8a4f37'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}

/// Inserts a transaction straight through the DAO (bypassing the controller),
/// for tests that derive from existing rows (e.g. budget progress).
Future<void> seedTransaction(
  AppDatabase db, {
  required String id,
  required DateTime date,
  required double amount,
  String type = 'expense',
  String userId = 'u1',
  String walletId = 'w1',
  String categoryId = 'c1',
  String currency = 'USD',
}) {
  final now = DateTime.now().toUtc();
  return db.transactionDao.insertOne(
    TransactionsCompanion(
      id: Value(id),
      userId: Value(userId),
      walletId: Value(walletId),
      categoryId: Value(categoryId),
      type: Value(type),
      amount: Value(amount),
      currency: Value(currency),
      date: Value(date),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );
}

// ---------------------------------------------------------------------------
// Auth fakes. The controller only ever reads `currentUser.uid`, so a minimal
// `noSuchMethod` fake covers the surface. `FirebaseFirestore` is faked with
// the real `FakeFirebaseFirestore` from fake_cloud_firestore because its
// `DocumentReference` is a sealed type (can't be hand-implemented).
// ---------------------------------------------------------------------------

class FakeAuthService implements AuthService {
  FakeAuthService({required String uid}) : currentUser = FakeUser(uid);

  @override
  final User? currentUser;

  /// Emits the fake user once so providers built on `authStateProvider`
  /// (e.g. `goalsListProvider`, the budget list) resolve a signed-in user.
  @override
  Stream<User?> authStateChanges() => Stream<User?>.value(currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeUser implements User {
  FakeUser(this.uid);

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
