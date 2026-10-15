import 'package:drift/drift.dart' show Value;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';
import '../../billing/data/free_tier_exception.dart';
import '../../billing/providers/premium_providers.dart';
import '../../billing/widgets/upsell_sheet.dart';

/// Form payload for create / edit. Plain mutable POJO — the UI updates
/// fields in place, then calls [WalletsController.create] or `.update`.
class WalletFormData {
  WalletFormData({
    this.id,
    this.name = '',
    this.type = 'cash',
    this.currency = 'USD',
    this.openingBalance = 0,
    this.iconName = 'payments',
    this.colorHex = '8a4f37',
  });

  /// Non-null when editing an existing wallet.
  String? id;
  String name;
  String type;
  String currency;
  double openingBalance;
  String iconName;
  String colorHex;
}

/// AsyncNotifier driving wallet create / update / archive / unhide.
/// UI watches the [AsyncValue] for loading + error state.
final walletsControllerProvider =
    AsyncNotifierProvider<WalletsController, void>(WalletsController.new);

class WalletsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Inserts a fresh wallet. `balance` starts at `openingBalance`; the
  /// transactions feature (P2.3) bumps it on each insert.
  Future<void> create(WalletFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a wallet while signed out');
      }
      final dao = ref.read(walletDaoProvider);
      // Free-tier ceiling check (PRD §6.14.1, RC `free_tier_wallets_max`).
      if (!ref.read(isPremiumProvider)) {
        final limit = FirebaseRemoteConfig.instance
            .getInt('free_tier_wallets_max');
        final ceiling = limit > 0 ? limit : 1;
        final existing = await dao.watchAll().first;
        final mine = existing.where((w) => w.userId == user.uid).length;
        if (mine >= ceiling) {
          throw const FreeTierExceeded(UpsellReason.wallets);
        }
      }
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_w_${now.microsecondsSinceEpoch}';
      await dao.insertOne(
        WalletsCompanion(
          id: Value(id),
          userId: Value(user.uid),
          name: Value(form.name.trim()),
          type: Value(form.type),
          currency: Value(form.currency),
          balance: Value(form.openingBalance),
          iconName: Value(form.iconName),
          color: Value(form.colorHex),
          createdAt: Value(now),
          updatedAt: Value(now),
          // syncStatus defaults to 'pending' — sync engine mirrors it.
        ),
      );
    });
  }

  /// Updates an existing wallet's metadata (name, type, currency, icon,
  /// color). Does NOT touch `balance` — that's owned by transaction flow.
  /// (Named `edit` to avoid colliding with `AsyncNotifier.update`.)
  Future<void> edit(WalletFormData form) async {
    final id = form.id;
    if (id == null) {
      throw ArgumentError('edit requires a non-null id');
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(walletDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Wallet $id not found');
      final now = DateTime.now().toUtc();
      await dao.updateOne(
        WalletsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          name: Value(form.name.trim()),
          type: Value(form.type),
          currency: Value(form.currency),
          balance: Value(existing.balance),
          iconName: Value(form.iconName),
          color: Value(form.colorHex),
          isHidden: Value(existing.isHidden),
          isArchived: Value(existing.isArchived),
          sortOrder: Value(existing.sortOrder),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  /// Soft-archive: read-only, hidden from carousel (PRD §6.2).
  Future<void> archive(String id, {bool archive = true}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(walletDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Wallet $id not found');
      await dao.updateOne(
        WalletsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          name: Value(existing.name),
          type: Value(existing.type),
          currency: Value(existing.currency),
          balance: Value(existing.balance),
          iconName: Value(existing.iconName),
          color: Value(existing.color),
          isHidden: Value(existing.isHidden),
          isArchived: Value(archive),
          sortOrder: Value(existing.sortOrder),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(DateTime.now().toUtc()),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  /// Toggle hide. Hidden wallets still render but mask the balance
  /// (`••••`); biometric gate to unmask lands in P7 Security.
  Future<void> setHidden(String id, bool hidden) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(walletDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Wallet $id not found');
      await dao.updateOne(
        WalletsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          name: Value(existing.name),
          type: Value(existing.type),
          currency: Value(existing.currency),
          balance: Value(existing.balance),
          iconName: Value(existing.iconName),
          color: Value(existing.color),
          isHidden: Value(hidden),
          isArchived: Value(existing.isArchived),
          sortOrder: Value(existing.sortOrder),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(DateTime.now().toUtc()),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }
}
