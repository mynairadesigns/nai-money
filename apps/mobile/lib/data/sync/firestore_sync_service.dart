import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import '../local/app_database.dart';
import 'sync_mappers.dart';

/// Write-through reconciler from Drift → Firestore (PRD §5.3).
///
/// For each synced table, subscribes to the `syncStatus = 'pending'` row
/// stream scoped to the current user. New rows trigger a Firestore set
/// with `merge: true` at `users/{uid}/<collection>/{docId}`; on success
/// the local row is flipped to `'synced'`. On failure the row stays
/// pending — the next emission (any other table change, or app cold
/// start) retries.
///
/// Only the [start]/[stop] API is exposed; callers don't drive a flush
/// directly. Service is a long-lived singleton owned by Riverpod; the
/// auth lifecycle provider calls [startForUser] / [stop].
class FirestoreSyncService {
  FirestoreSyncService(this._firestore, this._db);

  final FirebaseFirestore _firestore;
  final AppDatabase _db;

  String? _currentUid;
  final List<StreamSubscription<void>> _subs = [];

  bool get isRunning => _currentUid != null;

  /// Starts mirroring for [uid]. Idempotent — calling with the same uid
  /// is a no-op; calling with a different uid stops the existing session
  /// first.
  void startForUser(String uid) {
    if (_currentUid == uid) return;
    stop();
    _currentUid = uid;

    _subs.add(
      _db.walletDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushWallets(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.categoryDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushCategories(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.transactionDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushTransactions(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.budgetDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushBudgets(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.recurringRuleDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushRecurringRules(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.debtDao
          .watchPendingDebtsForUser(uid)
          .asyncMap((rows) => _flushDebts(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.debtDao
          .watchPendingPaymentsForUser(uid)
          .asyncMap((rows) => _flushDebtPayments(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.goalDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushGoals(uid, rows))
          .listen((_) {}),
    );
    _subs.add(
      _db.contactDao
          .watchPendingForUser(uid)
          .asyncMap((rows) => _flushContacts(uid, rows))
          .listen((_) {}),
    );
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _currentUid = null;
  }

  Future<void> _flushWallets(String uid, List<Wallet> pending) async {
    for (final w in pending) {
      if (w.userId != uid) continue; // defensive: cross-account guard
      try {
        await _firestore
            .doc('users/$uid/wallets/${w.id}')
            .set(walletToFirestore(w), SetOptions(merge: true));
        await _db.walletDao.markSynced(w.id);
      } catch (_) {
        // Network / permission error — leave pending. The Firestore SDK
        // also queues writes offline, so most transient failures resolve
        // themselves; otherwise the next table-change emission retries.
      }
    }
  }

  Future<void> _flushCategories(String uid, List<Category> pending) async {
    for (final c in pending) {
      if (c.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/categories/${c.id}')
            .set(categoryToFirestore(c), SetOptions(merge: true));
        await _db.categoryDao.markSynced(c.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushTransactions(String uid, List<Transaction> pending) async {
    for (final t in pending) {
      if (t.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/transactions/${t.id}')
            .set(transactionToFirestore(t), SetOptions(merge: true));
        await _db.transactionDao.markSynced(t.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushBudgets(String uid, List<Budget> pending) async {
    for (final b in pending) {
      if (b.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/budgets/${b.id}')
            .set(budgetToFirestore(b), SetOptions(merge: true));
        await _db.budgetDao.markSynced(b.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushRecurringRules(
    String uid,
    List<RecurringRule> pending,
  ) async {
    for (final r in pending) {
      if (r.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/recurringRules/${r.id}')
            .set(recurringRuleToFirestore(r), SetOptions(merge: true));
        await _db.recurringRuleDao.markSynced(r.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushDebts(String uid, List<Debt> pending) async {
    for (final d in pending) {
      if (d.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/debts/${d.id}')
            .set(debtToFirestore(d), SetOptions(merge: true));
        await _db.debtDao.markDebtSynced(d.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushDebtPayments(
    String uid,
    List<DebtPayment> pending,
  ) async {
    for (final p in pending) {
      if (p.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/debtPayments/${p.id}')
            .set(debtPaymentToFirestore(p), SetOptions(merge: true));
        await _db.debtDao.markPaymentSynced(p.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushGoals(String uid, List<Goal> pending) async {
    for (final g in pending) {
      if (g.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/goals/${g.id}')
            .set(goalToFirestore(g), SetOptions(merge: true));
        await _db.goalDao.markSynced(g.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }

  Future<void> _flushContacts(String uid, List<Contact> pending) async {
    for (final c in pending) {
      if (c.userId != uid) continue;
      try {
        await _firestore
            .doc('users/$uid/contacts/${c.id}')
            .set(contactToFirestore(c), SetOptions(merge: true));
        await _db.contactDao.markSynced(c.id);
      } catch (_) {
        // see _flushWallets
      }
    }
  }
}
