import { NextResponse, type NextRequest } from 'next/server';

import { SESSION_COOKIE } from '@/lib/auth/session';

/**
 * A UX shortcut, NOT a security boundary.
 *
 * (This is Next 16's `proxy` convention — the former `middleware.ts`.)
 *
 * It runs on the Edge runtime, where firebase-admin cannot run, so verifying a
 * session cookie here is impossible. All this does is bounce obviously-
 * signed-out visitors straight to /login instead of letting them round-trip
 * through a server component first.
 *
 * The real check is requireAdmin() in src/app/(dashboard)/layout.tsx and in
 * every /api/admin route handler. A forged or expired cookie sails past this
 * function and is rejected there.
 */
export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // The ONLY rule here, deliberately: bounce a visitor with no cookie at all.
  //
  // There is no matching "has a cookie, so send them to the dashboard" rule,
  // and there must not be. This function cannot verify a cookie — it only sees
  // that one exists. A stale or foreign cookie would then bounce /login -> /,
  // requireAdmin() would reject it and redirect / -> /login, and the two would
  // loop until the browser gave up with ERR_TOO_MANY_REDIRECTS. Presence is
  // not validity, so presence may not be used to grant navigation.
  if (!request.cookies.has(SESSION_COOKIE) && pathname !== '/login') {
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    url.search = '';
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  // Pages only — never `/api`.
  //
  // Redirecting an API request to /login answers a fetch() with a 307 to an
  // HTML page, so the caller parses a login form as JSON and reports something
  // unrelated to the real problem. Route handlers authorize themselves with
  // verifyAdminSession() and return a proper 401, which is both honest and
  // machine-readable — this matcher must stay out of their way.
  //
  // Excluding /api costs nothing in safety: the redirect below was never the
  // gate, only a shortcut for humans landing on a page while signed out.
  matcher: ['/((?!_next/static|_next/image|api/|favicon.ico|.*\\.).*)'],
};
