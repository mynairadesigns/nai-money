import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../providers/notification_providers.dart';

/// `/settings/notifications` — toggles for each notification category.
///
/// Each [SwitchListTile] reads from and writes to [notificationPrefsProvider].
/// Visual style matches [SettingsScreen] (ListTile-based list with section
/// headers).
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),

          // ── Budgets ──────────────────────────────────────────────────────
          _SectionHeader(title: 'Budgets', theme: theme),
          SwitchListTile(
            secondary: const Icon(Icons.donut_small_outlined),
            title: const Text('Budget alerts'),
            subtitle: const Text(
              'Notify when spending reaches 50%, 80%, 100%, or exceeds a budget.',
            ),
            value: prefs.budgetAlerts,
            onChanged: notifier.setBudgetAlerts,
          ),

          // ── Bills & recurring ─────────────────────────────────────────────
          _SectionHeader(title: 'Bills & recurring', theme: theme),
          SwitchListTile(
            secondary: const Icon(Icons.event_repeat_outlined),
            title: const Text('Recurring bill reminders'),
            subtitle: const Text(
              'Notify when a reminder-mode recurring bill is due today or overdue.',
            ),
            value: prefs.recurringDue,
            onChanged: notifier.setRecurringDue,
          ),

          // ── Debts ─────────────────────────────────────────────────────────
          _SectionHeader(title: 'Debts', theme: theme),
          SwitchListTile(
            secondary: const Icon(Icons.handshake_outlined),
            title: const Text('Debt due reminders'),
            subtitle: const Text(
              'Notify when a debt is due within 7 days, due today, or overdue.',
            ),
            value: prefs.debtDue,
            onChanged: notifier.setDebtDue,
          ),

          // ── Goals ─────────────────────────────────────────────────────────
          _SectionHeader(title: 'Goals', theme: theme),
          SwitchListTile(
            secondary: const Icon(Icons.flag_outlined),
            title: const Text('Goal milestones'),
            subtitle: const Text(
              'Celebrate when a goal reaches 25%, 50%, 75%, or 100% funded.',
            ),
            value: prefs.goalMilestones,
            onChanged: notifier.setGoalMilestones,
          ),

          // ── AI ────────────────────────────────────────────────────────────
          _SectionHeader(title: 'AI', theme: theme),
          SwitchListTile(
            secondary: const Icon(Icons.auto_graph_outlined),
            title: const Text('Anomaly alerts'),
            subtitle: const Text(
              'Notify when the AI detects unusual spending patterns.',
            ),
            value: prefs.anomalyAlerts,
            onChanged: notifier.setAnomalyAlerts,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.calendar_today_outlined),
            title: const Text('Weekly recap'),
            subtitle: const Text(
              'Remind you every Sunday at 18:00 to review your weekly summary.',
            ),
            value: prefs.weeklyRecap,
            onChanged: notifier.setWeeklyRecap,
          ),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.theme});

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
