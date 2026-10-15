/**
 * Deployment region for all Moneymind Cloud Functions.
 *
 * Pinned to `europe-west1` (Belgium) — closest Tier-1 region to Nigeria (West African subsea cables land in Europe; changed from the seller's Singapore default). The primary user
 * base. Every function (auth triggers, AI callables, schedulers) must
 * reuse this constant; cross-region Functions ↔ Firestore latency
 * dominates trigger speed, so we don't mix regions per function.
 */
export const REGION = 'europe-west1';
