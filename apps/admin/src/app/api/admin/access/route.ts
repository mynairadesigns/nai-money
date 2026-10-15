import { DEMO_MODE_MESSAGE, isDemoMode } from '@/lib/config/demo-mode';
import { NextResponse } from 'next/server';

import { writeAuditEntry } from '@/lib/audit/log';
import { verifyAdminSession } from '@/lib/auth/require-admin';
import { ADMIN_CLAIM } from '@/lib/auth/session';
import {
  grantAdmin,
  listUidsWithClaim,
  revokeAdmin,
  type RevokeSuccess,
} from '@/lib/data/admins';

// firebase-admin needs the Node runtime, and this must never be cached.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * The one write path into panel access.
 *
 * SECURITY — route handlers do NOT nest inside the (dashboard) layout, so the
 * gate that protects every page does nothing for this endpoint. It authorizes
 * itself, first thing, before reading the body.
 *
 * `verifyAdminSession` rather than `requireAdmin`: the latter answers an
 * unauthorized caller with `redirect('/login')`, which becomes a 307 to an HTML
 * page — a fetch caller would then try to parse a login form as JSON and report
 * something unrelated to the real problem. Same gate, honest status code, and
 * it returns the identity the audit entry and the self-revocation rail need.
 *
 * This is the most dangerous endpoint in the panel: it decides who can reach
 * every other one. Hence the two rails below, both applied HERE rather than in
 * the data layer, so no future caller can skip them by accident.
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

  return parsed.action === 'grant'
    ? handleGrant(parsed.email, admin)
    : handleRevoke(parsed.uid, parsed.confirmSelf, admin);
}

type Actor = { uid: string; email: string | null };

/* ------------------------------------------------------------------ grant -- */

async function handleGrant(email: string, admin: Actor) {
  const result = await grantAdmin({
    email,
    actorUid: admin.uid,
    actorEmail: admin.email,
  });

  if (!result.ok) {
    if (result.kind === 'not-found') {
      // The single most common failure, and the one where a generic error would
      // send the operator hunting for a typo in an address that is fine. The
      // panel deliberately cannot create accounts (see grantAdmin) — say where
      // that happens instead.
      return NextResponse.json(
        {
          error: result.message,
          hint:
            'This page grants access to an account that already exists; it cannot create one. ' +
            `Run \`pnpm -F admin grant-admin ${email} --create\` from a terminal to create the account and grant it in one step.`,
        },
        { status: 404 },
      );
    }
    return NextResponse.json(
      { error: result.message },
      { status: result.kind === 'invalid-email' ? 400 : 502 },
    );
  }

  const audit = await auditAccessChange({
    action: 'admin.grant',
    admin,
    uid: result.uid,
    email: result.email,
    hadClaim: result.alreadyAdmin,
    hasClaim: true,
  });

  return NextResponse.json({
    ok: true,
    action: 'grant',
    uid: result.uid,
    email: result.email,
    alreadyAdmin: result.alreadyAdmin,
    mirrorError: result.mirrorError,
    auditError: audit,
    message: result.alreadyAdmin
      ? 'That account already had admin access — nothing changed.'
      : 'Admin access granted. It takes effect the next time they sign in.',
  });
}

/* ----------------------------------------------------------------- revoke -- */

async function handleRevoke(
  uid: string,
  confirmSelf: boolean,
  admin: Actor,
) {
  /*
   * RAIL 1 — never leave zero admins.
   *
   * Counted from the accounts that actually carry the claim, not from mirror
   * rows: a listing full of people who cannot sign in must not authorise the
   * last real admin's removal. Locking everyone out of the panel is recoverable
   * only from a terminal with project credentials.
   */
  const holders = await listUidsWithClaim();

  if (!holders.ok) {
    // Fail CLOSED. If the check itself is broken we cannot know whether this is
    // the last admin, and guessing "probably not" is how everyone gets locked
    // out. Refusing costs one CLI command.
    return NextResponse.json(
      {
        error: `Could not verify how many admins remain, so nothing was revoked. ${holders.error}`,
        hint:
          'This check reads the adminUsers mirror through the Admin SDK. Refusing is deliberate: an unverifiable revoke could take the last admin with it, and only `pnpm -F admin grant-admin <email>` from a terminal could undo that.',
      },
      { status: 503 },
    );
  }

  if (holders.uids.includes(uid) && holders.uids.length === 1) {
    return NextResponse.json(
      {
        error: 'This is the only account with admin access, so it cannot be revoked here.',
        hint:
          'Grant a second admin first, then revoke this one. If you genuinely want no admins, run `pnpm -F admin grant-admin <email> --revoke` from a terminal — that path has project credentials and can undo itself.',
      },
      { status: 409 },
    );
  }

  /*
   * RAIL 2 — self-revocation is refused by default.
   *
   * It is almost always a misclick, and it takes effect mid-action: the
   * refresh-token revocation kills the caller's own session before the response
   * is even rendered. Allowed only with an explicit `confirmSelf`, which the UI
   * only sends from a separate confirmation step.
   *
   * Checked AFTER rail 1 so a last-admin self-revoke reports the harder stop —
   * that one cannot be confirmed away.
   */
  if (uid === admin.uid && !confirmSelf) {
    return NextResponse.json(
      {
        error: 'Refusing to revoke your own access without an explicit confirmation.',
        hint:
          'Revoking yourself signs you out immediately and you will not be able to sign back in. Confirm from the button on your own row if that is really what you want.',
        requiresConfirmSelf: true,
      },
      { status: 409 },
    );
  }

  const result = await revokeAdmin(uid);
  if (!result.ok) {
    return NextResponse.json({ error: result.message }, { status: 502 });
  }

  const audit = await auditAccessChange({
    action: 'admin.revoke',
    admin,
    uid: result.uid,
    email: result.email,
    // An orphan row never had an account behind it, so it never had a claim.
    hadClaim: !result.orphan,
    hasClaim: false,
  });

  return NextResponse.json({
    ok: true,
    action: 'revoke',
    uid: result.uid,
    email: result.email,
    orphan: result.orphan,
    self: uid === admin.uid,
    mirrorError: result.mirrorError,
    sessionError: result.sessionError,
    auditError: audit,
    message: revokeMessage(result, uid === admin.uid),
  });
}

