import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/transactions_filter.dart';
import 'transactions_list_provider.dart';

/// Active filter for the Transactions tab. Survives navigation within
/// the session; cleared on cold start (intentional — saved presets
/// are P7 polish).
final transactionsFilterProvider = NotifierProvider<
    TransactionsFilterController, TransactionsFilter>(
  TransactionsFilterController.new,
);

class TransactionsFilterController extends Notifier<TransactionsFilter> {
  @override
  TransactionsFilter build() => const TransactionsFilter();

  void set(TransactionsFilter f) => state = f;
  void clear() => state = const TransactionsFilter();
}

/// Free-text search query against transaction `note` (and, in P3, contact
/// name / tags). Separate from the structured filter so the user can
/// search and filter simultaneously.
final transactionsSearchProvider = NotifierProvider<
    TransactionsSearchController, String>(
  TransactionsSearchController.new,
);

class TransactionsSearchController extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q;
  void clear() => state = '';
}

/// The list rendered by /transactions = base stream ∩ filter ∩ search.
/// All client-side for now (small data scale per PRD §15 v1 target).
///
/// Search matches any of: note text, amount as printed string, currency
/// code, the category's name, or the wallet's name. This is more useful
/// than note-only (most rows have empty notes).
final filteredTransactionsProvider =
    Provider<AsyncValue<List<Transaction>>>((ref) {
  final base = ref.watch(transactionsListProvider);
  final filter = ref.watch(transactionsFilterProvider);
  final query = ref.watch(transactionsSearchProvider).trim().toLowerCase();
  final wallets = ref.watch(walletsListProvider).value ?? const <Wallet>[];
  final categories =
      ref.watch(categoriesListProvider).value ?? const <Category>[];

  // Index lookups so we don't do a linear search per row.
  final walletNameById = {for (final w in wallets) w.id: w.name.toLowerCase()};
  final categoryNameById = {
    for (final c in categories) c.id: c.name.toLowerCase(),
  };

  return base.whenData(
    (rows) {
      Iterable<Transaction> r = rows;
      if (filter.types.isNotEmpty) {
        r = r.where((t) => filter.types.contains(t.type));
      }
      if (filter.walletIds.isNotEmpty) {
        r = r.where((t) => filter.walletIds.contains(t.walletId));
      }
      if (filter.categoryIds.isNotEmpty) {
        r = r.where((t) => filter.categoryIds.contains(t.categoryId));
      }
      final range = filter.dateRange;
      if (range != null) {
        r = r.where(
          (t) =>
              !t.date.isBefore(range.start) &&
              t.date.isBefore(range.end.add(const Duration(days: 1))),
        );
      }
      final minA = filter.minAmount;
      if (minA != null) r = r.where((t) => t.amount >= minA);
      final maxA = filter.maxAmount;
      if (maxA != null) r = r.where((t) => t.amount <= maxA);
      if (query.isNotEmpty) {
        r = r.where((t) {
          if ((t.note ?? '').toLowerCase().contains(query)) return true;
          if (t.currency.toLowerCase().contains(query)) return true;
          // Match the amount as a free-form string ("100" matches "100",
          // "100.00", "1100"). Cheap toString — formatting is consistent
          // across rows.
          if (t.amount.toString().contains(query)) return true;
          final catName = categoryNameById[t.categoryId];
          if (catName != null && catName.contains(query)) return true;
          final walletName = walletNameById[t.walletId];
          if (walletName != null && walletName.contains(query)) return true;
          return false;
        });
      }
      return r.toList();
    },
  );
});
