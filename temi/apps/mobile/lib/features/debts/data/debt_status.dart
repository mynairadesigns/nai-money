import '../../../data/local/app_database.dart';

/// Derived debt status. The Drift `Debt.status` column is persisted for
/// sync compatibility (PRD §5.1) but never read by the UI — the source
/// of truth for what to render is [debtStatus], computed from
/// `remainingAmount` + `dueDate` + the current clock.
enum DebtStatus { open, dueSoon, overdue, settled }

/// Pure-function derivation. Pass a fixed [now] in tests; production
/// callers can omit it.
///
/// Rules (in order):
/// - **settled** when `remainingAmount <= 0` (with a small epsilon to
///   absorb float roundoff from payment math).
/// - **overdue** when `dueDate != null && dueDate < today` (local).
/// - **dueSoon** when `dueDate != null && dueDate` is within 7 days
///   from today (inclusive).
/// - **open** otherwise.
DebtStatus debtStatus(Debt d, {DateTime? now}) {
  if (d.remainingAmount <= 0.005) return DebtStatus.settled;
  final due = d.dueDate;
  if (due == null) return DebtStatus.open;
  final today = (now ?? DateTime.now()).toLocal();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final dueLocal = due.toLocal();
  final startOfDue = DateTime(dueLocal.year, dueLocal.month, dueLocal.day);
  if (startOfDue.isBefore(startOfToday)) return DebtStatus.overdue;
  final diffDays = startOfDue.difference(startOfToday).inDays;
  if (diffDays <= 7) return DebtStatus.dueSoon;
  return DebtStatus.open;
}

String debtStatusLabel(DebtStatus s) {
  switch (s) {
    case DebtStatus.open:
      return 'Open';
    case DebtStatus.dueSoon:
      return 'Due soon';
    case DebtStatus.overdue:
      return 'Overdue';
    case DebtStatus.settled:
      return 'Settled';
  }
}
