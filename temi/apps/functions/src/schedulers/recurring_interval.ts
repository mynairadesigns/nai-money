/**
 * Pure interval-arithmetic for recurring rules.
 *
 * This module has ZERO firebase imports so it can be unit-tested
 * without initialising firebase-admin. It is the canonical implementation
 * of "advance by N units of frequency"; the mobile mirror lives at
 * `apps/mobile/lib/features/recurring/data/recurring_catalog.dart`
 * (`addRecurringInterval`). Any change here needs the same change there.
 */

/**
 * Advances [date] by [interval] units of [frequency].
 *
 * Month/year arithmetic uses `Date.UTC(y, m, d, ...)` so JS handles
 * month-end overflow (e.g. Jan 31 + 1 month → Mar 3 in a non-leap year,
 * because month 1 day 31 overflows into March).
 *
 * @param date     Source date (not mutated).
 * @param frequency 'daily' | 'weekly' | 'monthly' | 'yearly' — anything
 *                  else falls back to +1 day so callers never loop forever.
 * @param interval  Positive integer multiplier.
 * @returns A new Date representing the next occurrence.
 */
export function addInterval(date: Date, frequency: string, interval: number): Date {
  const d = new Date(date.getTime());
  switch (frequency) {
    case 'daily':
      d.setUTCDate(d.getUTCDate() + interval);
      return d;
    case 'weekly':
      d.setUTCDate(d.getUTCDate() + 7 * interval);
      return d;
    case 'monthly':
      return new Date(
        Date.UTC(
          d.getUTCFullYear(),
          d.getUTCMonth() + interval,
          d.getUTCDate(),
          d.getUTCHours(),
          d.getUTCMinutes(),
          d.getUTCSeconds(),
        ),
      );
    case 'yearly':
      return new Date(
        Date.UTC(
          d.getUTCFullYear() + interval,
          d.getUTCMonth(),
          d.getUTCDate(),
          d.getUTCHours(),
          d.getUTCMinutes(),
          d.getUTCSeconds(),
        ),
      );
    default:
      // Unknown frequency — advance by one day so callers never loop forever.
      d.setUTCDate(d.getUTCDate() + 1);
      return d;
  }
}
