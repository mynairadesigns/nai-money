'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { Button } from '@/components/ui';
import { clientAuth } from '@/lib/firebase/client';

/**
 * Signs out on both sides: DELETE clears the httpOnly cookie and revokes the
 * refresh tokens server-side; the client SDK sign-out clears this tab's
 * Firebase state so a subsequent sign-in re-authenticates properly.
 */
export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function handleSignOut() {
    setBusy(true);
    try {
      await fetch('/api/auth/session', { method: 'DELETE' });
      await clientAuth().signOut().catch(() => {});
    } finally {
      router.replace('/login');
      router.refresh();
    }
  }

  return (
    <Button variant="text" onClick={handleSignOut} disabled={busy}>
      Sign out
    </Button>
  );
}
