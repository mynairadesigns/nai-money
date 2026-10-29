import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All categories owned by the current user, sorted by sortOrder then name.
/// Drift is the source of truth; the sync engine keeps Firestore in lockstep.
final categoriesListProvider = StreamProvider<List<Category>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final dao = ref.watch(categoryDaoProvider);
  return dao.watchAll().map(
        (rows) => rows.where((c) => c.userId == user.uid).toList()
          ..sort((a, b) {
            final s = a.sortOrder.compareTo(b.sortOrder);
            if (s != 0) return s;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }),
      );
});

/// Convenience derived providers — used by the manage screen to render
/// the two sections without re-filtering inline.
final expenseCategoriesProvider = Provider<AsyncValue<List<Category>>>((ref) {
  return ref.watch(categoriesListProvider).whenData(
        (rows) => rows.where((c) => c.type == 'expense').toList(),
      );
});

final incomeCategoriesProvider = Provider<AsyncValue<List<Category>>>((ref) {
  return ref.watch(categoriesListProvider).whenData(
        (rows) => rows.where((c) => c.type == 'income').toList(),
      );
});
