import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// All recurring rules owned by the current user, sorted by `nextDueDate`
/// asc so soon-to-fire rules surface first. Drift is the source of
/// truth; the sync engine mirrors to Firestore for the daily scheduler
/// in `apps/functions/src/schedulers/process_recurring_rules.ts`.
final recurringRulesListProvider = StreamProvider<List<RecurringRule>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  return ref.watch(recurringRuleDaoProvider).watchAll().map(
        (rows) => rows.where((r) => r.userId == user.uid).toList()
          ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate)),
      );
});

/// Active = not paused. Rendered in the "Active" section of the list.
final activeRecurringRulesProvider =
    Provider<AsyncValue<List<RecurringRule>>>((ref) {
  return ref.watch(recurringRulesListProvider).whenData(
        (rows) => rows.where((r) => !r.isPaused).toList(),
      );
});

/// Paused = paused by the user, or auto-paused by the scheduler once the
/// rule's endDate passed. Surfaces under a "Paused" header.
final pausedRecurringRulesProvider =
    Provider<AsyncValue<List<RecurringRule>>>((ref) {
  return ref.watch(recurringRulesListProvider).whenData(
        (rows) => rows.where((r) => r.isPaused).toList(),
      );
});
