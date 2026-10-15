import 'package:flutter_test/flutter_test.dart';
import 'package:homa_finance/features/recurring/data/recurring_catalog.dart';

/// `addRecurringInterval` MUST stay behaviour-identical to the server
/// `addInterval(...)` in `apps/functions/src/schedulers/process_recurring_rules.ts`
/// (recurring transactions are materialized server-side, advanced client-side).
/// These cases pin the contract — especially month/year end-of-month overflow,
/// which both sides delegate to their date constructor.
void main() {
  group('addRecurringInterval', () {
    test('daily advances by N days', () {
      final base = DateTime(2026, 5, 25);
      expect(addRecurringInterval(base, 'daily', 1), DateTime(2026, 5, 26));
      expect(addRecurringInterval(base, 'daily', 10), DateTime(2026, 6, 4));
    });

    test('weekly advances by 7 * N days', () {
      final base = DateTime(2026, 5, 25);
      expect(addRecurringInterval(base, 'weekly', 1), DateTime(2026, 6, 1));
      expect(addRecurringInterval(base, 'weekly', 2), DateTime(2026, 6, 8));
    });

    test('monthly advances by N months', () {
      final base = DateTime(2026, 1, 15);
      expect(addRecurringInterval(base, 'monthly', 1), DateTime(2026, 2, 15));
      expect(addRecurringInterval(base, 'monthly', 3), DateTime(2026, 4, 15));
    });

    test('monthly overflows month-end like new Date(y, m+n, d)', () {
      // Jan 31 + 1 month → Feb has no 31st → rolls to Mar 3 (2026 not leap).
      final base = DateTime(2026, 1, 31);
      expect(addRecurringInterval(base, 'monthly', 1), DateTime(2026, 3, 3));
    });

    test('yearly advances by N years', () {
      final base = DateTime(2026, 5, 25);
      expect(addRecurringInterval(base, 'yearly', 1), DateTime(2027, 5, 25));
    });

    test('yearly overflows Feb 29 onto a non-leap year', () {
      // 2028 is a leap year; +1 year lands on 2029 which has no Feb 29 → Mar 1.
      final base = DateTime(2028, 2, 29);
      expect(addRecurringInterval(base, 'yearly', 1), DateTime(2029, 3, 1));
    });

    test('preserves the time-of-day components', () {
      final base = DateTime(2026, 5, 25, 9, 30, 15);
      final next = addRecurringInterval(base, 'monthly', 1);
      expect(next, DateTime(2026, 6, 25, 9, 30, 15));
    });

    test('interval < 1 is clamped to 1', () {
      final base = DateTime(2026, 5, 25);
      expect(addRecurringInterval(base, 'daily', 0), DateTime(2026, 5, 26));
      expect(addRecurringInterval(base, 'daily', -3), DateTime(2026, 5, 26));
    });

    test('unknown frequency nudges forward one day (no infinite loop)', () {
      final base = DateTime(2026, 5, 25);
      expect(addRecurringInterval(base, 'fortnightly', 1), DateTime(2026, 5, 26));
    });
  });
}
