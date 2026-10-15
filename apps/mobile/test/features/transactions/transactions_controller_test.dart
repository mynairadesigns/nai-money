import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneymind/data/local/app_database.dart';
import 'package:moneymind/features/transactions/data/transaction_form_state.dart';
import 'package:moneymind/features/transactions/providers/transactions_controller.dart';

import '../../helpers/test_harness.dart';

/// CLAUDE.md §8: every Transactions mutation must keep the parent wallet
/// balance consistent inside one atomic block. These tests pin that invariant
/// across create / edit (same + cross wallet) / delete / transfer.
void main() {
  Future<String> firstTxId(AppDatabase db) async =>
      (await db.transactionDao.watchAll().first).single.id;

  group('create', () {
    test('expense decreases the wallet balance and writes a pending row',
        () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100);
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.create(TransactionFormData(
        type: 'expense',
        amount: 30,
        walletId: 'w1',
        categoryId: 'c1',
      ));

      expect(h.container.read(transactionsControllerProvider).hasError, isFalse);
      final wallet = await h.db.walletDao.getById('w1');
      expect(wallet!.balance, 70);

      final txs = await h.db.transactionDao.watchAll().first;
      expect(txs.length, 1);
      expect(txs.single.amount, 30);
      expect(txs.single.currency, 'USD'); // inherited from the wallet
      expect(txs.single.syncStatus, 'pending');
    });

    test('income increases the wallet balance', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100);
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.create(TransactionFormData(
        type: 'income',
        amount: 40,
        walletId: 'w1',
        categoryId: 'c1',
      ));

      final wallet = await h.db.walletDao.getById('w1');
      expect(wallet!.balance, 140);
    });
  });

  group('edit', () {
    test('same-wallet amount change applies the net delta', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100);
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.create(TransactionFormData(
        type: 'expense', amount: 30, walletId: 'w1', categoryId: 'c1',
      ));
      // balance == 70
      final id = await firstTxId(h.db);

      await ctrl.edit(TransactionFormData(
        id: id, type: 'expense', amount: 50, walletId: 'w1', categoryId: 'c1',
      ));

      // Reverse old -30, apply new -50 → 100 - 50 = 50.
      final wallet = await h.db.walletDao.getById('w1');
      expect(wallet!.balance, 50);
    });

    test('moving to another wallet refunds the old and charges the new',
        () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100);
      await seedWallet(h.db, id: 'w2', balance: 200);
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.create(TransactionFormData(
        type: 'expense', amount: 30, walletId: 'w1', categoryId: 'c1',
      ));
      // w1 == 70
      final id = await firstTxId(h.db);

      await ctrl.edit(TransactionFormData(
        id: id, type: 'expense', amount: 30, walletId: 'w2', categoryId: 'c1',
      ));

      final w1 = await h.db.walletDao.getById('w1');
      final w2 = await h.db.walletDao.getById('w2');
      expect(w1!.balance, 100); // refunded
      expect(w2!.balance, 170); // charged
    });
  });

  group('delete', () {
    test('reverses the wallet impact and removes the row', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100);
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.create(TransactionFormData(
        type: 'expense', amount: 30, walletId: 'w1', categoryId: 'c1',
      ));
      final id = await firstTxId(h.db);

      await ctrl.delete(id);

      expect(h.container.read(transactionsControllerProvider).hasError, isFalse);
      final wallet = await h.db.walletDao.getById('w1');
      expect(wallet!.balance, 100);
      expect(await h.db.transactionDao.watchAll().first, isEmpty);
    });
  });

  group('transfer', () {
    test('same-currency debits source and credits destination', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100, currency: 'USD');
      await seedWallet(h.db, id: 'w2', balance: 50, currency: 'USD');
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.createTransfer(
        sourceWalletId: 'w1',
        destWalletId: 'w2',
        sourceAmount: 40,
        fxRate: 1,
        date: DateTime(2026, 5, 25),
      );

      final w1 = await h.db.walletDao.getById('w1');
      final w2 = await h.db.walletDao.getById('w2');
      expect(w1!.balance, 60);
      expect(w2!.balance, 90);

      final tx = (await h.db.transactionDao.watchAll().first).single;
      expect(tx.type, 'transfer');
      expect(tx.transferToWalletId, 'w2');
    });

    test('cross-currency credits dest with amount * fxRate and records origin',
        () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100, currency: 'USD');
      await seedWallet(h.db, id: 'w2', balance: 0, currency: 'EUR');
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.createTransfer(
        sourceWalletId: 'w1',
        destWalletId: 'w2',
        sourceAmount: 40,
        fxRate: 0.9,
        date: DateTime(2026, 5, 25),
      );

      final w1 = await h.db.walletDao.getById('w1');
      final w2 = await h.db.walletDao.getById('w2');
      expect(w1!.balance, 60); // -40 source currency
      expect(w2!.balance, closeTo(36, 1e-9)); // +40 * 0.9 dest currency

      final tx = (await h.db.transactionDao.watchAll().first).single;
      expect(tx.amount, closeTo(36, 1e-9));
      expect(tx.currency, 'EUR');
      expect(tx.originalAmount, 40);
      expect(tx.originalCurrency, 'USD');
      expect(tx.fxRate, 0.9);
    });

    test('deleting a cross-currency transfer restores both wallets', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 100, currency: 'USD');
      await seedWallet(h.db, id: 'w2', balance: 0, currency: 'EUR');
      final ctrl = h.container.read(transactionsControllerProvider.notifier);

      await ctrl.createTransfer(
        sourceWalletId: 'w1',
        destWalletId: 'w2',
        sourceAmount: 40,
        fxRate: 0.9,
        date: DateTime(2026, 5, 25),
      );
      final id = await firstTxId(h.db);

      await ctrl.delete(id);

      final w1 = await h.db.walletDao.getById('w1');
      final w2 = await h.db.walletDao.getById('w2');
      expect(w1!.balance, 100); // refunded originalAmount
      expect(w2!.balance, closeTo(0, 1e-9)); // took back dest amount
    });
  });
}
