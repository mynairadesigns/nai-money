import Link from 'next/link';

import { requireAdmin } from '@/lib/auth/require-admin';

import { SignOutButton } from './sign-out-button';
import { ThemeToggle } from './theme-toggle';

// firebase-admin needs the Node runtime, and the gate below must run on every
// request rather than being cached.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * THE security gate for the whole panel.
 *
 * Because App Router nests layouts, every page under (dashboard) renders as a
 * child of this component — so requireAdmin() runs before any of them, and a
 * new page added later is protected without its author having to remember
 * anything. Route handlers do NOT nest this way: each /api/admin route must
 * call requireAdmin() itself.
 */
const NAV = [
  { href: '/', label: 'Dashboard' },
  { href: '/users', label: 'Users' },
  { href: '/ai-usage', label: 'AI usage' },
  { href: '/remote-config', label: 'Remote Config' },
  { href: '/billing', label: 'Billing' },
  { href: '/system', label: 'System' },
  { href: '/audit', label: 'Audit log' },
  { href: '/access', label: 'Access' },
] as const;

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const admin = await requireAdmin();

  return (
    <div className="min-h-dvh">
      <header className="border-b border-outline/10 bg-surface-container-low">
        <div className="mx-auto flex max-w-page flex-wrap items-center gap-4 px-4 py-4 md:px-10">
          <Link href="/" className="text-label-md uppercase text-primary">
            Moneymind admin
          </Link>

          <nav className="flex flex-1 flex-wrap items-center gap-1">
            {NAV.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="rounded-full px-4 py-1 text-label-sm text-on-surface-variant hover:bg-surface-container-high hover:text-on-surface"
              >
                {item.label}
              </Link>
            ))}
          </nav>

          <div className="flex items-center gap-2">
            <span className="text-label-sm text-on-surface-variant">
              {admin.email ?? admin.uid}
            </span>
            <ThemeToggle />
            <SignOutButton />
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-page px-4 py-8 md:px-10">{children}</div>
    </div>
  );
}
