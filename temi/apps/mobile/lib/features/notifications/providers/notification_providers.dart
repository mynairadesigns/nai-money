import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/onboarding_state_provider.dart';
import '../data/notification_service.dart';

// ---------------------------------------------------------------------------
// NotificationService provider
// ---------------------------------------------------------------------------

/// Single shared [NotificationService] instance. Callers never call [init]
/// directly — that is handled by [notificationCoordinatorProvider].
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

// ---------------------------------------------------------------------------
// NotificationPrefs
// ---------------------------------------------------------------------------

/// Immutable snapshot of all notification toggle preferences.
class NotificationPrefs {
  const NotificationPrefs({
    this.budgetAlerts = true,
    this.recurringDue = true,
    this.debtDue = true,
    this.goalMilestones = true,
    this.anomalyAlerts = true,
    this.weeklyRecap = true,
  });

  final bool budgetAlerts;
  final bool recurringDue;
  final bool debtDue;
  final bool goalMilestones;
  final bool anomalyAlerts;
  final bool weeklyRecap;

  NotificationPrefs copyWith({
    bool? budgetAlerts,
    bool? recurringDue,
    bool? debtDue,
    bool? goalMilestones,
    bool? anomalyAlerts,
    bool? weeklyRecap,
  }) {
    return NotificationPrefs(
      budgetAlerts: budgetAlerts ?? this.budgetAlerts,
      recurringDue: recurringDue ?? this.recurringDue,
      debtDue: debtDue ?? this.debtDue,
      goalMilestones: goalMilestones ?? this.goalMilestones,
      anomalyAlerts: anomalyAlerts ?? this.anomalyAlerts,
      weeklyRecap: weeklyRecap ?? this.weeklyRecap,
    );
  }
}

// SharedPreferences keys
const _kBudget = 'notif_budget';
const _kRecurring = 'notif_recurring';
const _kDebt = 'notif_debt';
const _kGoal = 'notif_goal';
const _kAnomaly = 'notif_anomaly';
const _kWeeklyRecap = 'notif_weekly_recap';

/// Reads and writes notification toggle preferences via SharedPreferences.
/// All toggles default to `true` on first launch.
final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
  NotificationPrefsNotifier.new,
);

class NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  @override
  NotificationPrefs build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return _load(prefs);
  }

  static NotificationPrefs _load(SharedPreferences prefs) {
    return NotificationPrefs(
      budgetAlerts: prefs.getBool(_kBudget) ?? true,
      recurringDue: prefs.getBool(_kRecurring) ?? true,
      debtDue: prefs.getBool(_kDebt) ?? true,
      goalMilestones: prefs.getBool(_kGoal) ?? true,
      anomalyAlerts: prefs.getBool(_kAnomaly) ?? true,
      weeklyRecap: prefs.getBool(_kWeeklyRecap) ?? true,
    );
  }

  Future<void> setBudgetAlerts(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_kBudget, value);
    state = state.copyWith(budgetAlerts: value);
  }

  Future<void> setRecurringDue(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_kRecurring, value);
    state = state.copyWith(recurringDue: value);
  }

  Future<void> setDebtDue(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_kDebt, value);
    state = state.copyWith(debtDue: value);
  }

  Future<void> setGoalMilestones(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_kGoal, value);
    state = state.copyWith(goalMilestones: value);
  }

  Future<void> setAnomalyAlerts(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_kAnomaly, value);
    state = state.copyWith(anomalyAlerts: value);
  }

  Future<void> setWeeklyRecap(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_kWeeklyRecap, value);
    state = state.copyWith(weeklyRecap: value);
  }
}
