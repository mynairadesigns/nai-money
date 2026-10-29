import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All debts owned by the current user, sorted by `createdAt` desc.
final debtsListProvider = StreamProvider<List<Debt>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(debtDaoProvider).watchAll().map(
        (rows) => rows.where((d) => d.userId == user.uid).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
});

/// "I lent money" rows. UI groups these under the **Lent** section.
final lentDebtsProvider = Provider<AsyncValue<List<Debt>>>((ref) {
  return ref.watch(debtsListProvider).whenData(
        (rows) => rows.where((d) => d.type == 'lent').toList(),
      );
});

/// "I borrowed money" rows. UI groups these under the **Borrowed** section.
final borrowedDebtsProvider = Provider<AsyncValue<List<Debt>>>((ref) {
  return ref.watch(debtsListProvider).whenData(
        (rows) => rows.where((d) => d.type == 'borrowed').toList(),
      );
});
