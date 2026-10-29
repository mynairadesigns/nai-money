import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { REGION } from '../utils/region';
import { writeHeartbeat } from './heartbeat';
import { DailyStats, dayKey, daysAgo, shapeDailyStats, utcDayStart } from './stats_logic';

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * `aggregatePlatformStats` — daily platform snapshot for the admin panel.
 *
 * Writes one `adminStatsDaily/{YYYY-MM-DD}` doc per day so the panel can draw
 * growth/retention trends. Without it the panel can only ever show "right
 * now": there is no per-day history anywhere in Firestore.
 *
 * **Cost:** every number comes from a `count()` aggregation query, which is
 * billed as a handful of reads regardless of collection size — this run costs
 * the same at 100 users as at 1,000,000. Never replace these with a `.get()`
 * and a `.size`.
 *
 * **Index policy (CLAUDE.md §7):** every query is single-field. `newUsers`
 * uses two range filters on the *same* field (`createdAt`), which the
 * automatic per-field index serves — no composite index needed.
 *
 * Runs at 00:30 UTC. Because the calendar day has just closed, the day these
 * numbers describe is **yesterday**, and that is the doc id we key by —
 * `adminStatsDaily/2026-08-09` is written by the run at 2026-08-10 00:30 UTC.
 * The 30-minute offset keeps it clear of `processRecurringRules` at 00:00.
 */
export const aggregatePlatformStats = onSchedule(
  {
    schedule: '30 0 * * *',
    region: REGION,
    timeZone: 'UTC',
    memory: '256MiB',
    timeoutSeconds: 120,
  },
  async (_event) => {
    const startedAt = Date.now();
    let status: 'ok' | 'error' = 'ok';
    let errorMessage: string | undefined;
    let processed = 0;

    try {
      const db = admin.firestore();
      const now = new Date();

      // The closed day is [dayStart, dayEnd): midnight-to-midnight UTC.
      const dayEnd = utcDayStart(now);
      const dayStart = daysAgo(dayEnd, 1);
      const key = dayKey(dayStart);

      const users = db.collection('users');
      const ts = (d: Date) => admin.firestore.Timestamp.fromDate(d);

      // Activity windows are rolling from *now*, not aligned to the closed
      // day — "active in the last 7 days" is the question the panel asks.
      const [total, created, premium, active24h, active7d, active30d] =
        await Promise.all([
          users.count().get(),
          users
            .where('createdAt', '>=', ts(dayStart))
            .where('createdAt', '<', ts(dayEnd))
            .count()
            .get(),
          users.where('premiumStatus', '==', 'premium').count().get(),
          users.where('lastSyncAt', '>=', ts(daysAgo(now, 1))).count().get(),
          users.where('lastSyncAt', '>=', ts(daysAgo(now, 7))).count().get(),
          users.where('lastSyncAt', '>=', ts(daysAgo(now, 30))).count().get(),
        ]);

      const stats: DailyStats = shapeDailyStats({
        totalUsers: total.data().count,
        newUsers: created.data().count,
        premiumUsers: premium.data().count,
        activeUsers24h: active24h.data().count,
        activeUsers7d: active7d.data().count,
        activeUsers30d: active30d.data().count,
      });
      processed = stats.totalUsers;

      // Keyed by day + merge → a manual re-run overwrites instead of
      // duplicating, and any field the panel adds later survives.
      await db.doc(`adminStatsDaily/${key}`).set(
        {
          ...stats,
          computedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      console.log(
        `aggregatePlatformStats: wrote adminStatsDaily/${key} — ` +
        `total=${stats.totalUsers}, new=${stats.newUsers}, ` +
        `premium=${stats.premiumUsers}, active24h=${stats.activeUsers24h}, ` +
        `active7d=${stats.activeUsers7d}, active30d=${stats.activeUsers30d}`,
      );
    } catch (err) {
      status = 'error';
      errorMessage = String(err);
      console.error('aggregatePlatformStats: run failed:', err);
      // Re-throw so Cloud Scheduler marks the run failed and retries.
      throw err;
    } finally {
      await writeHeartbeat({
        functionName: 'aggregatePlatformStats',
        status,
        durationMs: Date.now() - startedAt,
        processed,
        error: errorMessage,
      });
    }
  },
);
