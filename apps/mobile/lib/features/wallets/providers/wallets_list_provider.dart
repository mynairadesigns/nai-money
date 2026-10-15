import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All wallets owned by the currently-signed-in user, streamed live from
/// Drift. Archived + hidden wallets are included — the carousel filters
/// them out at the widget layer.
///
/// Per CLAUDE.md §6 (Local DB is source of truth), reads go through Drift,
/// not Firestore. The write-through sync engine keeps Firestore in lockstep.
final walletsListProvider = StreamProvider<List<Wallet>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final dao = ref.watch(walletDaoProvider);
  return dao.watchAll().map(
        (rows) => rows.where((w) => w.userId == user.uid).toList()
          ..sort((a, b) {
            // Pinned (sortOrder) first, then by createdAt.
            final s = a.sortOrder.compareTo(b.sortOrder);
            if (s != 0) return s;
            return a.createdAt.compareTo(b.createdAt);
          }),
      );
});

/// Only the wallets that show up in the Home carousel: not archived,
/// optionally not hidden. (Hidden balances are still listed but the card
/// masks the number — UI choice handled in WalletCard, not here.)
final visibleWalletsProvider = Provider<AsyncValue<List<Wallet>>>((ref) {
  return ref.watch(walletsListProvider).whenData(
        (rows) => rows.where((w) => !w.isArchived).toList(),
      );
});

/// The archived side of the split. Feeds the "Archived" section of the
/// Manage wallets screen — the only place an archived wallet can be found
/// and restored, since every other surface reads [visibleWalletsProvider].
final archivedWalletsProvider = Provider<AsyncValue<List<Wallet>>>((ref) {
  return ref.watch(walletsListProvider).whenData(
        (rows) => rows.where((w) => w.isArchived).toList(),
      );
});
