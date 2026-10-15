import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Per-instance in-memory rate limit. NOT distributed — cold starts and
 * multiple function instances mean a determined caller could exceed the
 * cap; this is best-effort burst protection only. Real distributed rate
 * limiting (Redis / Firestore tokens) is deferred to P5+.
 */
const _windows = new Map<string, number[]>();

export function enforceRateLimit(opts: {
  uid: string;
  key: string;
  windowSeconds: number;
  maxCalls: number;
}): void {
  const { uid, key, windowSeconds, maxCalls } = opts;
  const bucket = `${uid}:${key}`;
  const now = Date.now();
  const cutoff = now - windowSeconds * 1000;
  const arr = (_windows.get(bucket) ?? []).filter((t) => t > cutoff);
  if (arr.length >= maxCalls) {
    throw new HttpsError(
      'resource-exhausted',
      'Slow down — try again in a moment',
    );
  }
  arr.push(now);
  _windows.set(bucket, arr);
}
