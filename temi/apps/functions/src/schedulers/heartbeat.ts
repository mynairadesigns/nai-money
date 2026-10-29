import * as admin from 'firebase-admin';

if (!admin.apps.length) {
  admin.initializeApp();
}

/** Truncation ceiling for the stored `error` string — keeps the doc small. */
const MAX_ERROR_CHARS = 1000;

export interface HeartbeatInput {
  /** Exported function name — becomes the doc id, e.g. `processRecurringRules`. */
  functionName: string;
  status: 'ok' | 'error';
  durationMs: number;
  /** Optional unit of work count (rules processed, docs deleted, users counted). */
  processed?: number;
  /** Only stored when `status === 'error'`. */
  error?: string;
}

/**
 * Records a scheduler run at `adminHeartbeats/{functionName}`.
 *
 * A scheduler that quietly stops firing is invisible today — there is no
 * Firestore trace of a run at all, so "never ran" and "ran fine" look
 * identical to the admin panel. This writes one doc per function, overwritten
 * each run, so staleness (`lastRunAt` far in the past) is itself the alarm.
 *
 * **Never throws.** Callers invoke this from a `finally` block while an
 * exception is in flight; if this rejected there, the heartbeat's own failure
 * would replace the real error and destroy the diagnosis. Failures are logged
 * and swallowed.
 */
export async function writeHeartbeat(input: HeartbeatInput): Promise<void> {
  try {
    const patch: Record<string, unknown> = {
      lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
      status: input.status,
      durationMs: input.durationMs,
      // A successful run must clear a previous run's error, otherwise the
      // panel shows a green status next to a stale red message forever.
      error:
        input.status === 'error'
          ? (input.error ?? 'unknown error').slice(0, MAX_ERROR_CHARS)
          : admin.firestore.FieldValue.delete(),
    };
    if (input.processed !== undefined) patch.processed = input.processed;

    await admin
      .firestore()
      .doc(`adminHeartbeats/${input.functionName}`)
      .set(patch, { merge: true });
  } catch (err) {
    console.error(`writeHeartbeat(${input.functionName}) failed:`, err);
  }
}
