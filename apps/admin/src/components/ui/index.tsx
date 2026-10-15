import type { ComponentProps, ReactNode } from 'react';

/**
 * Shared UI primitives for the admin panel.
 *
 * These implement the design system's component rules so screens don't
 * re-invent them: elevation is tonal + ambient shadow (never borders), cards
 * are surface-container-lowest on a warm surface, buttons use the 8px radius,
 * chips are fully rounded, inputs are filled rather than outlined.
 *
 * HARD RULES, here and in every consumer:
 *   - No hex literals and no arbitrary values (`p-[13px]`, `text-[#abc]`).
 *     Colors come from the semantic tokens in app/globals.css.
 *   - Spacing uses Tailwind's NUMERIC scale, which globals.css pins to a 4px
 *     base so the design system's steps land on even numbers:
 *       4px→1  8px→2  16px→4  24px→6 (gutter)  32px→8  40px→10  64px→16
 *     Do not reintroduce named `--spacing-md`/`--spacing-lg` tokens: those
 *     names collide with Tailwind's own t-shirt scales and silently break
 *     unrelated utilities (`max-w-md` resolves through the spacing namespace).
 */

export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(' ');
}

/* -------------------------------------------------------------- Button --- */

type ButtonVariant = 'primary' | 'ghost' | 'text' | 'danger';

const BUTTON_BASE =
  'inline-flex items-center justify-center gap-2 rounded px-6 py-4 text-label-md ' +
  'transition-shadow transition-colors disabled:pointer-events-none disabled:opacity-50';

const BUTTON_VARIANTS: Record<ButtonVariant, string> = {
  primary: 'bg-primary text-on-primary hover:shadow-level-2',
  // "Ghost" — a 1px neutral border at 20% opacity, per the design system.
  ghost:
    'border border-outline/20 text-on-surface hover:bg-surface-container-high',
  text: 'text-primary hover:bg-surface-container',
  danger: 'bg-error text-on-error hover:shadow-level-2',
};

export function Button({
  variant = 'primary',
  className,
  ...props
}: ComponentProps<'button'> & { variant?: ButtonVariant }) {
  return (
    <button
      {...props}
      className={cx(BUTTON_BASE, BUTTON_VARIANTS[variant], className)}
    />
  );
}

/* ---------------------------------------------------------------- Card --- */

export function Card({
  className,
  children,
  ...props
}: ComponentProps<'section'>) {
  return (
    <section
      {...props}
      className={cx(
        'rounded-lg bg-surface-container-lowest p-6 shadow-level-1',
        className,
      )}
    >
      {children}
    </section>
  );
}

export function CardTitle({ children }: { children: ReactNode }) {
  return <h2 className="text-headline-md text-on-surface">{children}</h2>;
}

/* ----------------------------------------------------------------- Stat --- */

export function Stat({
  label,
  value,
  hint,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
}) {
  return (
    <Card className="flex flex-col gap-1">
      <p className="text-label-sm uppercase text-on-surface-variant">{label}</p>
      <p className="text-headline-lg text-on-surface tabular-nums">{value}</p>
      {hint ? (
        <p className="text-label-sm text-on-surface-variant">{hint}</p>
      ) : null}
    </Card>
  );
}

/* ---------------------------------------------------------------- Badge --- */

type BadgeTone = 'neutral' | 'positive' | 'warning' | 'critical';

const BADGE_TONES: Record<BadgeTone, string> = {
  neutral: 'bg-surface-container-high text-on-surface-variant',
  positive: 'bg-secondary-container text-on-secondary-container',
  warning: 'bg-tertiary-container text-on-tertiary-container',
  critical: 'bg-error-container text-on-error-container',
};

export function Badge({
  tone = 'neutral',
  children,
}: {
  tone?: BadgeTone;
  children: ReactNode;
}) {
  return (
    <span
      className={cx(
        'inline-flex items-center rounded-full px-4 py-1 text-label-sm',
        BADGE_TONES[tone],
      )}
    >
      {children}
    </span>
  );
}

/* ---------------------------------------------------------------- Input --- */

export function Input({ className, ...props }: ComponentProps<'input'>) {
  return (
    <input
      {...props}
      className={cx(
        // Filled, not outlined — a tertiary-toned fill with a 1.5px primary
        // focus ring, per the design system.
        //
        // `ring-[1.5px]` is the ONE sanctioned arbitrary value in the codebase:
        // the design system specifies 1.5px and Tailwind's ring scale only
        // offers 0/1/2/4/8. Rounding to `ring-2` would thicken every input
        // against the spec. Do not treat this as licence for other arbitrary
        // values — everything else comes from the tokens in globals.css.
        'w-full rounded bg-surface-container px-4 py-4 text-body-md text-on-surface',
        'placeholder:text-on-surface-variant',
        'outline-none focus:ring-[1.5px] focus:ring-primary',
        className,
      )}
    />
  );
}

/* --------------------------------------------------------------- Select --- */

/**
 * Filled select, visually identical to `Input`.
 *
 * The native arrow is removed with `appearance-none` and redrawn as a
 * positioned SVG. Browsers paint their own arrow flush against the right border
 * regardless of `padding-right`, which reads as a rendering bug next to the
 * generous padding everywhere else — and it cannot be nudged, because its
 * placement is not exposed to CSS. Drawing it ourselves also makes it obey the
 * colour tokens, so it stays legible in dark mode instead of staying whatever
 * the platform chose.
 *
 * `pr-10` reserves the arrow's column so a long option never slides under it.
 */
export function Select({
  className,
  children,
  ...props
}: ComponentProps<'select'>) {
  return (
    <div className="relative w-full">
      <select
        {...props}
        className={cx(
          'w-full appearance-none rounded bg-surface-container py-4 pl-4 pr-10',
          'text-body-md text-on-surface',
          'outline-none focus:ring-[1.5px] focus:ring-primary',
          className,
        )}
      >
        {children}
      </select>
      <svg
        aria-hidden
        viewBox="0 0 16 16"
        // pointer-events-none so the icon never swallows a click meant to open
        // the menu; -translate-y-1/2 centres it against any control height.
        className="pointer-events-none absolute right-4 top-1/2 h-4 w-4 -translate-y-1/2 text-on-surface-variant"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M4 6l4 4 4-4" />
      </svg>
    </div>
  );
}

/* ------------------------------------------------------------ EmptyState -- */

export function EmptyState({
  title,
  body,
}: {
  title: string;
  body?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-lg bg-surface-container-low px-6 py-16 text-center">
      <p className="text-body-lg text-on-surface">{title}</p>
      {body ? (
        <p className="max-w-prose text-body-md text-on-surface-variant">
          {body}
        </p>
      ) : null}
    </div>
  );
}
