import 'server-only';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

import { adminAuth } from '@/lib/firebase/admin';
import { CREDENTIAL_HELP, isCredentialError } from '@/lib/firebase/errors';

import { ADMIN_CLAIM, SESSION_COOKIE, type AdminIdentity } from './session';

/**
 * THE authorization gate. Every protected surface funnels through here — the
 * (dashboard) layout for pages, and each /api/admin route handler for
 * mutations. Nothing else in the codebase parses the session cookie.
 *
 * Two-part check, both required:
 *   1. the session cookie verifies (and has not been revoked), and
 *   2. the decoded token carries `admin: true`.
 *
 * A signed-in Homa Finance *end user* has a perfectly valid Firebase session and
 * no admin claim — step 2 is what keeps them out.
 */
export async function verifyAdminSession(): Promise<AdminIdentity | null> {
  const cookie = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!cookie) return null;

  try {
    // checkRevoked: true costs a lookup but means revoking a compromised
    // admin's sessions takes effect immediately rather than in up to 14 days.
    const decoded = await adminAuth().verifySessionCookie(cookie, true);
    if (decoded[ADMIN_CLAIM] !== true) return null;

    return {
      uid: decoded.uid,
      email: decoded.email ?? null,
      name: (decoded.name as string | undefined) ?? null,
      picture: (decoded.picture as string | undefined) ?? null,
    };
  } catch (e) {
    // A credential failure means the SERVER is broken, not the caller. It
    // still denies access — but silently returning null would make a
    // misconfigured deployment look like an endless "please sign in", so
    // leave a breadcrumb in the logs. Never leak the reason to the client.
    if (isCredentialError(e)) {
      console.error('[admin] session verification: ' + CREDENTIAL_HELP, e);
    }
    // Expired, malformed, revoked, or signed by another project all land here
    // too, and all mean "not authenticated".
    return null;
  }
}

/**
 * Server-component variant: redirects to /login instead of returning null.
 * Used by the (dashboard) layout, so no page nested under it can render for an
 * unauthorized caller even if the page itself forgets to check.
 *
 * When the caller HAD a cookie and it failed verification — expired, revoked,
 * or minted by a different Firebase project — say so in the query string. A
 * silent bounce to a blank login form looks identical to "the app is broken",
 * which is precisely how a dead cookie presents itself.
 */
export async function requireAdmin(): Promise<AdminIdentity> {
  const identity = await verifyAdminSession();
  if (identity) return identity;

  const hadCookie = (await cookies()).get(SESSION_COOKIE) !== undefined;
  redirect(hadCookie ? '/login?session=expired' : '/login');
}
