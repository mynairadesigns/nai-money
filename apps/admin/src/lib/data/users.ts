import 'server-only';

import { adminDb } from '@/lib/firebase/admin';
import { previousYearMonth, yearMonth } from '@/lib/format';
import type { AiUsageDocument, UserDocument } from '@/lib/types/user-document';

import {
  isMissingIndexError,
  startOfMonthUtc,
  toUserDetailRow,
  toUserRow,
  type UserDetailRow,
  type UserListRow,
} from './user-mapping';

export type { UserDetailRow, UserListRow };

/**
 * Read helpers over the top-level `users` collection.
 *
 * QUERY POLICY (mirrors the repo-wide rule in CLAUDE.md §7): keep queries
 * single-field so the automatic per-field index always serves them. A fresh
 * buyer project must work without deploying extra composite indexes. The one
 * exception — premium filter + createdAt ordering — is declared in
 * firestore.indexes.json and justified there.
 *
 * The Admin SDK bypasses security rules but NOT indexes, so this constraint
 * applies here exactly as it does on the client.
 */

const USERS = 'users';

export async function countUsers(): Promise<number> {
  const snap = await adminDb().collection(USERS).count().get();
  return snap.data().count;
}

export async function countPremiumUsers(): Promise<number> {
  const snap = await adminDb()
    .collection(USERS)
    .where('premiumStatus', '==', 'premium')
    .count()
    .get();
  return snap.data().count;
}

/**
 * Counts users whose [field] timestamp falls within the last [days].
 *
 * The clock read lives here rather than in the calling server component: page
 * components are held to React's purity rules, and a data helper is the honest
 * place for "now" anyway.
 */
export async function countUsersInLastDays(
  field: 'createdAt' | 'lastSyncAt',
  days: number,
): Promise<number> {
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  const snap = await adminDb()
    .collection(USERS)
    .where(field, '>=', since)
    .count()
    .get();
  return snap.data().count;
}

/**
 * Cursor-paginated user list. Uses `startAfter` rather than `offset` so cost
 * stays flat as an operator pages deeper.
 */
export async function listUsers(opts: {
  limit?: number;
  startAfterCreatedAtMs?: number | null;
  premiumOnly?: boolean;
}): Promise<{ rows: UserListRow[]; nextCursorMs: number | null }> {
  const limit = opts.limit ?? 50;

  let query = adminDb().collection(USERS).orderBy('createdAt', 'desc');

  if (opts.premiumOnly) {
    // Composite index: users(premiumStatus ASC, createdAt DESC).
    query = adminDb()
      .collection(USERS)
      .where('premiumStatus', '==', 'premium')
      .orderBy('createdAt', 'desc');
  }

  if (opts.startAfterCreatedAtMs != null) {
    query = query.startAfter(new Date(opts.startAfterCreatedAtMs));
  }

  const snap = await query.limit(limit).get();
  const rows = snap.docs.map((d) =>
    toUserRow(d.id, d.data() as Partial<UserDocument>),
  );
  const last = rows.at(-1)?.createdAtMs ?? null;

  return {
    rows,
    nextCursorMs: rows.length === limit ? last : null,
  };
}

/** Exact-match lookup. Single-field query — no index needed. */
export async function findUserByEmail(
  email: string,
): Promise<UserListRow | null> {
  const snap = await adminDb()
    .collection(USERS)
    .where('email', '==', email.trim().toLowerCase())
    .limit(1)
    .get();

  const doc = snap.docs[0];
  return doc ? toUserRow(doc.id, doc.data() as Partial<UserDocument>) : null;
}

export async function getUser(uid: string): Promise<UserListRow | null> {
  const doc = await adminDb().collection(USERS).doc(uid).get();
  return doc.exists
    ? toUserRow(doc.id, doc.data() as Partial<UserDocument>)
    : null;
}

/**
 * Per-subcollection document counts for the user detail page. `count()` keeps
 * this cheap even for a user with tens of thousands of transactions.
 */
