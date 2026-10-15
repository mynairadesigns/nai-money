'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { signInWithEmailAndPassword } from 'firebase/auth';

import { Button, Input } from '@/components/ui';
import { clientAuth, isFirebaseConfigured } from '@/lib/firebase/client';

/**
 * The only place the browser talks to Firebase Auth.
 *
 * Flow: sign in → get an ID token → hand it to POST /api/auth/session, which
 * verifies the admin claim and sets an httpOnly cookie. The client never sees
 * or stores the session cookie, and never touches Firestore.
 *
 * Email/password is the only sign-in method. Since the panel has no sign-up
 * screen either, every admin account is created from the CLI:
 * `pnpm -F admin grant-admin <email> --create`.
 *
 * Note the sign-out on rejection: an operator whose account lacks the admin
 * claim would otherwise stay signed in to Firebase in this tab, so a retry
 * would silently reuse the same rejected identity.
 */
export function LoginForm({ expired = false }: { expired?: boolean }) {
  const router = useRouter();
  const configured = isFirebaseConfigured();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(
    expired ? 'Your session ended. Please sign in again.' : null,
  );
  const [busy, setBusy] = useState(false);

  async function establishSession(idToken: string) {
    const res = await fetch('/api/auth/session', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ idToken }),
    });

    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      await clientAuth().signOut();
      throw new Error(body.error ?? 'Sign-in failed.');
    }

    // Server components must re-render against the new cookie.
    router.replace('/');
    router.refresh();
  }

  async function handleEmail(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const cred = await signInWithEmailAndPassword(
        clientAuth(),
        email,
        password,
      );
      await establishSession(await cred.user.getIdToken());
    } catch (e) {
      setError(messageFor(e));
      setBusy(false);
    }
  }

  if (!configured) {
    return (
      <p className="text-body-md text-on-surface-variant">
        Firebase is not configured. Copy <code>.env.example</code> to{' '}
        <code>.env.local</code> and fill in your web app config, then reload.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <form onSubmit={handleEmail} className="flex flex-col gap-4">
        <Input
          type="email"
          autoComplete="username"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <Input
          type="password"
          autoComplete="current-password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        <Button type="submit" variant="primary" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>

      {error ? (
        <p role="alert" className="text-label-md text-error">
          {error}
        </p>
      ) : null}
    </div>
  );
}

function messageFor(e: unknown): string {
  if (e instanceof Error && e.message) {
    // Firebase error codes are not useful to an operator; the server's own
    // messages (e.g. "This account does not have admin access.") are.
    if (e.message.startsWith('Firebase:')) return 'Sign-in failed.';
    return e.message;
  }
  return 'Sign-in failed.';
}
