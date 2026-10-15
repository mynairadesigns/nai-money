import { describe, expect, it } from 'vitest';

import {
  daysUntil,
  isAnonymousAppUserId,
  summarizeEvents,
  toEventRow,
  type RevenueCatEventRow,
} from './billing';

const NOW = Date.parse('2026-08-10T00:00:00Z');
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

/** Stands in for a Firestore Timestamp without importing firebase-admin. */
function timestamp(ms: number) {
  return { toMillis: () => ms, toDate: () => new Date(ms) };
}

function event(
  overrides: Partial<RevenueCatEventRow> = {},
): RevenueCatEventRow {
  return {
    id: overrides.id ?? 'e',
    type: overrides.type ?? 'RENEWAL',
    appUserId: overrides.appUserId ?? 'uid-1',
    receivedAtMs: overrides.receivedAtMs === undefined ? NOW : overrides.receivedAtMs,
    productId: overrides.productId ?? null,
    expiresAtMs: overrides.expiresAtMs ?? null,
    handled: overrides.handled ?? true,
  };
}

describe('toEventRow', () => {
  it('maps a document written by handleRevenueCatWebhook', () => {
    const row = toEventRow('doc-1', {
      type: 'INITIAL_PURCHASE',
      appUserId: 'uid-1',
      receivedAt: timestamp(NOW),
      productId: 'moneymind_premium_monthly',
      expiresAtMs: NOW + 30 * DAY,
      handled: true,
    });

    expect(row).toEqual({
      id: 'doc-1',
      type: 'INITIAL_PURCHASE',
      appUserId: 'uid-1',
      receivedAtMs: NOW,
      productId: 'moneymind_premium_monthly',
      expiresAtMs: NOW + 30 * DAY,
      handled: true,
    });
  });

  it('falls back to expirationMs when that is the field present', () => {
    // The shipped webhook writes expiresAtMs; expirationMs is closer to
    // RevenueCat's own payload name and may appear in a hand-written doc.
    expect(toEventRow('d', { expirationMs: NOW }).expiresAtMs).toBe(NOW);
  });

  it('survives a document missing every optional field', () => {
    const row = toEventRow('doc-2', {});

    expect(row.type).toBe('UNKNOWN');
    expect(row.appUserId).toBeNull();
    expect(row.productId).toBeNull();
    expect(row.expiresAtMs).toBeNull();
  });

  it('survives a document that is not an object at all', () => {
    expect(toEventRow('doc-3', undefined).type).toBe('UNKNOWN');
    expect(toEventRow('doc-4', 'nonsense').id).toBe('doc-4');
  });

  it('nulls a malformed or missing receivedAt rather than producing NaN', () => {
    // `receivedAt` is a serverTimestamp, so it is momentarily null on a doc read
    // back before the write resolves — and an older build may have stored a
    // string. Neither may render as "Invalid Date".
    expect(toEventRow('d', { receivedAt: '2026-08-10' }).receivedAtMs).toBeNull();
    expect(toEventRow('d', { receivedAt: null }).receivedAtMs).toBeNull();
    expect(toEventRow('d', {}).receivedAtMs).toBeNull();
    expect(toEventRow('d', { receivedAt: Number.NaN }).receivedAtMs).toBeNull();
  });

  it('treats anything other than true as not handled', () => {
    // The webhook only writes `handled: true` once the entitlement write
    // committed; an absent or truthy-but-not-true value is not that.
    expect(toEventRow('d', { handled: true }).handled).toBe(true);
    expect(toEventRow('d', { handled: false }).handled).toBe(false);
    expect(toEventRow('d', {}).handled).toBe(false);
    expect(toEventRow('d', { handled: 'yes' }).handled).toBe(false);
  });

  it('reads an empty string as absent', () => {
    // ''-valued productId would otherwise render as a blank cell that looks
    // like a value rather than a missing one.
    expect(toEventRow('d', { productId: '', appUserId: '' }).productId).toBeNull();
  });
});

