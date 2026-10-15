import type { ReactNode } from 'react';

/**
 * Inline literal — a field name, a document path, a shell command.
 *
 * `font-sans` is not redundant: Tailwind's preflight points `<code>` at the
 * mono stack, and Sora is the only family this design system allows. The tinted
 * fill carries the "this is a literal" signal instead.
 */
export function Code({ children }: { children: ReactNode }) {
  return (
    <code className="rounded-sm bg-surface-container px-1 font-sans text-on-surface">
      {children}
    </code>
  );
}
