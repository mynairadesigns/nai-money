import 'server-only';

import { FieldValue } from 'firebase-admin/firestore';

import { ADMIN_CLAIM } from '@/lib/auth/session';
import { adminAuth, adminDb } from '@/lib/firebase/admin';

import { toMillis } from './user-mapping';

/**
 * Who can sign in to this panel.
 *
 * THE MODEL: access is the Firebase Auth custom claim `admin: true`, and
 * nothing else. `adminUsers/{uid}` is a MIRROR, kept only so this module can
 * list admins without scanning the Auth tenant — it grants nothing. So every
 * read here joins the mirror against the LIVE claim rather than trusting it,
 * and every write sets the claim first and the mirror second.
 *
 * `firestore.rules` denies every client — admin and end user alike — all access
 * to `adminUsers`, so nothing but the Admin SDK can read or write it. That is
 * why this module needs no rules change.
 *
 * Semantics mirror scripts/grant-admin.mjs, which is how the FIRST admin comes
 * into existence (a panel you cannot sign in to cannot grant you access). Any
 * change to grant/revoke behaviour here belongs in that script too.
 */

const ADMIN_USERS = 'adminUsers';

/**
 * How long a mirror write is allowed before we give up on it.
 *
 * Lifted from scripts/grant-admin.mjs for the same reason: the Firestore SDK
 * retries indefinitely by design, so an unreachable Firestore would hang the
 * request forever AFTER the claim — the thing that actually grants access — had
 * already been written. A bounded wait turns that into a reportable warning
 * instead of a request that never answers.
 */
const MIRROR_TIMEOUT_MS = 10_000;

/* ------------------------------------------------------------------ pure -- */

/**
 * The two ways the mirror and the claim can disagree.
 *
 * Both are real and neither is visible anywhere else: Firebase's console shows
 * custom claims nowhere, and the mirror is just a Firestore collection. Left
 * unreported, `claim-missing` reads as "this person has access" when they
 * cannot sign in at all.
 */
export type AdminDrift = 'claim-missing' | 'auth-user-missing';

export const ADMIN_DRIFT_LABEL: Readonly<Record<AdminDrift, string>> = {
  'claim-missing': 'no claim',
  'auth-user-missing': 'account deleted',
};

export const ADMIN_DRIFT_EXPLANATION: Readonly<Record<AdminDrift, string>> = {
  'claim-missing':
    'Listed here, but the Auth account does not carry the admin claim — so this person cannot sign in. Either the claim was removed outside this panel, or a grant wrote the mirror and failed to write the claim. Granting again repairs it.',
  'auth-user-missing':
    'The Firebase Auth account this row points at no longer exists, so nothing grants access and the row is a leftover. Clearing it removes the mirror document.',
};

/** What an Auth lookup returned for one mirrored uid. */
export type AuthLookup =
  | {
      found: true;
      email: string | null;
      displayName: string | null;
      disabled: boolean;
      customClaims: Record<string, unknown> | undefined;
    }
  | { found: false };

export interface AdminRow {
  uid: string;
  email: string | null;
  displayName: string | null;
  /** True only when Auth carries `admin === true`. This is the real gate. */
  hasClaim: boolean;
  /** Auth account is disabled: it may hold the claim but still cannot sign in. */
  disabled: boolean;
  grantedAtMs: number | null;
  grantedBy: string | null;
  drift: AdminDrift | null;
}

/**
 * Strict `=== true`, never truthiness.
 *
 * requireAdmin() tests the decoded token exactly this way, so a claim of
 * `"true"` or `1` grants nothing. Loosening it here would make the list report
 * access that the gate does not actually give — the worst lie this page could
 * tell.
 */
export function hasAdminClaim(
  claims: Record<string, unknown> | null | undefined,
): boolean {
  return claims?.[ADMIN_CLAIM] === true;
}

