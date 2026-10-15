import 'server-only';

import {
  FieldValue,
  type QueryDocumentSnapshot,
} from 'firebase-admin/firestore';

import { toMillis } from '@/lib/data/user-mapping';
import { adminDb } from '@/lib/firebase/admin';

/**
 * The panel's audit trail: who changed what, from what to what, and when.
 *
 * Storage is `adminAuditLog/{autoId}`, which `firestore.rules` denies to every
 * client — admin and end user alike. Nothing but the Admin SDK can read or
 * write it, which is why the rules need no change to support this and why the
 * /audit page reads through the server rather than a client listener.
 *
 * Entries are append-only by convention: nothing here updates or deletes.
 */

const COLLECTION = 'adminAuditLog';

/**
 * Actions this panel records. A union rather than a free string so a typo
 * cannot fragment the log into two actions that look alike in a listing.
 */
export type AuditAction =
  | 'remote_config.publish'
  | 'billing.refresh_entitlement'
  | 'admin.grant'
  | 'admin.revoke';

export const AUDIT_ACTION_LABEL: Readonly<Record<AuditAction, string>> = {
  'remote_config.publish': 'Published Remote Config',
  'billing.refresh_entitlement': 'Refreshed entitlement',
  'admin.grant': 'Granted admin access',
  'admin.revoke': 'Revoked admin access',
};

export interface AuditWrite {
  actorUid: string;
  actorEmail: string | null;
  action: AuditAction;
  /** What was acted on — a template version, a document path, a uid. */
  target: string;
  /** Prior state. `null` for a field that did not exist. */
  before: Record<string, string | null>;
  after: Record<string, string | null>;
}

/**
 * Result of an audit write.
 *
 * Deliberately NOT a thrown error. A publish that already succeeded must not be
 * reported as failed because the bookkeeping afterwards failed — but the
 * operator still has to be told, because a change landed in production with no
 * record of it. Callers surface `error` alongside their own success.
 */
export type AuditWriteResult =
  | { ok: true; id: string }
  | { ok: false; error: string };

export async function writeAuditEntry(
  entry: AuditWrite,
): Promise<AuditWriteResult> {
  try {
    const ref = await adminDb()
      .collection(COLLECTION)
      .add({
        ...entry,
        // Server timestamp, not the container's clock: the reader orders by
        // this field, and a skewed clock on one instance would interleave its
        // entries incorrectly with everyone else's.
        at: FieldValue.serverTimestamp(),
      });

    return { ok: true, id: ref.id };
  } catch (e) {
    return {
      ok: false,
      error: e instanceof Error && e.message ? e.message : 'Unknown error.',
    };
  }
}

/* ------------------------------------------------------------------ read -- */

export interface AuditRow {
  id: string;
  actorUid: string;
  actorEmail: string | null;
  action: string;
  target: string;
  before: Record<string, string | null>;
  after: Record<string, string | null>;
  /** Epoch ms, or null when the field is missing or malformed. */
  atMs: number | null;
}

export interface AuditPage {
  rows: AuditRow[];
  /**
   * Captured beside the query rather than in the page component: React purity
   * forbids a clock read in a component body, and relative times need a "now"
   * consistent with the rows they describe.
   */
  nowMs: number;
  /** Set when the read failed, so the page can say why instead of showing empty. */
  error: string | null;
}

/**
 * Most recent entries first.
 *
 * `orderBy('at','desc')` on a single field is served by the automatic per-field
 * index, so this needs no composite index in `firestore.indexes.json` — the
 * repo-wide query policy in CLAUDE.md §7. Keep it single-field: adding a filter
 * (by actor, by action) alongside this ordering would require a composite index
 * that a fresh buyer project does not have.
 */
export async function listAuditEntries(limit = 100): Promise<AuditPage> {
  const nowMs = Date.now();

  try {
    const snap = await adminDb()
      .collection(COLLECTION)
      .orderBy('at', 'desc')
      .limit(limit)
      .get();

    return { rows: snap.docs.map(toAuditRow), nowMs, error: null };
  } catch (e) {
    // A collection that has never been written to returns empty rather than
    // throwing, so reaching here means credentials, IAM, or the network — all
    // of which the operator needs told rather than shown as "no activity".
    return {
      rows: [],
      nowMs,
      error: e instanceof Error && e.message ? e.message : 'Unknown error.',
    };
  }
}

function toAuditRow(doc: QueryDocumentSnapshot): AuditRow {
  const data = doc.data();

  return {
    id: doc.id,
    actorUid: asString(data.actorUid) ?? 'unknown',
    actorEmail: asString(data.actorEmail),
    action: asString(data.action) ?? 'unknown',
    target: asString(data.target) ?? '',
    before: asValueMap(data.before),
    after: asValueMap(data.after),
    // Shared with the users module rather than re-spelled: it already handles
    // Timestamp, Date, and raw-number forms, and returns null instead of NaN.
    atMs: toMillis(data.at),
  };
}

function asString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

/**
 * Coerces a stored before/after payload back to `{ key: string | null }`.
 *
 * Defensive because the log is append-only and long-lived: an entry written by
 * an older build of the panel must still render rather than crash the page.
 */
function asValueMap(value: unknown): Record<string, string | null> {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }

  const out: Record<string, string | null> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    out[key] = raw == null ? null : String(raw);
  }
  return out;
}
