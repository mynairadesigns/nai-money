import { addInterval } from './recurring_interval';

/**
 * Unit tests for `addInterval`.
 *
 * These cases mirror `apps/mobile/test/features/recurring/recurring_interval_test.dart`
 * — client + server parity is the whole point.
 *
 * All dates are constructed via `Date.UTC(...)` so tests are timezone-agnostic.
 */

describe('addInterval', () => {
  // Base date: 2026-01-15 00:00:00 UTC
  const base = new Date(Date.UTC(2026, 0, 15, 0, 0, 0));

  // ── daily ────────────────────────────────────────────────────────────────

  it('daily +1 advances by 1 day', () => {
    const result = addInterval(base, 'daily', 1);
    const expected = new Date(Date.UTC(2026, 0, 16, 0, 0, 0));
    expect(result.getTime()).toBe(expected.getTime());
  });

  it('daily +7 advances by 7 days', () => {
    const result = addInterval(base, 'daily', 7);
    const expected = new Date(Date.UTC(2026, 0, 22, 0, 0, 0));
    expect(result.getTime()).toBe(expected.getTime());
  });

  // ── weekly ───────────────────────────────────────────────────────────────

  it('weekly +1 advances by 7 days', () => {
    const result = addInterval(base, 'weekly', 1);
    const expected = new Date(Date.UTC(2026, 0, 22, 0, 0, 0));
    expect(result.getTime()).toBe(expected.getTime());
  });

  it('weekly +2 advances by 14 days', () => {
    const result = addInterval(base, 'weekly', 2);
    const expected = new Date(Date.UTC(2026, 0, 29, 0, 0, 0));
    expect(result.getTime()).toBe(expected.getTime());
  });

  // ── monthly ──────────────────────────────────────────────────────────────

  it('monthly +1 advances by 1 month', () => {
    const result = addInterval(base, 'monthly', 1);
    const expected = new Date(Date.UTC(2026, 1, 15, 0, 0, 0)); // 2026-02-15
    expect(result.getTime()).toBe(expected.getTime());
  });

  it('monthly +3 advances by 3 months', () => {
    const result = addInterval(base, 'monthly', 3);
    const expected = new Date(Date.UTC(2026, 3, 15, 0, 0, 0)); // 2026-04-15
    expect(result.getTime()).toBe(expected.getTime());
  });

  it('monthly end-of-month overflow: Jan 31 + 1 month → Mar 3 (non-leap 2026)', () => {
    // In 2026 (not a leap year) February has 28 days.
    // Date.UTC(2026, 1, 31) overflows into March: Feb 28 + 3 = Mar 3.
    const jan31 = new Date(Date.UTC(2026, 0, 31, 0, 0, 0));
    const result = addInterval(jan31, 'monthly', 1);
    const expected = new Date(Date.UTC(2026, 1, 31, 0, 0, 0)); // JS overflow → Mar 3
    expect(result.getTime()).toBe(expected.getTime());
  });

  // ── yearly ───────────────────────────────────────────────────────────────

  it('yearly +1 advances by 1 year', () => {
    const result = addInterval(base, 'yearly', 1);
    const expected = new Date(Date.UTC(2027, 0, 15, 0, 0, 0)); // 2027-01-15
    expect(result.getTime()).toBe(expected.getTime());
  });

  it('yearly +2 advances by 2 years', () => {
    const result = addInterval(base, 'yearly', 2);
    const expected = new Date(Date.UTC(2028, 0, 15, 0, 0, 0)); // 2028-01-15
    expect(result.getTime()).toBe(expected.getTime());
  });

  it('yearly: Feb 29 2028 (leap) + 1 year → Mar 1 2029', () => {
    // 2029 is not a leap year, so Feb 29 overflows to Mar 1.
    const feb29 = new Date(Date.UTC(2028, 1, 29, 0, 0, 0));
    const result = addInterval(feb29, 'yearly', 1);
    // Date.UTC(2029, 1, 29) → JS overflows to March 1 2029
    const expected = new Date(Date.UTC(2029, 1, 29, 0, 0, 0));
    expect(result.getTime()).toBe(expected.getTime());
  });

  // ── unknown frequency fallback ────────────────────────────────────────────

  it('unknown frequency falls back to +1 day', () => {
    const result = addInterval(base, 'biweekly', 3);
    const expected = new Date(Date.UTC(2026, 0, 16, 0, 0, 0)); // +1 day
    expect(result.getTime()).toBe(expected.getTime());
  });

  // ── source date is not mutated ────────────────────────────────────────────

  it('does not mutate the input date', () => {
    const original = base.getTime();
    addInterval(base, 'daily', 1);
    expect(base.getTime()).toBe(original);
  });
});