/**
 * Joins one mirror document with its Auth lookup into a row.
 *
 * Pure and defensive: the mirror is written by two independent callers (this
 * panel and the CLI) and read long after, so a hand-edited or half-written
 * document must render as an honest row rather than crash the page.
 */
export function toAdminRow(
  uid: string,
  mirror: unknown,
  auth: AuthLookup,
): AdminRow {
  const doc = asRecord(mirror);
  const grantedAtMs = toMillis(doc.grantedAt);
  const grantedBy = asString(doc.grantedBy);

  if (!auth.found) {
    return {
      uid,
      // Auth is gone, so the mirror's stale copy is all that is left of who
      // this was — worth showing so the row is identifiable before it is
      // cleared.
      email: asString(doc.email),
      displayName: asString(doc.displayName),
      hasClaim: false,
      disabled: false,
      grantedAtMs,
      grantedBy,
      drift: 'auth-user-missing',
    };
  }

  const hasClaim = hasAdminClaim(auth.customClaims);

  return {
    uid,
    // Auth wins over the mirror: the mirror is written at grant time and never
    // updated, so it still shows the old address after an email change.
    email: auth.email ?? asString(doc.email),
    displayName: auth.displayName ?? asString(doc.displayName),
    hasClaim,
    disabled: auth.disabled,
    grantedAtMs,
    grantedBy,
    drift: hasClaim ? null : 'claim-missing',
  };
}

/**
 * Alphabetical by email, uid as the tiebreak.
 *
 * Deterministic on purpose — a list that reorders between requests looks like
 * activity. Rows without an email (a mirror pointing at a deleted account) sort
 * last rather than being compared against `null`.
 */
export function sortAdminRows(rows: readonly AdminRow[]): AdminRow[] {
  return [...rows].sort((a, b) => {
    if (a.email && b.email) {
      return a.email.localeCompare(b.email) || a.uid.localeCompare(b.uid);
    }
    if (a.email) return -1;
    if (b.email) return 1;
    return a.uid.localeCompare(b.uid);
  });
}

function asRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function errorMessage(e: unknown): string {
  return e instanceof Error && e.message ? e.message : 'Unknown error.';
}

function errorCode(e: unknown): string {
  return typeof (e as { code?: unknown })?.code === 'string'
    ? (e as { code: string }).code
    : '';
}

/* -------------------------------------------------------------- firestore -- */

export interface AdminList {
  rows: AdminRow[];
  /** The clock the page renders relative times against. */
  nowMs: number;
  /** Set when the list could not be built at all, so the page can say why. */
  error: string | null;
}

/**
 * Every mirrored admin, joined against the live claim.
 *
 * NEVER `listUsers()`. That pages through the ENTIRE Auth tenant — every end
 * user of the mobile app — to find a handful of admins, and its cost grows with
 * the product's success. The mirror exists precisely so this stays O(admins),
 * and the per-uid `getUser` lookups below are targeted reads, not a scan.
 *
 * KNOWN BLIND SPOT: a user granted the claim without a mirror document does not
 * appear here. They can sign in and are invisible to this list. Finding them is
 * exactly the tenant scan above, so the page states the limitation instead.
 */
export async function listAdmins(): Promise<AdminList> {
  const nowMs = Date.now();

  try {
    // No orderBy: Firestore silently EXCLUDES documents missing the ordering
    // field, so ordering by `grantedAt` would hide any row whose mirror write
    // was partial — precisely the rows this page exists to surface. Sorting in
    // code cannot drop anything, and needs no index either.
    const snap = await adminDb().collection(ADMIN_USERS).get();

    const rows = await Promise.all(
      snap.docs.map(async (doc) =>
        toAdminRow(doc.id, doc.data(), await lookupAuthUser(doc.id)),
      ),
    );

    return { rows: sortAdminRows(rows), nowMs, error: null };
  } catch (e) {
    // An empty collection reads as zero rows rather than throwing, so reaching
    // here means credentials, IAM, or the network.
    return { rows: [], nowMs, error: errorMessage(e) };
  }
}