export async function countUserFootprint(
  uid: string,
): Promise<Record<string, number>> {
  const collections = [
    'wallets',
    'transactions',
    'budgets',
    'goals',
    'debts',
    'recurringRules',
    'categories',
  ] as const;

  const counts = await Promise.all(
    collections.map(async (name) => {
      const snap = await adminDb()
        .collection(USERS)
        .doc(uid)
        .collection(name)
        .count()
        .get();
      return [name, snap.data().count] as const;
    }),
  );

  return Object.fromEntries(counts);
}

/**
 * Month-to-date transaction count, for the free-tier ceiling readout.
 *
 * A lone `date >=` range on one field is served by the automatic per-field
 * index — adding an equality on anything else here would demand a composite
 * one, which is exactly what the query policy above forbids.
 */
export async function countTransactionsSince(
  uid: string,
  sinceMs: number,
): Promise<number> {
  const snap = await adminDb()
    .collection(USERS)
    .doc(uid)
    .collection('transactions')
    .where('date', '>=', new Date(sinceMs))
    .count()
    .get();
  return snap.data().count;
}

/** Direct document get on `users/{uid}/aiUsage/{YYYY-MM}` — never a query. */
export async function getAiUsage(
  uid: string,
  monthKey: string,
): Promise<AiUsageDocument | null> {
  const doc = await adminDb()
    .collection(USERS)
    .doc(uid)
    .collection('aiUsage')
    .doc(monthKey)
    .get();
  return doc.exists ? (doc.data() as AiUsageDocument) : null;
}

export interface UserListResult {
  rows: UserListRow[];
  nextCursorMs: number | null;
  /** The clock the page renders relative times against. */
  nowMs: number;
  /** True when the premium filter's composite index is absent or still building. */
  missingIndex: boolean;
}

/**
 * The single read the /users page makes.
 *
 * Owning both branches — exact-email lookup and the paginated list — keeps the
 * one `Date.now()` here rather than in the component, where React's purity
 * rules apply, and keeps the missing-index rescue out of the JSX.
 */
export async function loadUserList(opts: {
  email?: string | null;
  premiumOnly?: boolean;
  startAfterCreatedAtMs?: number | null;
  limit?: number;
}): Promise<UserListResult> {
  const nowMs = Date.now();

  if (opts.email) {
    const row = await findUserByEmail(opts.email);
    return {
      rows: row ? [row] : [],
      nextCursorMs: null,
      nowMs,
      missingIndex: false,
    };
  }

  try {
    const { rows, nextCursorMs } = await listUsers({
      limit: opts.limit,
      premiumOnly: opts.premiumOnly,
      startAfterCreatedAtMs: opts.startAfterCreatedAtMs,
    });
    return { rows, nextCursorMs, nowMs, missingIndex: false };
  } catch (e) {
    if (isMissingIndexError(e)) {
      return { rows: [], nextCursorMs: null, nowMs, missingIndex: true };
    }
    throw e;
  }
}

export interface UserDetail {
  user: UserDetailRow;
  footprint: Record<string, number>;
  transactionsThisMonth: number;
  currentMonthKey: string;
  previousMonthKey: string;
  currentUsage: AiUsageDocument | null;
  previousUsage: AiUsageDocument | null;
  nowMs: number;
}

/**
 * Everything /users/[uid] renders, in one call.
 *
 * The document read is awaited first so a missing user costs one read instead
 * of a dozen aggregations against subcollections that cannot exist.
 */
export async function loadUserDetail(uid: string): Promise<UserDetail | null> {
  const doc = await adminDb().collection(USERS).doc(uid).get();
  if (!doc.exists) return null;

  const nowMs = Date.now();
  const now = new Date(nowMs);
  const currentMonthKey = yearMonth(now);
  const previousMonthKey = previousYearMonth(now);

  const [footprint, transactionsThisMonth, currentUsage, previousUsage] =
    await Promise.all([
      countUserFootprint(uid),
      countTransactionsSince(uid, startOfMonthUtc(nowMs)),
      getAiUsage(uid, currentMonthKey),
      getAiUsage(uid, previousMonthKey),
    ]);

  return {
    user: toUserDetailRow(doc.id, doc.data() as Partial<UserDocument>),
    footprint,
    transactionsThisMonth,
    currentMonthKey,
    previousMonthKey,
    currentUsage,
    previousUsage,
    nowMs,
  };
}
