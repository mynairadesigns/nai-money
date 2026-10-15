/**
 * Deployment region for all Moneymind Cloud Functions.
 *
 * Pinned to `asia-southeast1` (Singapore) — closest to the primary user
 * base. Every function (auth triggers, AI callables, schedulers) must
 * reuse this constant; cross-region Functions ↔ Firestore latency
 * dominates trigger speed, so we don't mix regions per function.
 */
export const REGION = 'asia-southeast1';