async function lookupAuthUser(uid: string): Promise<AuthLookup> {
  try {
    const user = await adminAuth().getUser(uid);
    return {
      found: true,
      email: user.email ?? null,
      displayName: user.displayName ?? null,
      disabled: user.disabled,
      customClaims: user.customClaims,
    };
  } catch (e) {
    // A deleted account is data, not a failure — it is one of the two drift
    // states this module reports. Anything else (credentials, IAM) must keep
    // propagating so the whole list reports an error rather than quietly
    // showing every admin as claimless.
    if (errorCode(e) === 'auth/user-not-found') return { found: false };
    throw e;
  }
}

export type ClaimHolders =
  | { ok: true; uids: string[] }
  | { ok: false; error: string };

/**
 * The uids that ACTUALLY carry the claim right now — the input to the
 * last-admin safety rail.
 *
 * Derived from listAdmins rather than a cheaper `count()` on the mirror,
 * because a mirror row is not proof of access: counting rows would let a revoke
 * proceed on the strength of a listing that includes people who cannot sign in.
 *
 * A LOWER BOUND, deliberately. An admin granted outside this panel has no
 * mirror row and is invisible here, so the true number can only be higher —
 * meaning the rail errs towards refusing a revoke. That is the safe direction:
 * a needless refusal costs one CLI command, a wrong allowance locks every
 * operator out of the panel.
 */
export async function listUidsWithClaim(): Promise<ClaimHolders> {
  const { rows, error } = await listAdmins();
  if (error) return { ok: false, error };

  return { ok: true, uids: rows.filter((row) => row.hasClaim).map((r) => r.uid) };
}

/* ------------------------------------------------------------------ write -- */

export interface GrantSuccess {
  ok: true;
  uid: string;
  email: string | null;
  /** The claim was already set — nothing about access changed. */
  alreadyAdmin: boolean;
  /** Set when the claim landed but the mirror write did not. */
  mirrorError: string | null;
}

export type GrantFailure = {
  ok: false;
  kind: 'not-found' | 'invalid-email' | 'failed';
  message: string;
};

/**
 * Grants the admin claim to an EXISTING Auth account.
 *
 * There is no create path: the panel has no sign-up screen, and adding account
 * creation to a route reachable from a browser would turn one compromised admin
 * session into an account factory. `grant-admin <email> --create` from a
 * terminal is how a brand-new admin account is made.
 */
export async function grantAdmin(opts: {
  email: string;
  actorUid: string;
  actorEmail: string | null;
}): Promise<GrantSuccess | GrantFailure> {
  const auth = adminAuth();

  let user;
  try {
    user = await auth.getUserByEmail(opts.email);
  } catch (e) {
    const code = errorCode(e);
    if (code === 'auth/user-not-found') {
      return {
        ok: false,
        kind: 'not-found',
        message: `No Firebase Auth account with the email "${opts.email}".`,
      };
    }
    if (code === 'auth/invalid-email') {
      return { ok: false, kind: 'invalid-email', message: 'That is not a valid email address.' };
    }
    return { ok: false, kind: 'failed', message: errorMessage(e) };
  }

  const alreadyAdmin = hasAdminClaim(user.customClaims);

  try {
    // MERGE, never replace. setCustomUserClaims overwrites the entire claims
    // object, so spreading the existing ones is what stops a grant from
    // silently dropping some other claim the product adds later.
    await auth.setCustomUserClaims(user.uid, {
      ...(user.customClaims ?? {}),
      [ADMIN_CLAIM]: true,
    });
  } catch (e) {
    return { ok: false, kind: 'failed', message: errorMessage(e) };
  }

  // Best-effort relative to the claim: access is already granted at this point,
  // so a Firestore failure must not be reported as a failed grant. The caller
  // surfaces `mirrorError` alongside the success instead.
  const mirrorError = await withMirrorTimeout(
    adminDb()
      .collection(ADMIN_USERS)
      .doc(user.uid)
      .set(
        {
          uid: user.uid,
          email: user.email ?? null,
          displayName: user.displayName ?? null,
          // Server timestamp, not the container's clock — the list orders and
          // ages these, and a skewed instance would misreport both.
          grantedAt: FieldValue.serverTimestamp(),
          // The CLI writes the literal 'cli' here; an email or uid identifies a
          // panel grant, so the two are always distinguishable after the fact.
          grantedBy: opts.actorEmail ?? opts.actorUid,
        },
        { merge: true },
      ),
  );

  return {
    ok: true,
    uid: user.uid,
    email: user.email ?? null,
    alreadyAdmin,
    mirrorError,
  };
}

