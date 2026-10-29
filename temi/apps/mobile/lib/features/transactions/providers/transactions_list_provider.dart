import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All transactions for the signed-in user, newest first.
/// Drift is the source of truth; UI reads here, never from Firestore.
final transactionsListProvider = StreamProvider<List<Transaction>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(transactionDaoProvider).watchAllForUser(user.uid);
});

/// Last 5 transactions for the Home dashboard's "Recent" card.
final recentTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(transactionDaoProvider).watchRecentForUser(user.uid, 5);
});

/// Transactions filtered to a specific wallet (used by WalletDetailScreen).
final walletTransactionsProvider =
    StreamProvider.family<List<Transaction>, String>((ref, walletId) {
  return ref.watch(transactionDaoProvider).watchByWallet(walletId);
});
