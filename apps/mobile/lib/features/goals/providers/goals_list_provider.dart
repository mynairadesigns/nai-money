import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All goals owned by the current user, streamed live from Drift and
/// sorted by [Goal.createdAt] descending.
final goalsListProvider = StreamProvider<List<Goal>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(goalDaoProvider).watchAll().map(
        (rows) => rows.where((g) => g.userId == user.uid).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
});

/// Active = `completedAt` is null. Drives the Active section in
/// GoalsListScreen.
final activeGoalsProvider = Provider<AsyncValue<List<Goal>>>((ref) {
  return ref.watch(goalsListProvider).whenData(
        (rows) => rows.where((g) => g.completedAt == null).toList(),
      );
});

/// Completed = `completedAt` is set. Surfaces in the Completed section so
/// users can revisit reached goals.
final completedGoalsProvider = Provider<AsyncValue<List<Goal>>>((ref) {
  return ref.watch(goalsListProvider).whenData(
        (rows) => rows.where((g) => g.completedAt != null).toList(),
      );
});
