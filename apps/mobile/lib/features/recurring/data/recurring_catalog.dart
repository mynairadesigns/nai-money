// Static option lists + helpers for the P3.2 Recurring feature.
// Mirrors the server-side scheduler `process_recurring_rules.ts`:
// any change to the frequency set or the [addRecurringInterval] math
// must also land on the server.

class RecurringFrequencyOption {
  const RecurringFrequencyOption({required this.key, required this.label});
  final String key;
  final String label;
}

/// Frequencies supported by `process_recurring_rules.ts`. The [key] is
/// what we persist; the [label] is the user-facing form/segment text.
const kRecurringFrequencyCatalog = <RecurringFrequencyOption>[
  RecurringFrequencyOption(key: 'daily', label: 'Daily'),
  RecurringFrequencyOption(key: 'weekly', label: 'Weekly'),
  RecurringFrequencyOption(key: 'monthly', label: 'Monthly'),
  RecurringFrequencyOption(key: 'yearly', label: 'Yearly'),
];

class RecurringModeOption {
  const RecurringModeOption({required this.key, required this.label});
  final String key;
  final String label;
}

/// PRD §6.6: Auto materializes a transaction; Reminder only nudges the
/// user. P7 polish ships Reminder behavior; until then the server treats
/// both modes identically — but we still persist the user's choice so
/// the upgrade is data-compatible.
const kRecurringModeCatalog = <RecurringModeOption>[
  RecurringModeOption(key: 'auto', label: 'Auto'),
  RecurringModeOption(key: 'reminder', label: 'Reminder'),
];

/// Human label for a stored frequency key (falls back to title-case).
String labelForRecurringFrequency(String key) {
  for (final opt in kRecurringFrequencyCatalog) {
    if (opt.key == key) return opt.label;
  }
  if (key.isEmpty) return key;
  return '${key[0].toUpperCase()}${key.substring(1)}';
}

/// Human label for a stored mode key.
String labelForRecurringMode(String key) {
  for (final opt in kRecurringModeCatalog) {
    if (opt.key == key) return opt.label;
  }
  if (key.isEmpty) return key;
  return '${key[0].toUpperCase()}${key.substring(1)}';
}

/// "Every 2 weeks" / "Monthly" — the summary phrase shown on rule cards
/// and the detail header.
String summarizeFrequency(String frequency, int interval) {
  final i = interval < 1 ? 1 : interval;
  if (i == 1) {
    switch (frequency) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'yearly':
        return 'Yearly';
      default:
        return labelForRecurringFrequency(frequency);
    }
  }
  final unit = switch (frequency) {
    'daily' => 'days',
    'weekly' => 'weeks',
    'monthly' => 'months',
    'yearly' => 'years',
    _ => frequency,
  };
  return 'Every $i $unit';
}

/// Advances [base] by [interval] units of [frequency]. Must stay
/// behaviour-identical to the server `addInterval(...)` helper in
/// `apps/functions/src/schedulers/process_recurring_rules.ts`.
///
/// Day/week math is straight `Duration`. Month/year math uses the
/// `DateTime(y, m, d)` constructor so end-of-month overflow follows
/// the same rule as JS `new Date(y, m+n, d)`.
DateTime addRecurringInterval(
  DateTime base,
  String frequency,
  int interval,
) {
  final i = interval < 1 ? 1 : interval;
  switch (frequency) {
    case 'daily':
      return base.add(Duration(days: i));
    case 'weekly':
      return base.add(Duration(days: 7 * i));
    case 'monthly':
      return DateTime(
        base.year,
        base.month + i,
        base.day,
        base.hour,
        base.minute,
        base.second,
      );
    case 'yearly':
      return DateTime(
        base.year + i,
        base.month,
        base.day,
        base.hour,
        base.minute,
        base.second,
      );
    default:
      // Unknown frequency: nudge by a day so callers don't loop forever.
      return base.add(const Duration(days: 1));
  }
}
