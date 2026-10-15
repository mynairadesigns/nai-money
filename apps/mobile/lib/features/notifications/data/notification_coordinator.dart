import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/onboarding_state_provider.dart';
import '../../../data/local/app_database.dart';
import '../../budgets/providers/budget_progress_provider.dart';
import '../../debts/providers/debts_list_provider.dart';
import '../../goals/providers/goals_list_provider.dart';
import '../../recurring/providers/recurring_list_provider.dart';
import '../providers/notification_providers.dart';
import 'notification_service.dart';

// ---------------------------------------------------------------------------
// SharedPreferences key helpers
// ---------------------------------------------------------------------------

String _budgetFiredKey(String budgetId) => 'notif_budget_${budgetId}_fired';
String _budgetPeriodKey(String budgetId) =>
    'notif_budget_${budgetId}_period_start';
String _goalFiredKey(String goalId) => 'notif_goal_${goalId}_fired';

// ---------------------------------------------------------------------------
// Threshold helpers
// ---------------------------------------------------------------------------

/// Highest crossed budget-spend bucket. Returns `null` if below 50.
int? _budgetBucket(double pct) {
  if (pct > 100) return 101; // "over budget"
  if (pct >= 100) return 100;
  if (pct >= 80) return 80;
  if (pct >= 50) return 50;
  return null;
}

/// Highest crossed goal-progress milestone. Returns `null` if below 25.
int? _goalMilestone(double pct) {
  if (pct >= 100) return 100;
  if (pct >= 75) return 75;
  if (pct >= 50) return 50;
  if (pct >= 25) return 25;
  return null;
}

String _fmtDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// Best-effort extraction of a label from a recurring rule's JSON template.
String _recurringLabel(String templateJson) {
  try {
    final map = jsonDecode(templateJson);
    if (map is Map) {
      final note = map['note'] as String?;
      if (note != null && note.isNotEmpty) return note;
    }
  } catch (_) {}
  return 'A recurring bill';
}

// ---------------------------------------------------------------------------
// Coordinator provider
// ---------------------------------------------------------------------------

