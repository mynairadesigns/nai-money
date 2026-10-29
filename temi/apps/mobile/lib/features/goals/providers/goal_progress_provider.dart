import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/app_database.dart';
import 'goals_list_provider.dart';

/// Derived progress for a single goal — pct, days-to-deadline, and the
/// per-month contribution implied by the remaining gap.
class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.pct,
    required this.daysRemaining,
    required this.requiredPerMonth,
  });

  final Goal goal;

  /// `currentAmount / targetAmount`, clamped to `[0, 1]`.
  final double pct;

  /// Whole days from now until [Goal.deadline]; null when no deadline.
  final int? daysRemaining;

  /// Suggested monthly contribution to hit the target by the deadline.
  /// Null when there's no deadline, the deadline is in the past, or the
  /// target is already met.
  final double? requiredPerMonth;
}

/// Live progress for [goalId]. Reads through [goalsListProvider] (rather
/// than the DAO directly) so the row stays in lockstep with the list
/// screen's stream.
final goalProgressProvider =
    Provider.family<GoalProgress?, String>((ref, goalId) {
  final rows = ref.watch(goalsListProvider).value;
  if (rows == null) return null;
  Goal? goal;
  for (final g in rows) {
    if (g.id == goalId) {
      goal = g;
      break;
    }
  }
  if (goal == null) return null;

  final target = goal.targetAmount;
  final current = goal.currentAmount;
  final rawPct = target <= 0 ? 0.0 : current / target;
  final pct = rawPct.isNaN
      ? 0.0
      : rawPct.clamp(0.0, 1.0).toDouble();

  int? daysRemaining;
  final deadline = goal.deadline;
  if (deadline != null) {
    final diff = deadline.difference(DateTime.now()).inDays;
    daysRemaining = diff < 0 ? 0 : diff;
  }

  double? requiredPerMonth;
  final remaining = target - current;
  if (deadline != null && daysRemaining != null && remaining > 0) {
    if (daysRemaining > 0) {
      requiredPerMonth = remaining / (daysRemaining / 30.0);
    } else {
      // Deadline today or past — surface the full remaining as "now".
      requiredPerMonth = remaining;
    }
  }

  return GoalProgress(
    goal: goal,
    pct: pct,
    daysRemaining: daysRemaining,
    requiredPerMonth: requiredPerMonth,
  );
});
