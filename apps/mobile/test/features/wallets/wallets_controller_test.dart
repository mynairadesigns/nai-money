import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homa_finance/data/local/app_database.dart';
import 'package:homa_finance/features/wallets/providers/wallets_controller.dart';
import 'package:homa_finance/features/wallets/providers/wallets_list_provider.dart';

import '../../helpers/test_harness.dart';

/// WalletsController create / edit / archive / hide. Balance is owned by the
/// transaction flow — `edit` must NOT touch it — and every mutation must
/// re-flag the row for sync (CLAUDE.md §8 write-through convention).
void main() {
  group('create', () {
    test('inserts a wallet stamped with the uid, opening balance, pending sync',
        () async {
      final h = buildTestContainer();
      final ctrl = h.container.read(walletsControllerProvider.notifier);

      await ctrl.create(WalletFormData(
        name: 'Cash',
        currency: 'USD',
        openingBalance: 100,
      ));

      final wallets = await h.db.walletDao.watchAll().first;
      expect(wallets.length, 1);
      final w = wallets.single;
      expect(w.name, 'Cash');
      expect(w.currency, 'USD');
      expect(w.balance, 100);
      expect(w.userId, 'u1');
      expect(w.syncStatus, 'pending');
    });

    test('premium users are not blocked from a second wallet', () async {
      // isPremium defaults to true in the harness → free-tier ceiling skipped.
      final h = buildTestContainer();
      final ctrl = h.container.read(walletsControllerProvider.notifier);

      await ctrl.create(WalletFormData(name: 'A', currency: 'USD'));
      await ctrl.create(WalletFormData(name: 'B', currency: 'EUR'));

      final wallets = await h.db.walletDao.watchAll().first;
      expect(wallets.length, 2);
    });
  });

  group('edit', () {
    test('updates metadata, preserves balance, re-flags for sync', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 250);
      // Pretend the row was already mirrored.
      await h.db.walletDao.markSynced('w1');
      final ctrl = h.container.read(walletsControllerProvider.notifier);

      await ctrl.edit(WalletFormData(
        id: 'w1',
        name: 'Renamed',
        type: 'bank',
        currency: 'EUR',
        openingBalance: 999, // edit must IGNORE this
        iconName: 'savings',
        colorHex: 'aabbcc',
      ));

      final w = await h.db.walletDao.getById('w1');
      expect(w!.name, 'Renamed');
      expect(w.type, 'bank');
      expect(w.currency, 'EUR');
      expect(w.iconName, 'savings');
      expect(w.color, 'aabbcc');
      expect(w.balance, 250); // unchanged by edit
      expect(w.syncStatus, 'pending'); // re-flagged
    });
  });

  group('archive / hide', () {
    test('archive sets isArchived and re-flags for sync', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 0);
      await h.db.walletDao.markSynced('w1');
      final ctrl = h.container.read(walletsControllerProvider.notifier);

      await ctrl.archive('w1');

      final w = await h.db.walletDao.getById('w1');
      expect(w!.isArchived, isTrue);
      expect(w.syncStatus, 'pending');
    });

    test('archive:false restores the wallet and re-flags for sync', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 0);
      final ctrl = h.container.read(walletsControllerProvider.notifier);
      await ctrl.archive('w1');
      await h.db.walletDao.markSynced('w1');

      await ctrl.archive('w1', archive: false);

      final w = await h.db.walletDao.getById('w1');
      expect(w!.isArchived, isFalse);
      expect(w.syncStatus, 'pending');
    });

    test('archived wallets leave visibleWallets but stay in archived',
        () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 0);
      await seedWallet(h.db, id: 'w2', balance: 0);

      // `walletsListProvider` wraps an infinite Drift `watch()`, so a
      // `.future` read would leave a pending completer that errors at
      // container dispose (CLAUDE.md §6). Keep a live subscription and
      // poll the emitted value instead.
      final sub = h.container.listen<AsyncValue<List<Wallet>>>(
        walletsListProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      await _waitForWallets(h.container, (rows) => rows.length == 2);
      await h.container
          .read(walletsControllerProvider.notifier)
          .archive('w1');
      await _waitForWallets(
        h.container,
        (rows) => rows.any((w) => w.isArchived),
      );

      final visible = h.container.read(visibleWalletsProvider).value ?? [];
      final archived = h.container.read(archivedWalletsProvider).value ?? [];

      expect(visible.map((w) => w.id), ['w2']);
      expect(archived.map((w) => w.id), ['w1']);
    });

    test('setHidden toggles isHidden and re-flags for sync', () async {
      final h = buildTestContainer();
      await seedWallet(h.db, id: 'w1', balance: 0);
      await h.db.walletDao.markSynced('w1');
      final ctrl = h.container.read(walletsControllerProvider.notifier);

      await ctrl.setHidden('w1', true);

      final w = await h.db.walletDao.getById('w1');
      expect(w!.isHidden, isTrue);
      expect(w.syncStatus, 'pending');
    });
  });
}

/// Polls the (already-subscribed) wallet stream until [predicate] holds.
/// Drift emits asynchronously after a write, so the assertion has to wait
/// for the next emission rather than reading straight after the await.
Future<void> _waitForWallets(
  ProviderContainer container,
  bool Function(List<Wallet>) predicate,
) async {
  for (var i = 0; i < 100; i++) {
    final rows = container.read(walletsListProvider).value;
    if (rows != null && predicate(rows)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('wallet stream never satisfied the predicate');
}
