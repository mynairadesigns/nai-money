import type { ReactNode } from 'react';

import { cx } from '@/components/ui';

/**
 * A labelled value inside a <dl>. Support screens are mostly this shape, so it
 * lives here rather than being re-spelled in every card.
 */
export function Field({
  label,
  children,
  className,
}: {
  label: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cx('flex flex-col gap-1', className)}>
      <dt className="text-label-sm uppercase text-on-surface-variant">
        {label}
      </dt>
      <dd className="text-body-md text-on-surface">{children}</dd>
    </div>
  );
}