export interface RevokeSuccess {
  ok: true;
  uid: string;
  email: string | null;
  /** The Auth account was already gone; only the orphaned mirror was cleared. */
  orphan: boolean;
  /** Set when the claim was removed but the mirror document survived. */
  mirrorError: string | null;
  /** Set when the claim was removed but existing sessions could not be ended. */
  sessionError: string | null;
}

export type RevokeFailure = { ok: false; kind: 'failed'; message: string };

/**
 * Removes the admin claim and ends the account's sessions immediately.
 *
 * The caller MUST apply the last-admin and self-revocation rails before calling
 * this — see the route handler. Nothing in here refuses anything.
 */
export async function revokeAdmin(
  uid: string,
): Promise<RevokeSuccess | RevokeFailure> {
  const auth = adminAuth();

  let user;
  try {
    user = await auth.getUser(uid);
  } catch (e) {
    if (errorCode(e) !== 'auth/user-not-found') {
      return { ok: false, kind: 'failed', message: errorMessage(e) };
    }

    // The account is gone, so there is no claim to remove and no session to
    // end. Clearing the orphaned mirror row is the only work left — and the
    // only way to get that row off the page.
    return {
      ok: true,
      uid,
      email: null,
      orphan: true,
      mirrorError: await withMirrorTimeout(deleteMirror(uid)),
      sessionError: null,
    };
  }

  const claims = { ...(user.customClaims ?? {}) };
  delete claims[ADMIN_CLAIM];

  try {
    // Same merge discipline as the grant, in reverse: delete OUR key and write
    // the rest back, rather than writing an empty object over everything.
    await auth.setCustomUserClaims(user.uid, claims);
  } catch (e) {
    return { ok: false, kind: 'failed', message: errorMessage(e) };
  }

  const mirrorError = await withMirrorTimeout(deleteMirror(user.uid));

  // Removing the claim ALONE does not end an existing session: the session
  // cookie carries the claims that were baked into it when it was minted, and
  // it is valid for up to 14 days. Revoking the refresh tokens moves the
  // account's `validSince` to now, which requireAdmin's `checkRevoked: true`
  // honours on the very next request. This line is what makes a revoke
  // immediate rather than eventual.
  let sessionError: string | null = null;
  try {
    await auth.revokeRefreshTokens(user.uid);
  } catch (e) {
    sessionError = errorMessage(e);
  }

  return {
    ok: true,
    uid: user.uid,
    email: user.email ?? null,
    orphan: false,
    mirrorError,
    sessionError,
  };
}

function deleteMirror(uid: string): Promise<unknown> {
  return adminDb().collection(ADMIN_USERS).doc(uid).delete();
}

/** Runs a mirror write under {@link MIRROR_TIMEOUT_MS}; returns its failure. */
async function withMirrorTimeout(work: Promise<unknown>): Promise<string | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;

  try {
    await Promise.race([
      work,
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`timed out after ${MIRROR_TIMEOUT_MS / 1000}s`)),
          MIRROR_TIMEOUT_MS,
        );
      }),
    ]);
    return null;
  } catch (e) {
    return errorMessage(e);
  } finally {
    clearTimeout(timer);
  }
}
