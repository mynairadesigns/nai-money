import { DEMO_MODE_MESSAGE, isDemoMode } from '@/lib/config/demo-mode';
import { NextResponse } from 'next/server';

import { writeAuditEntry } from '@/lib/audit/log';
import { verifyAdminSession } from '@/lib/auth/require-admin';
import { refreshEntitlement, type EntitlementState } from '@/lib/data/billing';

// firebase-admin needs the Node runtime, and this must never be cached.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * Re-reads one user's entitlement from RevenueCat and rewrites the Firestore
 * mirror. The panel's only write into `users/{uid}`.
 *
 * WHY THIS EXISTS RATHER THAN CALLING THE FUNCTION. The `refreshEntitlement`
 * callable in apps/functions refreshes `request.auth.uid` and nothing else, so
 * an admin cannot use it on a user's behalf — which is exactly the support case
 * ("they paid, the app still says free"). The lookup and write therefore live
 * server-side here, mirroring that function's semantics field for field so the
 * two writers cannot disagree. See src/lib/data/billing.ts.
 *
 * SECURITY — route handlers do NOT nest inside the (dashboard) layout, so the
 * gate that protects every page does nothing for this endpoint. It authorizes
 * itself, first thing, before reading the body.
 *
 * `verifyAdminSession` rather than `requireAdmin`: the latter answers an
 * unauthorized caller with `redirect('/login')`, which becomes a 307 to an HTML
 * page — a fetch caller would then try to parse a login form as JSON. Same gate,
 * honest status code, and it returns the identity the audit entry needs.
 */
export async function POST(request: Request) {
  const admin = await verifyAdminSession();
  if (!admin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 401 });
  }

  // Server-side, for the same reason as the Remote Config endpoint: a demo
  // panel that still lets a visitor grant themselves admin is not a demo.
  if (isDemoMode()) {
    return NextResponse.json({ error: DEMO_MODE_MESSAGE }, { status: 403 });
  }

  const parsed = await parseBody(request);
  if ('error' in parsed) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }
  const { uid } = parsed;

  let result;
  try {
    result = await refreshEntitlement(uid);
  } catch (e) {
    // Firestore read/write failures land here. Whether the write committed is
    // genuinely unknown at this point, so say so rather than claim either.
    return NextResponse.json(
      {
        error: `The refresh failed against Firestore: ${e instanceof Error && e.message ? e.message : 'Unknown error.'} Re-check the user before assuming the mirror is unchanged.`,
      },
      { status: 502 },
    );
  }

  if (!result.ok) {
    // 503, not 500: an unset REVENUECAT_API_KEY is a deployment that has not
    // been finished, not a fault. The page hides the control when the key is
    // absent, so reaching this means the key was removed since page load.
    const status =
      result.failure.kind === 'not-configured'
        ? 503
        : result.failure.kind === 'no-such-user'
          ? 404
          : 502;
    return NextResponse.json({ error: result.message }, { status });
  }

  const audit = await writeAuditEntry({
    actorUid: admin.uid,
    actorEmail: admin.email,
    action: 'billing.refresh_entitlement',
    target: `users/${uid}`,
    before: auditPayload(result.before),
    after: auditPayload(result.after),
  });

  // The write already happened. Failing the request now would tell the operator
  // their change did not land — the opposite of the truth — and they would very
  // likely retry it. Report success WITH the logging failure, so the gap in the
  // audit trail is visible rather than swallowed.
  return NextResponse.json({
    ok: true,
    uid,
    before: result.before,
    after: result.after,
    changed: result.changed,
    auditError: audit.ok ? null : audit.error,
  });
}

/**
 * Audit entries are `{ key: string | null }`. The expiry is written as an ISO
 * string rather than epoch ms so the log is readable a year later without
 * anyone converting numbers by hand.
 */
function auditPayload(state: EntitlementState): Record<string, string | null> {
  return {
    premiumStatus: state.premiumStatus,
    premiumExpiry:
      state.premiumExpiryMs == null
        ? null
        : new Date(state.premiumExpiryMs).toISOString(),
  };
}

type ParsedBody = { uid: string } | { error: string };

/** Accepts `{ uid: string }`. */
async function parseBody(request: Request): Promise<ParsedBody> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return { error: 'Malformed request.' };
  }

  if (body == null || typeof body !== 'object') {
    return { error: 'Malformed request.' };
  }

  const { uid } = body as { uid?: unknown };
  if (typeof uid !== 'string') {
    return { error: 'A uid is required.' };
  }

  const trimmed = uid.trim();
  if (trimmed.length === 0) {
    return { error: 'A uid is required.' };
  }
  // A uid becomes a document path segment and a URL path segment, so reject the
  // characters that would change the meaning of either rather than let them
  // reach Firestore. Firebase uids are 28-char alphanumerics; this is generous
  // enough for a custom-auth deployment without admitting a traversal.
  if (trimmed.length > 128 || /[/\\?#%\s]/.test(trimmed)) {
    return { error: 'That does not look like a Firebase uid.' };
  }

  return { uid: trimmed };
}
