/**
 * Pure subscription-detection logic — zero firebase imports.
 *
 * Extracted from `detect_subscriptions.ts` so the bucketing + gap-analysis
 * algorithm can be unit-tested without initialising firebase-admin.
 */

import * as crypto from 'crypto';

const DAY_MS = 24 * 60 * 60 * 1000;
const MIN_OCCURRENCES = 3;
const MONTHLY_MIN_GAP_DAYS = 28;
const MONTHLY_MAX_GAP_DAYS = 35;
const WEEKLY_MIN_GAP_DAYS = 6;
const WEEKLY_MAX_GAP_DAYS = 8;
const AMOUNT_BUCKET_CENTS = 1; // group by exact amount (no fuzz)

/** A single expense transaction passed to the detector. */
export interface SubTxn {
  id: string;
  note: string;
  amount: number;
  currency: string;
  date: Date;
}

/** One detected subscription candidate. */
export interface SubscriptionCandidate {
  candidateId: string;
  merchant: string;
  amount: number;
  currency: string;
  frequency: 'weekly' | 'monthly';
  occurrences: number;
  sampleTransactionIds: string[];
}

/**
 * Normalises a merchant note for bucketing.
 * Lowercases and collapses non-alphanumeric runs to spaces.
 */
export function normalizeNote(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Deterministic 16-hex SHA-1 candidate ID.
 * Input format: `merchant.toLowerCase()|amount|currency|frequency`
 */
function _hash(input: string): string {
  return crypto.createHash('sha1').update(input).digest('hex').substring(0, 16);
}

interface Bucket {
  merchant: string;
  amount: number;
  currency: string;
  entries: Array<{ id: string; date: Date }>;
}

/**
 * Analyses a list of expense transactions and returns any detected
 * subscription candidates.
 *
 * Rules (mirrors the handler in `detect_subscriptions.ts`):
 *  - Group by (normalizedNote, exactAmount, currency).
 *  - A group needs ≥ MIN_OCCURRENCES (3) entries.
 *  - Sort entries by date; compute inter-occurrence gaps in days.
 *  - A majority of gaps (ceil(gaps/2)) must fall in either monthly
 *    (28–35 d) or weekly (6–8 d) windows for the group to qualify.
 *  - candidateId = sha1(`merchant.lower()|amount|currency|frequency`)
 *    first 16 hex — stable/deterministic for same inputs.
 *  - sampleTransactionIds = last 5 entries (most-recent occurrences).
 *  - Output sorted by occurrences descending.
 */
export function detectSubscriptionCandidates(txns: SubTxn[]): SubscriptionCandidate[] {
  const buckets = new Map<string, Bucket>();

  for (const t of txns) {
    const note = normalizeNote(t.note);
    if (!note) continue;
    if (t.amount <= 0) continue;
    if (!Number.isFinite(t.date.getTime())) continue;

    const bucketKey = `${note}|${Math.round(t.amount / AMOUNT_BUCKET_CENTS)}|${t.currency}`;
    let b = buckets.get(bucketKey);
    if (!b) {
      b = { merchant: t.note.trim(), amount: t.amount, currency: t.currency, entries: [] };
      buckets.set(bucketKey, b);
    }
    b.entries.push({ id: t.id, date: t.date });
  }

  const candidates: SubscriptionCandidate[] = [];

  for (const b of buckets.values()) {
    if (b.entries.length < MIN_OCCURRENCES) continue;

    const sorted = b.entries.slice().sort(
      (a, x) => a.date.getTime() - x.date.getTime(),
    );

    const gaps: number[] = [];
    for (let i = 1; i < sorted.length; i++) {
      const days =
        (sorted[i].date.getTime() - sorted[i - 1].date.getTime()) / DAY_MS;
      gaps.push(days);
    }

    const monthlyHits = gaps.filter(
      (g) => g >= MONTHLY_MIN_GAP_DAYS && g <= MONTHLY_MAX_GAP_DAYS,
    ).length;
    const weeklyHits = gaps.filter(
      (g) => g >= WEEKLY_MIN_GAP_DAYS && g <= WEEKLY_MAX_GAP_DAYS,
    ).length;

    const required = Math.ceil(gaps.length / 2);
    let frequency: 'weekly' | 'monthly' | null = null;
    if (monthlyHits >= required) frequency = 'monthly';
    else if (weeklyHits >= required) frequency = 'weekly';
    if (!frequency) continue;

    const candidateId = _hash(
      `${b.merchant.toLowerCase()}|${b.amount}|${b.currency}|${frequency}`,
    );

    candidates.push({
      candidateId,
      merchant: b.merchant,
      amount: b.amount,
      currency: b.currency,
      frequency,
      occurrences: sorted.length,
      sampleTransactionIds: sorted.slice(-5).map((e) => e.id),
    });
  }

  candidates.sort((a, b) => b.occurrences - a.occurrences);

  return candidates;
}
