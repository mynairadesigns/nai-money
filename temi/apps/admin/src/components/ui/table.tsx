import type { ComponentProps, ReactNode } from 'react';

import { cx } from './index';

/**
 * Table primitives.
 *
 * Wide content must scroll inside its own container rather than pushing the
 * page sideways, so <Table> always wraps itself in an overflow-x region.
 * Per the design system, rows are separated by a 10%-opacity divider — never a
 * border grid.
 */

export function Table({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-left">{children}</table>
    </div>
  );
}

export function THead({ children }: { children: ReactNode }) {
  return (
    <thead>
      <tr className="border-b border-outline/10">{children}</tr>
    </thead>
  );
}

export function TH({
  children,
  numeric,
  className,
}: {
  children: ReactNode;
  numeric?: boolean;
  className?: string;
}) {
  return (
    <th
      scope="col"
      className={cx(
        'whitespace-nowrap px-4 py-2 text-label-sm uppercase text-on-surface-variant',
        numeric && 'text-right',
        className,
      )}
    >
      {children}
    </th>
  );
}

export function TBody({ children }: { children: ReactNode }) {
  return <tbody>{children}</tbody>;
}

export function TR({ children, ...props }: ComponentProps<'tr'>) {
  return (
    <tr
      {...props}
      className="border-b border-outline/10 last:border-0 hover:bg-surface-container-low"
    >
      {children}
    </tr>
  );
}

export function TD({
  children,
  numeric,
  className,
}: {
  children: ReactNode;
  numeric?: boolean;
  className?: string;
}) {
  return (
    <td
      className={cx(
        'px-4 py-4 text-body-md text-on-surface',
        // tabular-nums keeps columns of figures aligned as values change.
        numeric && 'text-right tabular-nums',
        className,
      )}
    >
      {children}
    </td>
  );
}

/**
 * Horizontal meter for "used against a ceiling".
 *
 * Turns warning-toned at 80% and error-toned once the ceiling is reached, so a
 * user who is about to be blocked is visible at a glance rather than requiring
 * the numbers to be read.
 */
export function Meter({
  value,
  max,
  label,
}: {
  value: number;
  max: number | null;
  label?: ReactNode;
}) {
  const unlimited = max == null || max <= 0;
  const ratio = unlimited ? 0 : Math.min(value / max, 1);
  const pct = Math.round(ratio * 100);

  const tone = unlimited
    ? 'bg-secondary'
    : ratio >= 1
      ? 'bg-error'
      : ratio >= 0.8
        ? 'bg-tertiary'
        : 'bg-primary';

  return (
    <div className="flex flex-col gap-1">
      {label ? (
        <div className="flex items-baseline justify-between gap-4">
          <span className="text-label-sm text-on-surface-variant">{label}</span>
          <span className="text-label-sm tabular-nums text-on-surface">
            {unlimited ? `${value} / ∞` : `${value} / ${max}`}
          </span>
        </div>
      ) : null}
      <div
        className="h-2 w-full overflow-hidden rounded-full bg-surface-container-high"
        role="progressbar"
        aria-valuenow={value}
        aria-valuemin={0}
        aria-valuemax={unlimited ? undefined : max}
      >
        <div
          className={cx('h-full rounded-full transition-all', tone)}
          style={{ width: unlimited ? '100%' : `${Math.max(pct, 2)}%` }}
        />
      </div>
    </div>
  );
}
