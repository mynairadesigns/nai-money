import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { REGION } from '../utils/region';
import { writeHeartbeat } from './heartbeat';
import { AiUsageRecord, previousMonthKey, rollUpMonthly } from './stats_logic';

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * `resetMonthlyAIQuotas` — rollup + cleanup scheduler (PRD §8.1 / §8.3).
 *
 * AI quota counters live under `users/{uid}/aiUsage/{YYYY-MM}`.
 * Because the doc id rotates naturally each month there is nothing to
 * "reset" — the new month's doc simply starts from zero. This function's
 * job is **storage cleanup**: delete stale `aiUsage` docs that are older
 * than the *previous* calendar month so the subcollection doesn't grow
 * unbounded over time.
 *
 * Safety margin: we keep the current month's doc AND the previous month's
 * doc (useful for support investigations and the "X/5 used this month"
 * client counter). Docs two or more months old are deleted.
 *
 * **Rollup (admin panel):** before deleting anything we fold the scan into
 * one `adminStatsMonthly/{YYYY-MM}` doc per month. Without this, usage
 * history evaporates after ~2 months and no trend is ever recoverable. The
 * rollup reuses the collection-group snapshot the cleanup already needs, so
 * it costs zero extra reads. We roll up **every** month in the scan, not
 * just the ones about to be deleted — on first run that backfills the
 * current + previous month, which is the only history that still exists.
 *
 * Runs at 00:00 UTC on the 1st of each month (Cloud Scheduler cron).
 * Uses a collection-group query over `aiUsage`. Deletes in Firestore
 * batches of ≤ 500. Per-doc try/catch so a single bad doc doesn't abort
 * the run.
 */
export const resetMonthlyAIQuotas = onSchedule(
  {
    schedule: '0 0 1 * *',
    region: REGION,
    timeZone: 'UTC',
    memory: '512MiB',
    timeoutSeconds: 540,
  },
  async (_event) => {
    const startedAt = Date.now();
    let status: 'ok' | 'error' = 'ok';
    let errorMessage: string | undefined;
    let deletedCount = 0;

    try {
      const db = admin.firestore();

      // Cutoff: docs whose id < previousMonth should be deleted.
      // We keep `currentMonth` and `previousMonth`; anything before that is stale.
      const cutoff = previousMonthKey(new Date());
      console.log(`resetMonthlyAIQuotas: deleting aiUsage docs with id < "${cutoff}"`);

      // Collection-group query — returns every `aiUsage` subcollection doc
      // across all users. We can't filter by doc id in a range query on a
      // collection-group directly, so we fetch all and filter client-side.
      // In practice there are at most one doc per user per month, so the
      // total dataset is small even at large user counts.
      let allSnap: admin.firestore.QuerySnapshot;
      try {
        allSnap = await db.collectionGroup('aiUsage').get();
      } catch (err) {
        status = 'error';
        errorMessage = `failed to query aiUsage collection-group: ${String(err)}`;
        console.error('resetMonthlyAIQuotas: failed to query aiUsage collection-group:', err);
        return;
      }

      // --- 1. Roll up EVERY month in the scan, before any deletion. ---
      await _rollUpMonthlyStats(db, allSnap);

      // --- 2. Delete the stale docs. ---
      const staleDocs = allSnap.docs.filter((doc) => doc.id < cutoff);
      console.log(
        `resetMonthlyAIQuotas: found ${allSnap.size} total aiUsage docs, ` +
        `${staleDocs.length} are stale (id < "${cutoff}")`,
      );

      if (staleDocs.length === 0) {
        console.log('resetMonthlyAIQuotas: nothing to delete.');
        return;
      }

      // Batch-delete in chunks of 500 (Firestore batch limit).
      const BATCH_SIZE = 500;
      let errorCount = 0;

      for (let i = 0; i < staleDocs.length; i += BATCH_SIZE) {
        const chunk = staleDocs.slice(i, i + BATCH_SIZE);
        const batch = db.batch();
        // Per-chunk tally: the running total would otherwise subtract earlier
        // chunks' failures from this chunk's successes.
        let chunkErrors = 0;
        for (const doc of chunk) {
          try {
            batch.delete(doc.ref);
          } catch (err) {
            console.error(
              `resetMonthlyAIQuotas: failed to queue delete for ${doc.ref.path}:`,
              err,
            );
            chunkErrors += 1;
          }
        }
        errorCount += chunkErrors;
        try {
          await batch.commit();
          deletedCount += chunk.length - chunkErrors;
          console.log(
            `resetMonthlyAIQuotas: committed batch ${Math.floor(i / BATCH_SIZE) + 1}, ` +
            `deleted ${chunk.length} docs`,
          );
        } catch (err) {
          console.error(
            `resetMonthlyAIQuotas: batch commit failed for chunk starting at ${i}:`,
            err,
          );
          errorCount += chunk.length;
        }
      }

      if (errorCount > 0) {
        status = 'error';
        errorMessage = `${errorCount} aiUsage doc(s) failed to delete`;
      }

      console.log(
        `resetMonthlyAIQuotas: done. deleted=${deletedCount}, errors=${errorCount}`,
      );
    } catch (err) {
      status = 'error';
      errorMessage = String(err);
      console.error('resetMonthlyAIQuotas: run failed:', err);
      // Re-throw so Cloud Scheduler marks the run failed and retries.
      throw err;
    } finally {
      await writeHeartbeat({
        functionName: 'resetMonthlyAIQuotas',
        status,
        durationMs: Date.now() - startedAt,
        processed: deletedCount,
        error: errorMessage,
      });
    }
  },
);

/**
 * Folds [snap] into one `adminStatsMonthly/{YYYY-MM}` doc per month present.
 *
 * Idempotent: the write is keyed by month and every field is set explicitly
 * from the full scan, so a re-run overwrites with the same numbers rather
 * than accumulating. Months are few (2–3 in a healthy deployment), so the
 * sequential awaits are cheap.
 *
 * Best-effort — a rollup failure is logged but never blocks the cleanup that
 * follows it. The counters would only be re-derivable until the delete pass,
 * but blocking cleanup on a stats write would let the subcollection grow
 * unbounded, which is the worse failure.
 */
async function _rollUpMonthlyStats(
  db: admin.firestore.Firestore,
  snap: admin.firestore.QuerySnapshot,
): Promise<void> {
  const records: AiUsageRecord[] = [];
  for (const doc of snap.docs) {
    // `users/{uid}/aiUsage/{YYYY-MM}` → parent is `aiUsage`, its parent is the user doc.
    const uid = doc.ref.parent.parent?.id;
    if (!uid) {
      console.warn(
        `resetMonthlyAIQuotas: cannot derive uid from ${doc.ref.path}, skipping in rollup`,
      );
      continue;
    }
    records.push({ month: doc.id, uid, counters: doc.data() ?? {} });
  }

  const rollups = rollUpMonthly(records);
  for (const [month, rollup] of rollups) {
    try {
      await db.doc(`adminStatsMonthly/${month}`).set(
        {
          users: rollup.users,
          usersPremium: rollup.usersPremium,
          aiCalls: rollup.aiCalls,
          aiCallsTotal: rollup.aiCallsTotal,
          activeUsers: rollup.activeUsers,
          rolledUpAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      console.log(
        `resetMonthlyAIQuotas: rolled up adminStatsMonthly/${month} — ` +
        `users=${rollup.users}, active=${rollup.activeUsers}, calls=${rollup.aiCallsTotal}`,
      );
    } catch (err) {
      console.error(
        `resetMonthlyAIQuotas: failed to write adminStatsMonthly/${month}:`,
        err,
      );
    }
  }
}