/// Top-level side-effect provider that drives all local notification
/// scheduling. Mirror the [syncLifecycleProvider] pattern — call
///
/// ```dart
/// ref.watch(notificationCoordinatorProvider);
/// ```
///
/// once at the app root (e.g. `HomaFinanceApp.build`) to keep it alive.
///
/// Subscribes to:
/// - [allActiveBudgetProgressProvider] — budget 50/80/100/over alerts
/// - [recurringRulesListProvider] — reminder-mode rules due today / overdue
/// - [debtsListProvider] — debts overdue / due today / due in ≤7 days
/// - [goalsListProvider] — goal milestones at 25/50/75/100%
/// - weeklyRecap — next Sunday 18:00 scheduled notification
final notificationCoordinatorProvider = Provider<void>((ref) {
  final svc = ref.watch(notificationServiceProvider);
  final prefs = ref.watch(notificationPrefsProvider);
  final sharedPrefs = ref.read(sharedPreferencesProvider);

  // -------------------------------------------------------------------------
  // One-time init — idempotent inside NotificationService.
  // -------------------------------------------------------------------------
  () async {
    try {
      await svc.init();
      await svc.requestPermissions();
    } catch (e) {
      debugPrint('notificationCoordinator: init error: $e');
    }
  }();

  // -------------------------------------------------------------------------
  // Budget alerts — 50 / 80 / 100 / over
  // -------------------------------------------------------------------------
  ref.listen<AsyncValue<List<BudgetProgress>>>(
    allActiveBudgetProgressProvider,
    (_, next) async {
      if (!prefs.budgetAlerts) return;
      final list = next.value;
      if (list == null) return;

      for (final progress in list) {
        try {
          final bucket = _budgetBucket(progress.pctUsed);
          if (bucket == null) continue;

          final budgetId = progress.budget.id;
          final startIso = progress.budget.startDate.toIso8601String();
          final periodKey = _budgetPeriodKey(budgetId);
          final firedKey = _budgetFiredKey(budgetId);

          // Detect period rollover and reset fired state.
          if (sharedPrefs.getString(periodKey) != startIso) {
            await sharedPrefs.setString(periodKey, startIso);
            await sharedPrefs.remove(firedKey);
          }

          final firedBucket = sharedPrefs.getInt(firedKey) ?? 0;
          if (bucket <= firedBucket) continue; // already notified this period

          final budgetLabel = progress.budget.categoryId != null
              ? 'Category budget'
              : 'Wallet budget';
          final pctStr = progress.pctUsed.toStringAsFixed(0);

          final String title;
          final String body;
          if (bucket == 101) {
            title = 'Over budget!';
            body = '$budgetLabel has exceeded its limit ($pctStr% used).';
          } else if (bucket == 100) {
            title = 'Budget fully used';
            body = '$budgetLabel reached 100% of its limit.';
          } else {
            title = 'Budget at $bucket%';
            body = '$budgetLabel is at $pctStr% of its limit.';
          }

          await svc.showNow(
            id: svc.notifId('budget_$bucket', budgetId),
            title: title,
            body: body,
            payload: 'budget:$budgetId',
          );
          await sharedPrefs.setInt(firedKey, bucket);
        } catch (e) {
          debugPrint('notificationCoordinator: budget error: $e');
        }
      }
    },
    fireImmediately: true,
  );

  // -------------------------------------------------------------------------
  // Recurring rules — reminder-mode rules due today or overdue
  // -------------------------------------------------------------------------
  ref.listen<AsyncValue<List<RecurringRule>>>(
    recurringRulesListProvider,
    (_, next) async {
      if (!prefs.recurringDue) return;
      final rules = next.value;
      if (rules == null) return;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      for (final rule in rules) {
        if (rule.isPaused) continue;
        if (rule.mode != 'reminder') continue;

        try {
          final due = rule.nextDueDate;
          final isToday =
              !due.isBefore(todayStart) && due.isBefore(todayEnd);
          final isOverdue = due.isBefore(todayStart);
          if (!isToday && !isOverdue) continue;

          final label = _recurringLabel(rule.transactionTemplate);
          final title = isOverdue ? 'Bill overdue' : 'Bill due today';
          final body = isOverdue
              ? '$label was due on ${_fmtDate(due)}.'
              : '$label is due today.';

          await svc.showNow(
            id: svc.notifId('recurring', rule.id),
            title: title,
            body: body,
            payload: 'recurring:${rule.id}',
          );
        } catch (e) {
          debugPrint('notificationCoordinator: recurring error: $e');
        }
      }
    },
    fireImmediately: true,
  );

  // -------------------------------------------------------------------------
  // Debts — overdue / due today / due in ≤7 days (scheduled)
  // -------------------------------------------------------------------------
  ref.listen<AsyncValue<List<Debt>>>(
    debtsListProvider,
    (_, next) async {
      if (!prefs.debtDue) return;
      final debts = next.value;
      if (debts == null) return;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      for (final debt in debts) {
        if (debt.status == 'settled') continue;
        final dueDate = debt.dueDate;
        if (dueDate == null) continue;

        try {
          final dueDayStart =
              DateTime(dueDate.year, dueDate.month, dueDate.day);
          final daysUntil = dueDayStart.difference(todayStart).inDays;
          if (daysUntil > 7) continue; // not yet actionable

          final direction =
              debt.type == 'lent' ? 'is owed to you' : 'is due';
          final contact =
              debt.contactName.isNotEmpty ? debt.contactName : 'a contact';
          final amtStr =
              '${debt.currency} ${debt.remainingAmount.toStringAsFixed(2)}';

          if (daysUntil < 0) {
            await svc.showNow(
              id: svc.notifId('debt_overdue', debt.id),
              title: 'Debt overdue',
              body:
                  '$amtStr $direction from $contact — overdue since ${_fmtDate(dueDate)}.',
              payload: 'debt:${debt.id}',
            );
          } else if (daysUntil == 0) {
            await svc.showNow(
              id: svc.notifId('debt_today', debt.id),
              title: 'Debt due today',
              body: '$amtStr $direction from $contact.',
              payload: 'debt:${debt.id}',
            );
          } else {
            // Schedule a reminder at 09:00 on the due date itself.
            final reminderAt = DateTime(
              dueDate.year,
              dueDate.month,
              dueDate.day,
              9,
            );
            await svc.scheduleAt(
              id: svc.notifId('debt_7d', debt.id),
              when: reminderAt,
              title: 'Debt due today',
              body: '$amtStr $direction from $contact.',
              payload: 'debt:${debt.id}',
            );
          }
        } catch (e) {
          debugPrint('notificationCoordinator: debt error: $e');
        }
      }
    },
    fireImmediately: true,
  );

  // -------------------------------------------------------------------------
  // Goals — milestones at 25 / 50 / 75 / 100 %
  // -------------------------------------------------------------------------
  ref.listen<AsyncValue<List<Goal>>>(
    goalsListProvider,
    (_, next) async {
      if (!prefs.goalMilestones) return;
      final goals = next.value;
      if (goals == null) return;

      for (final goal in goals) {
        if (goal.completedAt != null) continue;
        if (goal.targetAmount <= 0) continue;

        try {
          final pct = (goal.currentAmount / goal.targetAmount) * 100;
          final milestone = _goalMilestone(pct);
          if (milestone == null) continue;

          final firedKey = _goalFiredKey(goal.id);
          final firedMilestone = sharedPrefs.getInt(firedKey) ?? 0;
          if (milestone <= firedMilestone) continue;

          await svc.showNow(
            id: svc.notifId('goal_$milestone', goal.id),
            title: 'Goal milestone — $milestone%!',
            body: '${goal.name} is $milestone% funded. Keep it up!',
            payload: 'goal:${goal.id}',
          );
          await sharedPrefs.setInt(firedKey, milestone);
        } catch (e) {
          debugPrint('notificationCoordinator: goal error: $e');
        }
      }
    },
    fireImmediately: true,
  );

  // -------------------------------------------------------------------------
  // Weekly recap — schedule next Sunday at 18:00 local
  // -------------------------------------------------------------------------
  if (prefs.weeklyRecap) {
    _scheduleWeeklyRecap(svc);
  } else {
    svc.cancel(svc.notifId('weekly_recap', 'global'));
  }
});

// ---------------------------------------------------------------------------
// Weekly recap helper
// ---------------------------------------------------------------------------

Future<void> _scheduleWeeklyRecap(NotificationService svc) async {
  try {
    final now = DateTime.now();
    // DateTime.sunday == 7. daysUntilSunday == 0 when today is Sunday.
    final daysUntilSunday = (DateTime.sunday - now.weekday + 7) % 7;
    var nextSunday = DateTime(
      now.year,
      now.month,
      now.day + daysUntilSunday,
      18,
    );
    // If today is Sunday and 18:00 is already past, push to next Sunday.
    if (nextSunday.isBefore(now)) {
      nextSunday = nextSunday.add(const Duration(days: 7));
    }

    await svc.scheduleAt(
      id: svc.notifId('weekly_recap', 'global'),
      when: nextSunday,
      title: 'Your weekly recap is ready',
      body: 'See how your finances looked this week.',
      payload: 'weekly_recap',
    );
  } catch (e) {
    debugPrint('notificationCoordinator: weeklyRecap error: $e');
  }
}
