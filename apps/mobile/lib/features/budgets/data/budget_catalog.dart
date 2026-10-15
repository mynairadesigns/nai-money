/// Period option for budgets (PRD §6.5).
class BudgetPeriodOption {
  const BudgetPeriodOption({
    required this.key,
    required this.label,
  });
  final String key;
  final String label;
}

const kBudgetPeriodCatalog = <BudgetPeriodOption>[
  BudgetPeriodOption(key: 'weekly', label: 'Weekly'),
  BudgetPeriodOption(key: 'monthly', label: 'Monthly'),
  BudgetPeriodOption(key: 'custom', label: 'Custom'),
];

/// PRD §6.5 default threshold (yellow → red transition at 80%).
const kDefaultBudgetThresholdPercent = 80;

/// Threshold options surfaced as a chip row in Add Budget.
const kBudgetThresholdOptions = <int>[50, 80, 90, 100];

/// Per-period defaults: how to advance the start/end window from a given
/// anchor date.
///
/// - weekly: 7-day rolling window starting Monday
/// - monthly: calendar-month aligned (1st → 1st)
/// - custom: caller supplies both dates
({DateTime start, DateTime end}) defaultRangeForPeriod(
  String period, {
  DateTime? anchor,
}) {
  final now = (anchor ?? DateTime.now()).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  switch (period) {
    case 'weekly':
      final weekday = today.weekday; // 1=Mon..7=Sun
      final start = today.subtract(Duration(days: weekday - 1));
      return (start: start, end: start.add(const Duration(days: 7)));
    case 'monthly':
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      return (start: start, end: end);
    case 'custom':
    default:
      // Caller is expected to supply both; this is a safe fallback that
      // mirrors monthly so the form always has something to anchor on.
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      return (start: start, end: end);
  }
}
