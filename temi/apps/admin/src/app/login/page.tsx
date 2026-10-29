import type { Metadata } from 'next';

import { Card } from '@/components/ui';

import { LoginForm } from './login-form';

export const metadata: Metadata = { title: 'Sign in · Temi Finance Admin' };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ session?: string }>;
}) {
  // Set by requireAdmin() when a cookie was present but failed verification.
  const expired = (await searchParams).session === 'expired';

  return (
    <main className="mx-auto flex min-h-dvh max-w-md flex-col justify-center px-4 py-16">
      <p className="text-label-md uppercase text-on-surface-variant">
        Temi Finance
      </p>
      <h1 className="mt-2 text-headline-lg text-on-surface">Admin panel</h1>
      <p className="mt-2 text-body-md text-on-surface-variant">
        Restricted to accounts with the admin claim.
      </p>

      <Card className="mt-8">
        <LoginForm expired={expired} />
      </Card>
    </main>
  );
}
