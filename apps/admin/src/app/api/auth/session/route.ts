import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import {
  ADMIN_CLAIM,
  SESSION_COOKIE,
  SESSION_MAX_AGE_MS,
  sessionCookieOptions,
} from '@/lib/auth/session';
import { adminAuth } from '@/lib/firebase/admin';
import { CREDENTIAL_HELP, isCredentialError } from '@/lib/firebase/errors';

// firebase-admin needs the Node runtime; it cannot run on Edge.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * Exchanges a freshly-minted Firebase ID token for an httpOnly session cookie.
 *
 * The admin claim is asserted HERE, at issue time, so a non-admin never
 * receives a cookie at all. It is asserted again on every request in
 * requireAdmin() — issue-time alone would let a revoked admin keep browsing
 * until the cookie expired.
 */
export async function POST(request: Request) {
  let idToken: unknown;
  try {
    ({ idToken } = await request.json());
  } catch {
    return NextResponse.json({ error: 'Malformed request' }, { status: 400 });
  }

  if (typeof idToken !== 'string' || idToken.length === 0) {
    return NextResponse.json({ error: 'Missing idToken' }, { status: 400 });
  }

  try {
    const decoded = await adminAuth().verifyIdToken(idToken, true);

    if (decoded[ADMIN_CLAIM] !== true) {
      // Deliberately identical shape to a bad token: don't help an attacker
      // distinguish "not an admin" from "invalid credentials".
      return NextResponse.json(
        { error: 'This account does not have admin access.' },
        { status: 403 },
      );
    }

    // Firebase refuses to mint a session cookie from an ID token older than
    // 5 minutes, which is what keeps this endpoint from being replayable.
    const sessionCookie = await adminAuth().createSessionCookie(idToken, {
      expiresIn: SESSION_MAX_AGE_MS,
    });

    (await cookies()).set({
      ...sessionCookieOptions(SESSION_MAX_AGE_MS),
      value: sessionCookie,
    });

    return NextResponse.json({ ok: true });
  } catch (e) {
    // A server that cannot verify ANY token is a deployment fault, not a bad
    // sign-in. Reporting it as 401 sends the operator off debugging their own
    // account while the real cause — missing credentials — stays invisible.
    if (isCredentialError(e)) {
      console.error('[admin] session: ' + CREDENTIAL_HELP, e);
      return NextResponse.json(
        { error: 'Server is not configured to verify sign-ins. ' + CREDENTIAL_HELP },
        { status: 503 },
      );
    }
    return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 });
  }
}

/** Signs out: clears the cookie and revokes the underlying refresh tokens. */
export async function DELETE() {
  const jar = await cookies();
  const cookie = jar.get(SESSION_COOKIE)?.value;

  if (cookie) {
    try {
      const decoded = await adminAuth().verifySessionCookie(cookie, false);
      await adminAuth().revokeRefreshTokens(decoded.sub);
    } catch {
      // Already invalid — clearing the cookie is still the right outcome.
    }
  }

  jar.set({ ...sessionCookieOptions(0), value: '' });
  return NextResponse.json({ ok: true });
}