describe('summarizeEvents', () => {
  it('reports zeroes for an empty page without inventing a latest event', () => {
    // This is what a deployment with no webhook configured looks like, and it
    // must not read as an error.
    expect(summarizeEvents([])).toEqual({
      total: 0,
      handled: 0,
      unhandled: 0,
      distinctTypes: 0,
      latestMs: null,
      byType: [],
    });
  });

  it('records the newest timestamp per type, not the first seen', () => {
    const summary = summarizeEvents([
      event({ id: '1', type: 'RENEWAL', receivedAtMs: NOW - 2 * DAY }),
      event({ id: '2', type: 'RENEWAL', receivedAtMs: NOW - HOUR }),
      event({ id: '3', type: 'EXPIRATION', receivedAtMs: NOW - 5 * DAY }),
    ]);

    expect(summary.distinctTypes).toBe(2);
    expect(summary.latestMs).toBe(NOW - HOUR);
    expect(summary.byType.map((t) => t.type)).toEqual(['RENEWAL', 'EXPIRATION']);
    expect(summary.byType[0].lastSeenMs).toBe(NOW - HOUR);
    expect(summary.byType[0].count).toBe(2);
  });

  it('counts handled against unhandled overall and per type', () => {
    const summary = summarizeEvents([
      event({ id: '1', type: 'RENEWAL', handled: true }),
      event({ id: '2', type: 'TEST', handled: false, receivedAtMs: NOW - DAY }),
      event({ id: '3', type: 'TEST', handled: false, receivedAtMs: NOW - 2 * DAY }),
    ]);

    expect(summary.total).toBe(3);
    expect(summary.handled).toBe(1);
    expect(summary.unhandled).toBe(2);

    const test = summary.byType.find((t) => t.type === 'TEST');
    expect(test).toMatchObject({ count: 2, handled: 0, unhandled: 2 });
  });

  it('sorts a type with no usable timestamp last rather than treating it as ancient', () => {
    const summary = summarizeEvents([
      event({ id: '1', type: 'NO_STAMP', receivedAtMs: null }),
      event({ id: '2', type: 'RENEWAL', receivedAtMs: NOW - 10 * DAY }),
    ]);

    expect(summary.byType.map((t) => t.type)).toEqual(['RENEWAL', 'NO_STAMP']);
    expect(summary.byType[1].lastSeenMs).toBeNull();
  });

  it('breaks ties on type name so the ordering cannot shuffle between requests', () => {
    const summary = summarizeEvents([
      event({ id: '1', type: 'ZED', receivedAtMs: NOW }),
      event({ id: '2', type: 'ALPHA', receivedAtMs: NOW }),
      event({ id: '3', type: 'NO_B', receivedAtMs: null }),
      event({ id: '4', type: 'NO_A', receivedAtMs: null }),
    ]);

    expect(summary.byType.map((t) => t.type)).toEqual([
      'ALPHA',
      'ZED',
      'NO_A',
      'NO_B',
    ]);
  });

  it('leaves latestMs null when every row is missing its timestamp', () => {
    const summary = summarizeEvents([
      event({ id: '1', receivedAtMs: null }),
      event({ id: '2', receivedAtMs: null }),
    ]);

    expect(summary.total).toBe(2);
    expect(summary.latestMs).toBeNull();
  });
});

describe('daysUntil', () => {
  it('rounds up so an expiry later today never reads as zero', () => {
    expect(daysUntil(NOW + 8 * HOUR, NOW)).toBe(1);
    expect(daysUntil(NOW + DAY, NOW)).toBe(1);
    expect(daysUntil(NOW + DAY + HOUR, NOW)).toBe(2);
  });

  it('floors at zero for an expiry already in the past', () => {
    expect(daysUntil(NOW - 5 * DAY, NOW)).toBe(0);
  });

  it('has no answer for a missing expiry', () => {
    expect(daysUntil(null, NOW)).toBeNull();
  });
});

describe('isAnonymousAppUserId', () => {
  it('recognises RevenueCat placeholder ids', () => {
    // These never match a users/{uid} document — the app purchased before
    // calling Purchases.logIn(uid).
    expect(isAnonymousAppUserId('$RCAnonymousID:8c0a1b2c3d')).toBe(true);
  });

  it('leaves a real uid alone', () => {
    expect(isAnonymousAppUserId('abc123')).toBe(false);
    expect(isAnonymousAppUserId(null)).toBe(false);
  });
});
