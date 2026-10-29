import * as admin from 'firebase-admin';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { REGION } from '../utils/region';
import { writeHeartbeat } from './heartbeat';
import { addInterval } from './recurring_interval';

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * `processRecurringRules` — PRD §8.1 daily scheduler. Materializes due
 * `recurringRules` into real `transactions` for every user.
 *
 * Runs at 00:00 UTC. For each non-paused rule where `nextDueDate <= now`:
 *   1. Parses the stored `transactionTemplate` JSON (mirror of the Drift
 *      schema in `apps/mobile/lib/data/local/tables/recurring_rules.dart`).
 *   2. Inserts one `transactions/{txId}` doc per due occurrence, stamped
 *      with `isRecurring: true` + `recurringRuleId`.
 *   3. Catch-up loop (cap 50 iters/rule) advances `nextDueDate` by
 *      `interval` units of `frequency` until it's in the future.
 *   4. If `endDate` is set and the new `nextDueDate` overshoots it, the
 *      rule is auto-paused.
 *
 * 2nd-gen scheduled function (mirrors `getFxRate`'s 2nd-gen pattern).
 * Per-rule `try/catch` keeps a single bad doc from killing the batch.
 */

const MAX_ITERATIONS_PER_RULE = 50;

interface TransactionTemplate {
  type?: string;
  amount?: number;
  walletId?: string;
  categoryId?: string;
  note?: string | null;
}

export const processRecurringRules = onSchedule(
  {
    schedule: '0 0 * * *',
    region: REGION,
    timeZone: 'UTC',
    memory: '512MiB',
    timeoutSeconds: 540,
  },
  async (_event) => {
    const startedAt = Date.now();
    let status: 'ok' | 'error' = 'ok';
    let errorMessage: string | undefined;
    let rulesProcessed = 0;

    try {
      rulesProcessed = await _processDueRules();
    } catch (err) {
      status = 'error';
      errorMessage = String(err);
      console.error('processRecurringRules: run failed:', err);
      // Re-throw so Cloud Scheduler marks the run failed and retries.
      throw err;
    } finally {
      // Heartbeat for the admin panel: a scheduler that silently stops firing
      // is otherwise indistinguishable from one that ran cleanly.
      await writeHeartbeat({
        functionName: 'processRecurringRules',
        status,
        durationMs: Date.now() - startedAt,
        processed: rulesProcessed,
        error: errorMessage,
      });
    }
  },
);

/**
 * Runs one pass over every due rule. Returns the number of rules processed
 * (for the heartbeat's `processed` field).
 */
async function _processDueRules(): Promise<number> {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();

  const dueSnap = await db
    .collectionGroup('recurringRules')
    .where('isPaused', '==', false)
    .where('nextDueDate', '<=', now)
    .get();

  let rulesProcessed = 0;
  let transactionsCreated = 0;

  for (const ruleDoc of dueSnap.docs) {
    try {
      const uid = ruleDoc.ref.parent.parent?.id;
      if (!uid) {
        console.warn(
          `Skipping rule ${ruleDoc.id}: cannot derive uid from path ${ruleDoc.ref.path}`,
        );
        continue;
      }

      const data = ruleDoc.data() as Record<string, unknown>;
      const frequency = String(data.frequency ?? 'monthly');
      const interval = Math.max(1, Number(data.interval ?? 1));
      const mode = String(data.mode ?? 'auto');
      const endDateTs = data.endDate as admin.firestore.Timestamp | null | undefined;
      const endDate = endDateTs ? endDateTs.toDate() : null;
      let nextDueDate = (data.nextDueDate as admin.firestore.Timestamp).toDate();

      // The template is stored as a JSON *string* in Drift; Firestore mirror
      // preserves that shape so server + client agree.
      const rawTemplate = data.transactionTemplate;
      let template: TransactionTemplate;
      if (typeof rawTemplate === 'string') {
        template = JSON.parse(rawTemplate) as TransactionTemplate;
      } else if (rawTemplate && typeof rawTemplate === 'object') {
        template = rawTemplate as TransactionTemplate;
      } else {
        console.warn(
          `Skipping rule ${ruleDoc.id}: missing or invalid transactionTemplate`,
        );
        continue;
      }

      if (
        !template.walletId ||
        !template.categoryId ||
        typeof template.amount !== 'number' ||
        !template.type
      ) {
        console.warn(
          `Skipping rule ${ruleDoc.id}: incomplete template`,
        );
        continue;
      }

      // Look up wallet currency once per rule.
      const walletSnap = await db
        .doc(`users/${uid}/wallets/${template.walletId}`)
        .get();
      const walletCurrency =
        (walletSnap.exists && (walletSnap.data()?.currency as string)) || '';

      // Catch-up: emit one transaction per due occurrence.
      let iterations = 0;
      let shouldPause = false;
      const nowMs = now.toDate().getTime();

      while (
        nextDueDate.getTime() <= nowMs &&
        iterations < MAX_ITERATIONS_PER_RULE
      ) {
        const occurrenceDate = nextDueDate;
        const txId = `${uid}_t_${Date.now()}_${iterations}`;
        const txRef = db.doc(`users/${uid}/transactions/${txId}`);

        if (mode === 'auto') {
          await txRef.set({
            id: txId,
            userId: uid,
            walletId: template.walletId,
            categoryId: template.categoryId,
            type: template.type,
            amount: template.amount,
            currency: walletCurrency,
            date: admin.firestore.Timestamp.fromDate(occurrenceDate),
            note: template.note ?? null,
            isRecurring: true,
            recurringRuleId: ruleDoc.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          transactionsCreated += 1;
        }
        // Reminder mode: documented as P7 polish. For v1 we behave like
        // 'auto' so the user still sees the transaction; once FCM lands
        // we'll branch here to push instead of materialize.
        else {
          await txRef.set({
            id: txId,
            userId: uid,
            walletId: template.walletId,
            categoryId: template.categoryId,
            type: template.type,
            amount: template.amount,
            currency: walletCurrency,
            date: admin.firestore.Timestamp.fromDate(occurrenceDate),
            note: template.note ?? null,
            isRecurring: true,
            recurringRuleId: ruleDoc.id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          transactionsCreated += 1;
        }

        nextDueDate = addInterval(nextDueDate, frequency, interval);
        iterations += 1;

        if (endDate && nextDueDate.getTime() > endDate.getTime()) {
          shouldPause = true;
          break;
        }
      }

      // Persist the rule's updated cursor (+ optional pause).
      const patch: Record<string, unknown> = {
        nextDueDate: admin.firestore.Timestamp.fromDate(nextDueDate),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (shouldPause) patch.isPaused = true;
      await ruleDoc.ref.set(patch, { merge: true });

      rulesProcessed += 1;
    } catch (err) {
      console.error(
        `Failed to process recurring rule ${ruleDoc.ref.path}:`,
        err,
      );
    }
  }

  console.log(
    `Processed ${rulesProcessed} rules, created ${transactionsCreated} transactions`,
  );

  return rulesProcessed;
}
