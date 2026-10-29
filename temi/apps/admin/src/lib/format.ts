/**
 * Display formatting shared across modules.
 *
 * Pure and locale-pinned to en-US on purpose: these render inside server
 * components, so relying on the runtime's default locale would make output
 * depend on where the container happens to run.
 */

const NUMBER = new Intl.NumberFormat('en-US');
const DATE = new Intl.DateTimeFormat('en-US', {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
});
const DATE_TIME = new Intl.DateTimeFormat('en-US', {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

/** An em-dash reads as "no value", where "0" or "Invalid Date" would mislead. */
export const EMPTY = '—';

export function formatNumber(n: number | null | undefined): string {
  return n == null || !Number.isFinite(n) ? EMPTY : NUMBER.format(n);
}

export function formatDate(ms: number | null | undefined): string {
  return ms == null ? EMPTY : DATE.format(new Date(ms));
}

export function formatDateTime(ms: number | null | undefined): string {
  return ms == null ? EMPTY : DATE_TIME.format(new Date(ms));
}

/**
 * Coarse relative time — "3d ago". Deliberately not minute-accurate: these
 * render on the server, so a precise value would be stale the moment it is
 * sent and would also defeat any caching.
 */
export function formatRelative(
  ms: number | null | undefined,
  nowMs: number,
): string {
  if (ms == null) return EMPTY;

  const seconds = Math.round((nowMs - ms) / 1000);
  if (seconds < 60) return 'just now';

  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;

  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;

  const days = Math.round(hours / 24);
  if (days < 30) return `${days}d ago`;

  const months = Math.round(days / 30);
  if (months < 12) return `${months}mo ago`;

  return `${Math.round(months / 12)}y ago`;
}

/**
 * USD with enough precision to be useful for AI spend, where a single call can
 * cost a fraction of a cent. Sub-cent totals would otherwise all render "$0.00"
 * and look broken.
 */
export function formatUsd(amount: number): string {
  if (!Number.isFinite(amount)) return EMPTY;
  if (amount === 0) return '$0.00';
  if (amount < 0.01) return `<$0.01`;
  return `$${amount.toFixed(amount < 100 ? 2 : 0)}`;
}

export function formatPercent(value: number, total: number): string {
  if (!total) return '0.0%';
  return `${((value / total) * 100).toFixed(1)}%`;
}

/** `YYYY-MM` for a date, in UTC — matches the aiUsage document id scheme. */
export function yearMonth(date: Date): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

/** The `YYYY-MM` key for the month before [date]. */
export function previousYearMonth(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() - 1, 1));
  return yearMonth(d);
}
