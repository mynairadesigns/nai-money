import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../data/local/app_database.dart';

/// Form payload for create / edit. Mutable POJO updated in place by
/// AddDebtScreen; submitted via [DebtsController.create] / `.edit`.
///
/// `contactName` is denormalized (kept on the debt row) because PRD §5.1
/// declares it non-nullable on the Debts table — that lets the UI render
/// without having to join Contacts on every list rebuild.
class DebtFormData {
  DebtFormData({
    this.id,
    this.type = 'lent',
    this.contactName = '',
    this.contactId,
    this.originalAmount = 0,
    this.currency = 'USD',
    this.dueDate,
    this.notes,
  });

  /// Non-null when editing.
  String? id;

  /// 'lent' (I lent money) | 'borrowed' (I borrowed money).
  String type;

  String contactName;
  String? contactId;

  double originalAmount;
  String currency;

  DateTime? dueDate;
  String? notes;

  bool get isReady => contactName.trim().isNotEmpty && originalAmount > 0;
}

final debtsControllerProvider =
    AsyncNotifierProvider<DebtsController, void>(DebtsController.new);

/// AsyncNotifier driving debt create / edit / delete + payment + settle.
/// UI watches the AsyncValue for loading + error.
///
/// Naming: `edit` (not `update`) to avoid colliding with
/// `AsyncNotifier.update`.
class DebtsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(DebtFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a debt while signed out');
      }
      if (!form.isReady) {
        throw ArgumentError('Debt form missing contact or amount');
      }
      final dao = ref.read(debtDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_d_${now.microsecondsSinceEpoch}';

      await dao.insertOne(
        DebtsCompanion(
          id: Value(id),
          userId: Value(user.uid),
          type: Value(form.type),
          contactName: Value(form.contactName.trim()),
          contactId: Value(form.contactId),
          originalAmount: Value(form.originalAmount),
          remainingAmount: Value(form.originalAmount),
          currency: Value(form.currency),
          dueDate: Value(form.dueDate),
          status: const Value('open'),
          notes: Value(_nullIfBlank(form.notes)),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> edit(DebtFormData form) async {
    final id = form.id;
    if (id == null) throw ArgumentError('edit requires a non-null id');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(debtDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Debt $id not found');
      final now = DateTime.now().toUtc();
      await dao.updateOne(
        DebtsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          type: Value(form.type),
          contactName: Value(form.contactName.trim()),
          contactId: Value(form.contactId),
          originalAmount: Value(form.originalAmount),
          // We trust the existing remainingAmount — payment math owns
          // it. Recomputing from Σ debtPayments is out of scope here.
          remainingAmount: Value(existing.remainingAmount),
          currency: Value(form.currency),
          dueDate: Value(form.dueDate),
          status: Value(existing.status),
          notes: Value(_nullIfBlank(form.notes)),
          createdAt: Value(existing.createdAt),
          settledAt: Value(existing.settledAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  /// Removes the debt **and its payments**, then mirrors both deletions
  /// to Firestore.
  ///
  /// The FK in `debt_payments` has no `ON DELETE CASCADE`, so this used
  /// to drop the debt row alone and accept the orphaned payments as a v1
  /// tradeoff. They turned out not to be harmless: `debtPayments` is one
  /// of the 9 synced tables, so orphans still flushed to
  /// `users/{uid}/debtPayments/` and the hydrator pulled them back on
  /// every sign-in — and they survived "Reset all data", which cascaded
  /// via the *surviving* debt rows and so could never reach them.
  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      final db = ref.read(appDatabaseProvider);
      final dao = ref.read(debtDaoProvider);

      // Read the ids before the rows are gone — the Firestore mirror
      // needs them and they're unrecoverable after the transaction.
      final paymentIds =
          (await dao.getPaymentsForDebt(id)).map((p) => p.id).toList();

      await db.transaction(() async {
        // Payments first: the parent must outlive its children so the
        // FK direction stays satisfied if enforcement is ever enabled.
        await dao.deletePaymentsForDebt(id);
        await dao.deleteById(id);
      });

      if (user != null) {
        await _mirrorDelete(user.uid, debtId: id, paymentIds: paymentIds);
      }
    });
  }

  /// Fire-and-forget Firestore mirror for deletes, mirroring
  /// `TransactionsController._mirrorDelete`. The local rows are already
  /// gone so there's no `syncStatus='pending'` flag to ride on; we
  /// dispatch the deletes directly. Failures are swallowed — the
  /// Firestore SDK queues offline writes itself.
  Future<void> _mirrorDelete(
    String uid, {
    required String debtId,
    required List<String> paymentIds,
  }) async {
    final firestore = ref.read(firestoreProvider);
    Future<void> deleteDoc(String path) async {
      try {
        await firestore.doc(path).delete();
      } catch (_) {
        // Swallow: best-effort mirror. See doc comment.
      }
    }

    for (final paymentId in paymentIds) {
      await deleteDoc('users/$uid/debtPayments/$paymentId');
    }
    await deleteDoc('users/$uid/debts/$debtId');
  }

  /// Records a payment against a debt. Runs inside a Drift transaction
  /// so the payment insert + the parent's `remainingAmount` decrement
  /// either both land or neither does. Both rows flip to `pending` so
  /// the sync engine re-mirrors them.
  Future<void> addPayment({
    required String debtId,
    required double amount,
    DateTime? paidAt,
    String? note,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot record a payment while signed out');
      }
      if (amount <= 0) {
        throw ArgumentError('Payment amount must be greater than 0');
      }
      final db = ref.read(appDatabaseProvider);
      final dao = ref.read(debtDaoProvider);
      final now = DateTime.now().toUtc();
      final paymentId = '${user.uid}_dp_${now.microsecondsSinceEpoch}';

      await db.transaction(() async {
        final existing = await dao.getById(debtId);
        if (existing == null) throw StateError('Debt $debtId not found');

        await dao.addPayment(
          DebtPaymentsCompanion(
            id: Value(paymentId),
            userId: Value(user.uid),
            debtId: Value(debtId),
            amount: Value(amount),
            paidAt: Value(paidAt ?? now),
            note: Value(_nullIfBlank(note)),
            updatedAt: Value(now),
          ),
        );

        final newRemaining = (existing.remainingAmount - amount);
        final settled = newRemaining <= 0.005;
        await dao.updateOne(
          DebtsCompanion(
            id: Value(existing.id),
            userId: Value(existing.userId),
            type: Value(existing.type),
            contactName: Value(existing.contactName),
            contactId: Value(existing.contactId),
            originalAmount: Value(existing.originalAmount),
            remainingAmount: Value(settled ? 0 : newRemaining),
            currency: Value(existing.currency),
            dueDate: Value(existing.dueDate),
            status: Value(existing.status),
            notes: Value(existing.notes),
            createdAt: Value(existing.createdAt),
            settledAt: Value(settled ? now : existing.settledAt),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
      });
    });
  }

  /// Force-settle a debt without recording a final payment. Useful when
  /// the remaining amount is forgiven / written off.
  Future<void> markSettled(String debtId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(debtDaoProvider);
      final existing = await dao.getById(debtId);
      if (existing == null) throw StateError('Debt $debtId not found');
      final now = DateTime.now().toUtc();
      await dao.updateOne(
        DebtsCompanion(
          id: Value(existing.id),
          userId: Value(existing.userId),
          type: Value(existing.type),
          contactName: Value(existing.contactName),
          contactId: Value(existing.contactId),
          originalAmount: Value(existing.originalAmount),
          remainingAmount: const Value(0),
          currency: Value(existing.currency),
          dueDate: Value(existing.dueDate),
          status: Value(existing.status),
          notes: Value(existing.notes),
          createdAt: Value(existing.createdAt),
          settledAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