/**
 * Says what actually happened, not what was intended.
 *
 * "Access ended immediately" is only true when the refresh-token revocation
 * landed. When it did not, the claim is gone but a live session cookie keeps
 * working for up to 14 days — so the headline must not claim otherwise, or it
 * would contradict the warning shown right beneath it.
 */
function revokeMessage(result: RevokeSuccess, isSelf: boolean): string {
  if (result.orphan) {
    return 'That Firebase Auth account no longer exists, so there was no access to revoke — the leftover row has been cleared.';
  }
  if (result.sessionError) {
    return isSelf
      ? 'Your own admin claim has been removed, but your current session could not be revoked.'
      : 'Their admin claim has been removed, but their existing sessions could not be revoked.';
  }
  return isSelf
    ? 'Your own admin access has been revoked, and your session with it — the next request will send you to the sign-in page.'
    : 'Admin access revoked. Their sessions were revoked too, so access ended immediately.';
}

/* ------------------------------------------------------------------ audit -- */

/**
 * Records the change, and reports a logging failure WITHOUT failing the call.
 *
 * The claim has already been written by the time this runs. Answering with an
 * error now would tell the operator their change did not land — the opposite of
 * the truth — and they would very likely retry it. Returning the failure
 * alongside the success makes the gap in the trail visible instead.
 */
async function auditAccessChange(opts: {
  action: 'admin.grant' | 'admin.revoke';
  admin: Actor;
  uid: string;
  email: string | null;
  /** Whether the claim was set BEFORE this call — not whether it was asked for. */
  hadClaim: boolean;
  hasClaim: boolean;
}): Promise<string | null> {
  // The email rides on whichever side HOLDS the claim, so the log reads as
  // "a@example.com gained/lost the claim" with no join against a uid needed.
  // The audit page renders an absent key as "not set".
  //
  // `hadClaim` is the account's real prior state rather than the inverse of the
  // action: re-granting to somebody who was already an admin must record
  // true → true, not a change that never happened.
  const side = (holds: boolean): Record<string, string | null> =>
    holds ? { [ADMIN_CLAIM]: 'true', email: opts.email } : { [ADMIN_CLAIM]: null, email: null };

  const audit = await writeAuditEntry({
    actorUid: opts.admin.uid,
    actorEmail: opts.admin.email,
    action: opts.action,
    target: `adminUsers/${opts.uid}`,
    before: side(opts.hadClaim),
    after: side(opts.hasClaim),
  });

  return audit.ok ? null : audit.error;
}

/* ------------------------------------------------------------------ parse -- */

type ParsedBody =
  | { action: 'grant'; email: string }
  | { action: 'revoke'; uid: string; confirmSelf: boolean }
  | { error: string };

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

  const { action, email, uid, confirmSelf } = body as Record<string, unknown>;

  if (action === 'grant') {
    if (typeof email !== 'string' || email.trim().length === 0) {
      return { error: 'Enter the email address of an existing account.' };
    }
    // Lowercased to match how the mobile app stores addresses at sign-up, the
    // same normalisation findUserByEmail applies on the users module.
    return { action: 'grant', email: email.trim().toLowerCase() };
  }

  if (action === 'revoke') {
    if (typeof uid !== 'string' || uid.trim().length === 0) {
      return { error: 'Missing uid.' };
    }
    // Anything other than a literal `true` counts as unconfirmed: a truthy
    // string arriving from a bug must not stand in for the operator's intent.
    return { action: 'revoke', uid: uid.trim(), confirmSelf: confirmSelf === true };
  }

  return { error: 'Unknown action — expected "grant" or "revoke".' };
}
