import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../local/app_database.dart';
import 'sync_mappers.dart';

/// One-shot Firestore → Drift pull, run at sign-in by [syncLifecycleProvider]
/// before the write-through engine starts. Closes the two pain points the
/// write-through alone can't:
///
///  1. **Recurring scheduler.** `processRecurringRules` writes new Transaction
///     docs directly to Firestore — without this pull, the client never sees
///     them until they re-install. After hydrate, the next cold start picks
///     them up.
///  2. **Re-install / multi-device.** A fresh Drift database has nothing in
///     it; without this pull, the user would see "empty" until they re-create
///     every row by hand. Hydrate restores everything from Firestore.
///
/// Conflict resolution (PRD §5.3, last-write-wins by `updatedAt`):
///  - If the local row doesn't exist → upsert.
///  - If the local row exists with `syncStatus == 'pending'` → SKIP. The
///    write-through engine is about to push this; let it win.
///  - Otherwise → upsert if remote.updatedAt > local.updatedAt (i.e. the
///    Firestore copy is newer); else skip.
///
/// Failures are non-fatal — a network blip leaves Drift unchanged and the
/// next sign-in retries. The whole hydrate is best-effort; never blocks
/// the auth flow.
class FirestoreHydrator {
  FirestoreHydrator(this._firestore, this._db);

  final FirebaseFirestore _firestore;
  final AppDatabase _db;

  /// Pull every synced subcollection under `users/{uid}/` into Drift.
  /// Returns silently on any error.
  Future<void> hydrate(String uid) async {
    try {
      await Future.wait([
        _pull(
          uid: uid,
          collection: 'wallets',
          existingUpdatedAtById: () async {
            final rows = await _db.walletDao.watchAll().first;
            return {
              for (final w in rows.where((w) => w.userId == uid))
                w.id: (w.updatedAt, w.syncStatus),
            };
          },
          upsert: (data) =>
              _db.walletDao.upsertOne(walletFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'categories',
          existingUpdatedAtById: () async {
            final rows = await _db.categoryDao.watchAll().first;
            return {
              for (final c in rows.where((c) => c.userId == uid))
                c.id: (c.updatedAt, c.syncStatus),
            };
          },
          upsert: (data) =>
              _db.categoryDao.upsertOne(categoryFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'transactions',
          existingUpdatedAtById: () async {
            final rows = await _db.transactionDao.watchAll().first;
            return {
              for (final t in rows.where((t) => t.userId == uid))
                t.id: (t.updatedAt, t.syncStatus),
            };
          },
          upsert: (data) => _db.transactionDao
              .upsertOne(transactionFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'budgets',
          existingUpdatedAtById: () async {
            final rows = await _db.budgetDao.watchAll().first;
            return {
              for (final b in rows.where((b) => b.userId == uid))
                b.id: (b.updatedAt, b.syncStatus),
            };
          },
          upsert: (data) =>
              _db.budgetDao.upsertOne(budgetFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'recurringRules',
          existingUpdatedAtById: () async {
            final rows = await _db.recurringRuleDao.watchAll().first;
            return {
              for (final r in rows.where((r) => r.userId == uid))
                r.id: (r.updatedAt, r.syncStatus),
            };
          },
          upsert: (data) => _db.recurringRuleDao
              .upsertOne(recurringRuleFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'debts',
          existingUpdatedAtById: () async {
            final rows = await _db.debtDao.watchAll().first;
            return {
              for (final d in rows.where((d) => d.userId == uid))
                d.id: (d.updatedAt, d.syncStatus),
            };
          },
          upsert: (data) =>
              _db.debtDao.upsertDebt(debtFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'debtPayments',
          existingUpdatedAtById: () async {
            // No top-level watch on payments; iterate via parent-debt scope.
            // For hydration this returns an empty map (treat all as new);
            // the write-through engine on the next local edit will reconcile.
            return const <String, (DateTime, String)>{};
          },
          upsert: (data) =>
              _db.debtDao.upsertPayment(debtPaymentFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'goals',
          existingUpdatedAtById: () async {
            final rows = await _db.goalDao.watchAll().first;
            return {
              for (final g in rows.where((g) => g.userId == uid))
                g.id: (g.updatedAt, g.syncStatus),
            };
          },
          upsert: (data) =>
              _db.goalDao.upsertOne(goalFromFirestore(data, uid)),
        ),
        _pull(
          uid: uid,
          collection: 'contacts',
          existingUpdatedAtById: () async {
            final rows = await _db.contactDao.watchAll().first;
            return {
              for (final c in rows.where((c) => c.userId == uid))
                c.id: (c.updatedAt, c.syncStatus),
            };
          },
          upsert: (data) =>
              _db.contactDao.upsertOne(contactFromFirestore(data, uid)),
        ),
      ]);
    } catch (_) {
      // Best-effort: any failure leaves Drift unchanged. Retried on next
      // sign-in via syncLifecycleProvider.
    }
  }

  /// Fetches every doc under `users/{uid}/<collection>/` and upserts into
  /// Drift, respecting the LWW + pending-skip rules in the class doc.
  Future<void> _pull({
    required String uid,
    required String collection,
    required Future<Map<String, (DateTime, String)>> Function()
        existingUpdatedAtById,
    required Future<void> Function(Map<String, dynamic>) upsert,
  }) async {
    try {
      final snapshot =
          await _firestore.collection('users/$uid/$collection').get();
      if (snapshot.docs.isEmpty) return;
      final existing = await existingUpdatedAtById();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final id = data['id'] as String? ?? doc.id;
        final remoteUpdatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
        final localEntry = existing[id];

        if (localEntry != null) {
          final (localUpdatedAt, localStatus) = localEntry;
          if (localStatus == 'pending') continue; // engine wins
          if (remoteUpdatedAt != null &&
              !remoteUpdatedAt.isAfter(localUpdatedAt)) {
            continue; // local is same-or-newer
          }
        }

        // Defensive — ensure id is stamped on the data map for the mapper.
        await upsert({...data, 'id': id});
      }
    } catch (_) {
      // see hydrate() — best-effort.
    }
  }
}
