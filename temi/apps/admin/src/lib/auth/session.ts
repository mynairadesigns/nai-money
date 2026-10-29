import 'server-only';

/**
 * Session cookie constants and claim shape.
 *
 * `__session` is not an arbitrary name: it is the only cookie Firebase
 * Hosting's CDN forwards to the origin. Using it keeps behaviour identical
 * across App Hosting and the Cloud Run fallback.
 */
export const SESSION_COOKIE = '__session';

/** Firebase caps session cookies at 14 days. */
export const SESSION_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;

/** The custom claim that grants access. Set by scripts/grant-admin.mjs. */
export const ADMIN_CLAIM = 'admin';

export interface AdminIdentity {
  uid: string;
  email: string | null;
  name: string | null;
  picture: string | null;
}

export function sessionCookieOptions(maxAgeMs: number) {
  return {
    name: SESSION_COOKIE,
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax' as const,
    path: '/',
    maxAge: Math.floor(maxAgeMs / 1000),
  };
}
