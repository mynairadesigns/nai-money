import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/daos/wallet_dao.dart';
import '../../../data/remote/storage_service.dart';
import '../../ads/providers/ads_providers.dart';
import '../../billing/data/free_tier_exception.dart';
import '../../billing/providers/premium_providers.dart';
import '../../billing/widgets/upsell_sheet.dart';
import '../data/transaction_form_state.dart';

final transactionsControllerProvider =
    AsyncNotifierProvider<TransactionsController, void>(
  TransactionsController.new,
);

/// AsyncNotifier driving transaction create / edit / delete. Each
/// mutation runs inside a single Drift transaction so the parent wallet
/// balance stays consistent with the row set (per CLAUDE.md §8).
///
/// Naming: `edit` (not `update`) to avoid colliding with
/// `AsyncNotifier.update`.
class TransactionsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(TransactionFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a transaction while signed out');
      }
      _assertReady(form);
      final db = ref.read(appDatabaseProvider);
      final txDao = ref.read(transactionDaoProvider);
      final walletDao = ref.read(walletDaoProvider);
      // Free-tier ceiling check (PRD §6.14.1, RC `free_tier_transactions_monthly`).
      if (!ref.read(isPremiumProvider)) {
        final limit = FirebaseRemoteConfig.instance
            .getInt('free_tier_transactions_monthly');
        final ceiling = limit > 0 ? limit : 100;
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month);
        final monthEnd = DateTime(now.year, now.month + 1);
        final count = await txDao.countForMonth(
          userId: user.uid,
          start: monthStart,
          end: monthEnd,
        );
        if (count >= ceiling) {
          throw const FreeTierExceeded(UpsellReason.transactions);
        }
      }
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_t_${now.microsecondsSinceEpoch}';

      await db.transaction(() async {
        final wallet = await walletDao.getById(form.walletId!);
        if (wallet == null) {
          throw StateError('Wallet ${form.walletId} not found');
        }

        await txDao.insertOne(
          TransactionsCompanion(
            id: Value(id),
            userId: Value(user.uid),
            walletId: Value(form.walletId!),
            categoryId: Value(form.categoryId ?? ''),
            type: Value(form.type),
            amount: Value(form.amount),
            currency: Value(wallet.currency),
            date: Value(form.date),
            note: Value(form.note),
            attachmentUrl: Value(form.attachmentUrl),
            attachmentLocalPath: Value(form.attachmentLocalPath),
            aiCategorySuggested: Value(form.aiCategorySuggested),
            aiConfidence: Value(form.aiConfidence),
            aiSource: Value(form.aiSource),
            createdAt: Value(now),
            updatedAt: Value(now),
            // syncStatus defaults to 'pending' — sync engine mirrors it.
          ),
        );

        await _bumpWalletBalance(
          walletDao: walletDao,
          wallet: wallet,
          delta: _signedDelta(form.type, form.amount),
          now: now,
        );
      });
      // Notify the interstitial controller — gated by ads_enabled (premium
      // users + RC off both short-circuit the bump-to-ad pipeline).
      ref.read(transactionAddCountProvider.notifier).increment();

      // Promote a scanned receipt from its temp upload to the permanent
      // per-transaction Storage path (P4.2.1). Off the critical path:
      // fire-and-forget so the save returns immediately, best-effort so a
      // flaky network never blocks or fails the (already-committed) save.
      unawaited(
        _promoteReceiptIfNeeded(
          uid: user.uid,
          txId: id,
          tempPath: form.attachmentLocalPath,
        ),
      );
    });
  }

  /// After a scanned receipt is saved, copy its temp Storage object to the
  /// permanent path `users/{uid}/receipts/{txId}.jpg`, repoint the row's
  /// `attachmentUrl`, clear the temp `attachmentLocalPath`, and re-flag for
  /// sync. Best-effort and self-contained: any failure (e.g. offline) leaves
  /// the temp path in place as the fallback. Never throws.
  ///
  /// Only acts on temp receipt paths (`users/{uid}/receipts/temp/...`); a
  /// manually-attached URL or a plain local cache path is left untouched.
  Future<void> _promoteReceiptIfNeeded({
    required String uid,
    required String txId,
    required String? tempPath,
  }) async {
    if (tempPath == null || !tempPath.contains('/receipts/temp/')) return;
    try {
      final storage = ref.read(storageServiceProvider);
      final permanentUrl = await storage.moveReceiptToPermanent(
        uid: uid,
        txId: txId,
        tempStoragePath: tempPath,
      );
      await ref.read(transactionDaoProvider).setReceiptAttachment(
            id: txId,
            attachmentUrl: permanentUrl,
            updatedAt: DateTime.now().toUtc(),
          );
    } catch (_) {
      // Best-effort — leave the temp path as the fallback attachment ref.
    }
  }

  Future<void> edit(TransactionFormData form) async {
    final id = form.id;
    if (id == null) {
      throw ArgumentError('edit requires a non-null id');
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _assertReady(form);
      final db = ref.read(appDatabaseProvider);
      final txDao = ref.read(transactionDaoProvider);
      final walletDao = ref.read(walletDaoProvider);
      final now = DateTime.now().toUtc();

      await db.transaction(() async {
        final existing = await txDao.getById(id);
        if (existing == null) {
          throw StateError('Transaction $id not found');
        }
        // Reverse the old row's effect on the old wallet, apply the new
        // row's effect to the new wallet. Same-wallet edits are folded
        // into a single net delta.
        final oldDelta = _signedDelta(existing.type, existing.amount);
        final newDelta = _signedDelta(form.type, form.amount);

        if (existing.walletId == form.walletId) {
          final wallet = await walletDao.getById(form.walletId!);
          if (wallet != null) {
            await _bumpWalletBalance(
              walletDao: walletDao,
              wallet: wallet,
              delta: newDelta - oldDelta,
              now: now,
            );
          }
        } else {
          final oldWallet = await walletDao.getById(existing.walletId);
          final newWallet = await walletDao.getById(form.walletId!);
          if (oldWallet != null) {
            await _bumpWalletBalance(
              walletDao: walletDao,
              wallet: oldWallet,
              delta: -oldDelta,
              now: now,
            );
          }
          if (newWallet != null) {
            await _bumpWalletBalance(
              walletDao: walletDao,
              wallet: newWallet,
              delta: newDelta,
              now: now,
            );
          }
        }

        final newWallet = await walletDao.getById(form.walletId!);
        await txDao.updateOne(
          TransactionsCompanion(
            id: Value(id),
            userId: Value(existing.userId),
            walletId: Value(form.walletId!),
            categoryId: Value(form.categoryId ?? ''),
            type: Value(form.type),
            amount: Value(form.amount),
            currency: Value(newWallet?.currency ?? existing.currency),
            date: Value(form.date),
            note: Value(form.note),
            attachmentUrl: Value(form.attachmentUrl ?? existing.attachmentUrl),
            attachmentLocalPath: Value(
              form.attachmentLocalPath ?? existing.attachmentLocalPath,
            ),
            aiCategorySuggested: Value(
              form.aiCategorySuggested || existing.aiCategorySuggested,
            ),
            aiConfidence: Value(form.aiConfidence ?? existing.aiConfidence),
            aiSource: Value(form.aiSource ?? existing.aiSource),
            createdAt: Value(existing.createdAt),
            updatedAt: Value(now),
            syncStatus: const Value('pending'),
          ),
        );
      });
    });
  }

  /// Records a transfer between two wallets per PRD §5.1. A transfer is a
  /// SINGLE Transaction row (not double-entry) — [Transaction.walletId] is
  /// the source, [Transaction.transferToWalletId] is the destination.
  ///
  /// For same-currency transfers, pass [fxRate] = 1 and the source +
  /// destination amounts are identical.
  /// For cross-currency transfers, [fxRate] is the source→destination rate
  /// fetched by `FxService` (or entered manually as a fallback); the
  /// destination amount is [sourceAmount] × [fxRate] and stored as
  /// [Transaction.amount] in the destination wallet's currency.
  /// [Transaction.originalAmount] / [Transaction.originalCurrency] capture
  /// the source-side values for future audits.
  ///
  /// Inside a single `appDatabase.transaction` block (per CLAUDE.md §8):
  /// 1. Insert the Transaction row
  /// 2. Debit the source wallet by `sourceAmount` (in its own currency)
  /// 3. Credit the destination wallet by `destAmount` (in its own currency)
  /// 4. Both wallets' `syncStatus` resets to `'pending'`
  Future<void> createTransfer({
    required String sourceWalletId,
    required String destWalletId,
    required double sourceAmount,
    required double fxRate, // 1.0 if same-currency
    required DateTime date,
    String? note,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a transfer while signed out');
      }
      if (sourceAmount <= 0) {
        throw ArgumentError('sourceAmount must be > 0');
      }
      if (fxRate <= 0) {
        throw ArgumentError('fxRate must be > 0');
      }
      if (sourceWalletId == destWalletId) {
        throw ArgumentError('sourceWalletId and destWalletId must differ');
      }

      final db = ref.read(appDatabaseProvider);
      final txDao = ref.read(transactionDaoProvider);
      final walletDao = ref.read(walletDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_t_${now.microsecondsSinceEpoch}';

      await db.transaction(() async {
        final sourceWallet = await walletDao.getById(sourceWalletId);
        if (sourceWallet == null) {
          throw StateError('Source wallet $sourceWalletId not found');
        }
        final destWallet = await walletDao.getById(destWalletId);
        if (destWallet == null) {
          throw StateError('Destination wallet $destWalletId not found');
        }

        final destAmount = sourceAmount * fxRate;

        await txDao.insertOne(
          TransactionsCompanion(
            id: Value(id),
            userId: Value(user.uid),
            walletId: Value(sourceWalletId),
            transferToWalletId: Value(destWalletId),
            categoryId: const Value(''),
            type: const Value('transfer'),
            amount: Value(destAmount),
            currency: Value(destWallet.currency),
            originalAmount: Value(sourceAmount),
            originalCurrency: Value(sourceWallet.currency),
            fxRate: Value(fxRate),
            date: Value(date),
            note: Value(note),
            createdAt: Value(now),
            updatedAt: Value(now),
            // syncStatus defaults to 'pending' — sync engine mirrors it.
          ),
        );

        await _bumpWalletBalance(
          walletDao: walletDao,
          wallet: sourceWallet,
          delta: -sourceAmount,
          now: now,
        );
        await _bumpWalletBalance(
          walletDao: walletDao,
          wallet: destWallet,
          delta: destAmount,
          now: now,
        );
      });
    });
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      final db = ref.read(appDatabaseProvider);
      final txDao = ref.read(transactionDaoProvider);
      final walletDao = ref.read(walletDaoProvider);
      final now = DateTime.now().toUtc();

      await db.transaction(() async {
        final existing = await txDao.getById(id);
        if (existing == null) return;
        await _reverseTransaction(existing, walletDao, now);
        await txDao.deleteById(id);
      });
      if (user != null) {
        await _mirrorDelete(user.uid, [id]);
      }
    });
  }

  /// Bulk delete. Atomically reverses each row's wallet impact + removes
  /// all rows in one DAO call, then mirrors the deletes to Firestore.
  Future<void> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      final db = ref.read(appDatabaseProvider);
      final txDao = ref.read(transactionDaoProvider);
      final walletDao = ref.read(walletDaoProvider);
      final now = DateTime.now().toUtc();

      await db.transaction(() async {
        final rows = await txDao.getByIds(ids);
        for (final t in rows) {
          await _reverseTransaction(t, walletDao, now);
        }
        await txDao.deleteByIds(ids);
      });
      if (user != null) {
        await _mirrorDelete(user.uid, ids);
      }
    });
  }

  /// Bulk recategorize. Loads each row, replaces categoryId, bumps
  /// `updatedAt` + flips `syncStatus` to `'pending'` so the sync engine
  /// re-mirrors. No wallet impact (amount/type unchanged).
  Future<void> recategorizeMany(List<String> ids, String newCategoryId) async {
    if (ids.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final db = ref.read(appDatabaseProvider);
      final txDao = ref.read(transactionDaoProvider);
      final now = DateTime.now().toUtc();
      await db.transaction(() async {
        final rows = await txDao.getByIds(ids);
        for (final t in rows) {
          await txDao.updateOne(
            TransactionsCompanion(
              id: Value(t.id),
              userId: Value(t.userId),
              walletId: Value(t.walletId),
              categoryId: Value(newCategoryId),
              type: Value(t.type),
              amount: Value(t.amount),
              currency: Value(t.currency),
              originalAmount: Value(t.originalAmount),
              originalCurrency: Value(t.originalCurrency),
              fxRate: Value(t.fxRate),
              date: Value(t.date),
              note: Value(t.note),
              contactId: Value(t.contactId),
              attachmentUrl: Value(t.attachmentUrl),
              attachmentLocalPath: Value(t.attachmentLocalPath),
              tags: Value(t.tags),
              transferToWalletId: Value(t.transferToWalletId),
              isRecurring: Value(t.isRecurring),
              recurringRuleId: Value(t.recurringRuleId),
              aiCategorySuggested: Value(t.aiCategorySuggested),
              aiConfidence: Value(t.aiConfidence),
              aiSource: Value(t.aiSource),
              createdAt: Value(t.createdAt),
              updatedAt: Value(now),
              syncStatus: const Value('pending'),
            ),
          );
        }
      });
    });
  }

  // ---- internals -------------------------------------------------------

  void _assertReady(TransactionFormData form) {
    if (!form.isReady) {
      throw ArgumentError('Form is missing required fields');
    }
  }

  /// Income adds, expense subtracts. Transfer source is subtractive; the
  /// destination side (a second row + balance bump) lands in P2.4.
  double _signedDelta(String type, double amount) {
    switch (type) {
      case 'income':
        return amount;
      case 'expense':
        return -amount;
      case 'transfer':
        return -amount; // source side only in P2.3
      default:
        return 0;
    }
  }

  /// Reverses a row's wallet impact. Used by both single and bulk
  /// delete. Handles transfers correctly: refunds the source wallet
  /// (`+originalAmount`) AND takes back from the dest wallet
  /// (`-amount`); for expense/income the existing `_signedDelta` rule
  /// applies on the source wallet only.
  Future<void> _reverseTransaction(
    Transaction tx,
    WalletDao walletDao,
    DateTime now,
  ) async {
    if (tx.type == 'transfer' && tx.transferToWalletId != null) {
      final source = await walletDao.getById(tx.walletId);
      if (source != null) {
        final sourceAmount = tx.originalAmount ?? tx.amount;
        await _bumpWalletBalance(
          walletDao: walletDao,
          wallet: source,
          delta: sourceAmount,
          now: now,
        );
      }
      final dest = await walletDao.getById(tx.transferToWalletId!);
      if (dest != null) {
        await _bumpWalletBalance(
          walletDao: walletDao,
          wallet: dest,
          delta: -tx.amount,
          now: now,
        );
      }
    } else {
      final wallet = await walletDao.getById(tx.walletId);
      if (wallet != null) {
        await _bumpWalletBalance(
          walletDao: walletDao,
          wallet: wallet,
          delta: -_signedDelta(tx.type, tx.amount),
          now: now,
        );
      }
    }
  }

  /// Fire-and-forget Firestore mirror for deletes. The local Drift row
  /// is already gone, so a pending-status flag isn't an option; we
  /// dispatch the Firestore delete directly. Failures are swallowed —
  /// the Firestore SDK queues offline writes itself, and a leftover
  /// orphan is recoverable by re-deleting next session. A more robust
  /// `pending_deletes` table can land later if real-world data loss
  /// becomes a concern.
  Future<void> _mirrorDelete(String uid, List<String> ids) async {
    final firestore = ref.read(firestoreProvider);
    for (final id in ids) {
      try {
        await firestore.doc('users/$uid/transactions/$id').delete();
      } catch (_) {
        // Swallow: best-effort mirror. See doc comment.
      }
    }
  }

  Future<void> _bumpWalletBalance({
    required WalletDao walletDao,
    required Wallet wallet,
    required double delta,
    required DateTime now,
  }) async {
    if (delta == 0) return;
    await walletDao.updateOne(
      WalletsCompanion(
        id: Value(wallet.id),
        userId: Value(wallet.userId),
        name: Value(wallet.name),
        type: Value(wallet.type),
        currency: Value(wallet.currency),
        balance: Value(wallet.balance + delta),
        iconName: Value(wallet.iconName),
        color: Value(wallet.color),
        isHidden: Value(wallet.isHidden),
        isArchived: Value(wallet.isArchived),
        sortOrder: Value(wallet.sortOrder),
        createdAt: Value(wallet.createdAt),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
  }
}
