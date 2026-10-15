import { NextResponse } from 'next/server';

import { writeAuditEntry } from '@/lib/audit/log';
import { DEMO_MODE_MESSAGE, isDemoMode } from '@/lib/config/demo-mode';
import { verifyAdminSession } from '@/lib/auth/require-admin';
import { changesToAuditPayload } from '@/lib/remote-config/diff';
import { isManifestKey, validateRcValue } from '@/lib/remote-config/manifest';
import { publishValues } from '@/lib/remote-config/template';

// firebase-admin needs the Node runtime, and this must never be cached.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * The one write path into Remote Config.
 *
 * SECURITY — route handlers do NOT nest inside the (dashboard) layout, so the
 * gate that protects every page does nothing for this endpoint. It authorizes
 * itself, first thing, before reading the body.
 *
 * `verifyAdminSession` rather than `requireAdmin`: the latter answers an
 * unauthorized caller with `redirect('/login')`, which becomes a 307 to an HTML
 * page. A fetch caller would then try to parse a login form as JSON and report
 * something unrelated to the real problem. Same gate, honest status code — and
 * it returns the identity the audit entry needs.
 *
 * Validation is re-run here against the manifest even though the editor already
 * validated: the browser is not a trusted validator, and an unknown key must
 * never reach the template.
 */
export async function POST(request: Request) {
  const admin = await verifyAdminSession();
  if (!admin) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 401 });
  }

  // Checked here, not just in the editor: the endpoint is reachable with curl
  // regardless of what the UI renders, so the refusal has to live server-side.
  if (isDemoMode()) {
    return NextResponse.json({ error: DEMO_MODE_MESSAGE }, { status: 403 });
  }

  const parsed = await parseBody(request);
  if ('error' in parsed) {
    return NextResponse.json({ error: parsed.error }, { status: 400 });
  }
  const { expectedEtag, values } = parsed;

  if (values.size === 0) {
    return NextResponse.json(
      { error: 'No changes were submitted.' },
      { status: 400 },
    );
  }

  const fieldErrors: Record<string, string> = {};
  for (const [key, value] of values) {
    // Unknown keys are rejected outright rather than published as new
    // parameters — a typo would otherwise become a permanent template entry
    // that nothing reads.
    if (!isManifestKey(key)) {
      fieldErrors[key] = `Unknown key "${key}".`;
      continue;
    }
    const error = validateRcValue(key, value);
    if (error) fieldErrors[key] = error;
  }

  if (Object.keys(fieldErrors).length > 0) {
    return NextResponse.json(
      { error: 'Some values were rejected.', fieldErrors },
      { status: 400 },
    );
  }

  const result = await publishValues({ expectedEtag, values });

  if (!result.ok) {
    // A stale template is the operator's cue to reload, not a server fault —
    // 409 says "your copy is out of date" rather than "this is broken".
    const status =
      result.failure.kind === 'stale'
        ? 409
        : result.failure.kind === 'rejected'
          ? 400
          : 502;
    return NextResponse.json({ error: result.message }, { status });
  }

  // Submitted values that already matched the template. Nothing was published,
  // so there is nothing to audit — saying so beats a misleading "published".
  if (result.changes.length === 0) {
    return NextResponse.json({
      ok: true,
      published: false,
      changes: [],
      versionNumber: result.versionNumber,
      auditError: null,
      message: 'Those values already match the live template. Nothing to publish.',
    });
  }

  const { before, after } = changesToAuditPayload(result.changes);
  const audit = await writeAuditEntry({
    actorUid: admin.uid,
    actorEmail: admin.email,
    action: 'remote_config.publish',
    target: result.versionNumber
      ? `remoteConfig/versions/${result.versionNumber}`
      : 'remoteConfig',
    before,
    after,
  });

  // The publish already happened. Failing the request now would tell the
  // operator their change did not land — the opposite of the truth — and they
  // would very likely retry it. Report success WITH the logging failure, so
  // the gap in the audit trail is visible rather than swallowed.
  return NextResponse.json({
    ok: true,
    published: true,
    changes: result.changes,
    versionNumber: result.versionNumber,
    auditError: audit.ok ? null : audit.error,
  });
}

type ParsedBody =
  | { expectedEtag: string | null; values: Map<string, string> }
  | { error: string };

/**
 * Accepts `{ expectedEtag?: string | null, values: { [key]: string } }`.
 *
 * Every value must already be a string. Coercing a number or boolean here would
 * hide a client bug and could publish `"[object Object]"` into production
 * config; Remote Config stores strings, so the caller sends strings.
 */
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

  const { expectedEtag, values } = body as {
    expectedEtag?: unknown;
    values?: unknown;
  };

  if (
    expectedEtag != null &&
    (typeof expectedEtag !== 'string' || expectedEtag.length === 0)
  ) {
    return { error: 'Malformed expectedEtag.' };
  }

  if (values == null || typeof values !== 'object' || Array.isArray(values)) {
    return { error: 'Missing values.' };
  }

  const out = new Map<string, string>();
  for (const [key, value] of Object.entries(values as Record<string, unknown>)) {
    if (typeof value !== 'string') {
      return { error: `Value for "${key}" must be a string.` };
    }
    out.set(key, value);
  }

  return { expectedEtag: (expectedEtag as string | undefined) ?? null, values: out };
}
