'use client';

import { Button } from '@/components/ui';

const STORAGE_KEY = 'mm-admin-theme';

/**
 * Pins light or dark explicitly rather than following prefers-color-scheme, so
 * an operator on a dark OS can still read the panel in light mode.
 *
 * Deliberately stateless: the current theme lives on <html> (applied pre-paint
 * by the inline script in the root layout), and this reads it at click time.
 * Mirroring it into React state would mean either a setState-in-effect or an
 * SSR/client hydration mismatch on the label, for no benefit.
 */
export function ThemeToggle() {
  function toggle() {
    const root = document.documentElement;
    const next = !root.classList.contains('dark');
    root.classList.toggle('dark', next);
    try {
      localStorage.setItem(STORAGE_KEY, next ? 'dark' : 'light');
    } catch {
      // Private browsing with storage disabled — the toggle still works for
      // this page view, it just won't persist.
    }
  }

  return (
    <Button variant="text" onClick={toggle} aria-label="Toggle light and dark theme">
      Theme
    </Button>
  );
}
