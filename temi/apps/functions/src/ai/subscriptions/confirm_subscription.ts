import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION } from '../../utils/region';

if (!admin.apps.length) admin.initializeApp();

interface ConfirmInput {
  candidateId: string;
  merchant: string;
  amount: number;
  currency: string;
  frequency: 'weekly' | 'monthly';
  walletId: string;
  categoryId: string;
  startDate: string; // ISO
}

/**
 * Callable: confirm a detected subscription as a real recurring rule.
 * No quota, no LLM — pure Firestore write.
 *
 * Creates `users/{uid}/recurringRules/{id}` matching the Drift
 * `RecurringRules` schema (PRD §5.1):
 *   - id, transactionTemplate (JSON), frequency, interval (1), startDate,
 *     endDate (null), nextDueDate (= startDate + interval), mode ('auto'),
 *     isPaused (false), createdAt, updatedAt.
 *
 * The transactionTemplate JSON is the canonical shape the daily scheduler
 * (`processRecurringRules`) parses to instantiate future transactions.
 */
export const confirmSubscription = onCall(
  { region: REGION, memory: '256MiB', timeoutSeconds: 30 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }
    const uid = request.auth.uid;

    const input = _validateInput(request.data);

    const startDate = new Date(input.startDate);
    if (!Number.isFinite(startDate.getTime())) {
      throw new HttpsError('invalid-argument', 'startDate must be a valid ISO date');
    }
    const nextDueDate = _addInterval(startDate, input.frequency, 1);

    const db = admin.firestore();

    // Verify the wallet + category belong to the user — defence in depth
    // on top of Firestore rules.
    const [walletSnap, categorySnap] = await Promise.all([
      db.doc(`users/${uid}/wallets/${input.walletId}`).get().catch(() => null),
      db.doc(`users/${uid}/categories/${input.categoryId}`).get().catch(() => null),
    ]);
    if (!walletSnap || !walletSnap.exists) {
      throw new HttpsError('not-found', 'Wallet not found');
    }
    if (!categorySnap || !categorySnap.exists) {
      throw new HttpsError('not-found', 'Category not found');
    }

    const ruleId = _hash(
      `${uid}|${input.candidateId}|${input.frequency}|${Date.now()}`,
    );

    const transactionTemplate = JSON.stringify({
      type: 'expense',
      amount: input.amount,
      walletId: input.walletId,
      categoryId: input.categoryId,
      note: input.merchant,
    });

    const now = admin.firestore.Timestamp.now();
    const ruleDoc = {
      id: ruleId,
      transactionTemplate,
      frequency: input.frequency,
      interval: 1,
      startDate: admin.firestore.Timestamp.fromDate(startDate),
      endDate: null,
      nextDueDate: admin.firestore.Timestamp.fromDate(nextDueDate),
      mode: 'auto',
      isPaused: false,
      createdAt: now,
      updatedAt: now,
    };

    try {
      await db.doc(`users/${uid}/recurringRules/${ruleId}`).set(ruleDoc);
    } catch (e) {
      console.error('confirmSubscription: write failed', e);
      throw new HttpsError('internal', 'Failed to create recurring rule');
    }

    return { recurringRuleId: ruleId };
  },
);

function _validateInput(data: unknown): ConfirmInput {
  if (typeof data !== 'object' || data === null) {
    throw new HttpsError('invalid-argument', 'Body must be an object');
  }
  const d = data as Record<string, unknown>;
  const candidateId = d.candidateId;
  const merchant = d.merchant;
  const amount = d.amount;
  const currency = d.currency;
  const frequency = d.frequency;
  const walletId = d.walletId;
  const categoryId = d.categoryId;
  const startDate = d.startDate;

  if (typeof candidateId !== 'string' || candidateId.trim() === '') {
    throw new HttpsError('invalid-argument', 'candidateId must be a non-empty string');
  }
  if (typeof merchant !== 'string' || merchant.trim() === '') {
    throw new HttpsError('invalid-argument', 'merchant must be a non-empty string');
  }
  if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError('invalid-argument', 'amount must be a positive number');
  }
  if (typeof currency !== 'string' || currency.length !== 3) {
    throw new HttpsError('invalid-argument', 'currency must be a 3-letter code');
  }
  if (frequency !== 'weekly' && frequency !== 'monthly') {
    throw new HttpsError('invalid-argument', 'frequency must be weekly or monthly');
  }
  if (typeof walletId !== 'string' || walletId.trim() === '') {
    throw new HttpsError('invalid-argument', 'walletId must be a non-empty string');
  }
  if (typeof categoryId !== 'string' || categoryId.trim() === '') {
    throw new HttpsError('invalid-argument', 'categoryId must be a non-empty string');
  }
  if (typeof startDate !== 'string' || startDate.trim() === '') {
    throw new HttpsError('invalid-argument', 'startDate must be an ISO date string');
  }
  return {
    candidateId: candidateId.trim(),
    merchant: merchant.trim(),
    amount,
    currency: currency.toUpperCase(),
    frequency,
    walletId: walletId.trim(),
    categoryId: categoryId.trim(),
    startDate: startDate.trim(),
  };
}

/**
 * Mirrors `addInterval` in `apps/functions/src/schedulers/process_recurring_rules.ts`
 * (and Drift-side `addRecurringInterval` in
 * `apps/mobile/lib/features/recurring/data/recurring_catalog.dart`).
 * Only the frequencies emitted by `detectSubscriptions` are supported here.
 */
function _addInterval(
  date: Date,
  frequency: 'weekly' | 'monthly',
  interval: number,
): Date {
  const d = new Date(date.getTime());
  switch (frequency) {
    case 'weekly':
      d.setUTCDate(d.getUTCDate() + 7 * interval);
      return d;
    case 'monthly':
      return new Date(
        Date.UTC(
          d.getUTCFullYear(),
          d.getUTCMonth() + interval,
          d.getUTCDate(),
          d.getUTCHours(),
          d.getUTCMinutes(),
          d.getUTCSeconds(),
        ),
      );
  }
}

function _hash(input: string): string {
  return crypto.createHash('sha1').update(input).digest('hex').substring(0, 20);
}
