import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION } from '../../utils/region';
import {
  detectSubscriptionCandidates,
  normalizeNote,
  type SubTxn,
} from './subscription_logic';

if (!admin.apps.length) admin.initializeApp();

const LOOKBACK_DAYS = 90;
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Callable: subscription detector (pattern matching, NO LLM) — PRD §7.4.
 *
 * Per CLAUDE.md §7 this still goes through auth, but skips quota +
 * rate-limit because the work is local computation only and cheap to run.
 *
 * Logic:
 *  - Pull the last 90 days of the user's expense transactions.
 *  - Group by (normalized note, amount, currency).
 *  - A "candidate" needs ≥ 3 occurrences AND gaps that are either roughly
 *    monthly (28–35 days) or roughly weekly (6–8 days).
 */
export const detectSubscriptions = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }
    const uid = request.auth.uid;
    _validateInput(request.data);

    const db = admin.firestore();
    const since = new Date(Date.now() - LOOKBACK_DAYS * DAY_MS);

    // Single-field range filter only — Firestore serves this from the
    // automatic per-field index, so a fresh buyer project needs NO composite
    // index deploy. Combining this `date >=` range with a `type ==` equality
    // WOULD require a composite index (the query throws FAILED_PRECONDITION
    // otherwise, surfacing to the client as "Couldn't run the detector");
    // we filter `type` in the mapping loop below instead. The 90-day window
    // for one user is small, so over-fetching income rows is negligible.
    let snap: FirebaseFirestore.QuerySnapshot;
    try {
      snap = await db
        .collection(`users/${uid}/transactions`)
        .where('date', '>=', admin.firestore.Timestamp.fromDate(since))
        .get();
    } catch (e) {
      console.error('detectSubscriptions: tx fetch failed', e);
      throw new HttpsError('internal', 'Failed to read transactions');
    }

    // Map Firestore docs to SubTxn, parsing `date` correctly.
    // BUG FIX: `t.date` is a Firestore Timestamp, NOT a string. The original
    // code called `_str(t.date, '')` which always returned '' for a Timestamp
    // object, making `new Date('')` invalid and skipping every doc — the
    // detector always returned {candidates: []}. We now use `.toDate()` on
    // the Timestamp with a defensive fallback for string/number values.
    const txns: SubTxn[] = [];
    for (const doc of snap.docs) {
      const t = doc.data();
      // Was a query-level `where('type','==','expense')`; moved here to keep
      // the query single-field (see note above). Only expenses can be subs.
      if (_str(t.type, '') !== 'expense') continue;
      const note = _str(t.note, '');
      if (!normalizeNote(note)) continue;
      const amount = _num(t.amount, 0);
      if (amount <= 0) continue;
      const currency = _str(t.currency, 'USD');

      // Correctly parse the Firestore Timestamp date field.
      let date: Date;
      if (t.date instanceof admin.firestore.Timestamp) {
        date = t.date.toDate();
      } else if (typeof t.date === 'string') {
        date = new Date(t.date);
      } else if (typeof t.date === 'number') {
        date = new Date(t.date);
      } else {
        continue; // unrecognised date type — skip
      }
      if (!Number.isFinite(date.getTime())) continue;

      txns.push({ id: doc.id, note, amount, currency, date });
    }

    const candidates = detectSubscriptionCandidates(txns);

    return { candidates };
  },
);

function _validateInput(data: unknown): void {
  if (data == null) return;
  if (typeof data !== 'object') {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
}

function _str(v: unknown, fallback: string): string {
  return typeof v === 'string' ? v : fallback;
}

function _num(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
