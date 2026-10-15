/**
 * Deployment region for all Homa Finance Cloud Functions.
 *
 * Pinned to `europe-west1` (Belgium): the closest Tier-1 region to Nigeria,
 * since West African subsea cables land in Europe. (The seller's default was
 * Singapore.) Must match the Firestore location. Every function (auth triggers, AI callables, schedulers) must
 * reuse this constant; cross-region Functions ↔ Firestore latency
 * dominates trigger speed, so we don't mix regions per function.
 */
export const REGION = 'europe-west1';
