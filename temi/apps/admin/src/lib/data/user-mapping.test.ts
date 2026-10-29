import { describe, expect, it } from 'vitest';

import {
  entitlementDrift,
  isMissingIndexError,
  isPremiumNow,
  quotaCountedTotal,
  startOfMonthUtc,
  toMillis,
  toUserDetailRow,
  toUserRow,
  type UserListRow,
} from './user-mapping';

const NOW = Date.parse('2026-08-10T00:00:00Z');
const HOUR = 60 * 60 * 1000;

/** Stands in for a Firestore Timestamp without importing firebase-admin. */
function timestamp(ms: number) {
  return { toMillis: () => ms, toDate: () => new Date(ms) };
}

describe('toMillis', () => {
  it('reads a Firestore Timestamp', () => {
    expect(toMillis(timestamp(NOW))).toBe(NOW);
  });

  it('accepts a Date or a raw number', () => {
    expect(toMillis(new Date(NOW))).toBe(NOW);
    expect(toMillis(NOW)).toBe(NOW);
  });

  it('returns null rather than NaN for unusable values', () => {
    expect(toMillis(null)).toBeNull();
    expect(toMillis(undefined)).toBeNull();
    expect(toMillis('2026-08-10')).toBeNull();
    expect(toMillis(new Date('nonsense'))).toBeNull();
    expect(toMillis(Number.NaN)).toBeNull();
  });
});

describe('toUserRow', () => {
  it('maps a fully populated document', () => {
    const row = toUserRow('uid-1', {
      email: 'a@example.com',
      displayName: 'Ada',
      defaultCurrency: 'USD',
      premiumStatus: 'premium',
      premiumExpiry: timestamp(NOW + HOUR),
      createdAt: timestamp(NOW - HOUR),
      lastSyncAt: timestamp(NOW),
    });

    expect(row).toEqual({
      uid: 'uid-1',
      email: 'a@example.com',
      displayName: 'Ada',
      defaultCurrency: 'USD',
      premiumStatus: 'premium',
      premiumExpiryMs: NOW + HOUR,
      createdAtMs: NOW - HOUR,
      lastSyncAtMs: NOW,
    });
  });

  it('survives a sparse document without throwing', () => {
    // A user created by the auth trigger but never synced has most fields
    // absent; the panel must still list them.
    const row = toUserRow('uid-2', {});
    expect(row.uid).toBe('uid-2');
    expect(row.email).toBeNull();
    expect(row.premiumExpiryMs).toBeNull();
  });

  it('survives a missing document', () => {
    expect(toUserRow('uid-3', undefined).uid).toBe('uid-3');
  });
});

describe('isPremiumNow', () => {
  const base: UserListRow = {
    uid: 'u',
    email: null,
    displayName: null,
    defaultCurrency: null,
    premiumStatus: 'premium',
    premiumExpiryMs: NOW + HOUR,
    createdAtMs: null,
    lastSyncAtMs: null,
  };

  it('is premium with an unexpired expiry', () => {
    expect(isPremiumNow(base, NOW)).toBe(true);
  });

  it('is NOT premium once the expiry has passed', () => {
    expect(isPremiumNow({ ...base, premiumExpiryMs: NOW - HOUR }, NOW)).toBe(false);
  });

  it('is NOT premium when premiumExpiry is null', () => {
    // Mirrors the server: quota_logic.ts treats a null expiry as free, which
    // is why the webhook writes a +100-year timestamp for lifetime purchases.
    expect(isPremiumNow({ ...base, premiumExpiryMs: null }, NOW)).toBe(false);
  });

  it('is NOT premium when the status says free', () => {
    expect(isPremiumNow({ ...base, premiumStatus: 'free' }, NOW)).toBe(false);
  });
});

describe('entitlementDrift', () => {
  const base: UserListRow = {
    uid: 'u',
    email: null,
    displayName: null,
    defaultCurrency: null,
    premiumStatus: 'free',
    premiumExpiryMs: null,
    createdAtMs: null,
    lastSyncAtMs: null,
  };

  it('reports no drift for a plain free user', () => {
    expect(entitlementDrift(base, NOW)).toBeNull();
  });

  it('reports no drift for a valid premium user', () => {
    expect(
      entitlementDrift(
        { ...base, premiumStatus: 'premium', premiumExpiryMs: NOW + HOUR },
        NOW,
      ),
    ).toBeNull();
  });

  it('flags a lapsed subscription still marked premium', () => {
    expect(
      entitlementDrift(
        { ...base, premiumStatus: 'premium', premiumExpiryMs: NOW - HOUR },
        NOW,
      ),
    ).toBe('expired-but-marked-premium');
  });

  it('flags a null expiry on a premium user', () => {
    // The trap: this user LOOKS premium in the app but the server denies them
    // the quota bypass.
    expect(
      entitlementDrift({ ...base, premiumStatus: 'premium' }, NOW),
    ).toBe('expired-but-marked-premium');
  });

  it('flags a free user carrying a future expiry', () => {
    expect(
      entitlementDrift({ ...base, premiumExpiryMs: NOW + HOUR }, NOW),
    ).toBe('free-but-has-future-expiry');
  });
});

describe('toUserDetailRow', () => {
  it('carries the list fields plus the detail-only ones', () => {
    const row = toUserDetailRow('uid-1', {
      email: 'a@example.com',
      photoUrl: 'https://example.com/a.png',
      monthlyIncome: 4200,
      financialHealthScore: 71,
      createdAt: timestamp(NOW - HOUR),
      setupCompletedAt: timestamp(NOW),
      updatedAt: timestamp(NOW),
    });

    expect(row.email).toBe('a@example.com');
    expect(row.createdAtMs).toBe(NOW - HOUR);
    expect(row.photoUrl).toBe('https://example.com/a.png');
    expect(row.monthlyIncome).toBe(4200);
    expect(row.financialHealthScore).toBe(71);
    expect(row.setupCompletedAtMs).toBe(NOW);
    expect(row.updatedAtMs).toBe(NOW);
  });

  it('nulls the optional stamps a pre-onboarding user has never written', () => {
    const row = toUserDetailRow('uid-2', { email: 'b@example.com' });
    expect(row.setupCompletedAtMs).toBeNull();
    expect(row.updatedAtMs).toBeNull();
    expect(row.monthlyIncome).toBeNull();
  });

  it('distinguishes a zero score from an absent one', () => {
    // 0 is a legitimate health score; `??` must not turn it into null or the
    // panel would report "no score" for the worst-off users.
    expect(toUserDetailRow('u', { financialHealthScore: 0 }).financialHealthScore).toBe(0);
  });
});

describe('quotaCountedTotal', () => {
  it('sums only the fields that share the free-tier ceiling', () => {
    const total = quotaCountedTotal({
      categorize: 2,
      chat: 3,
      scan: 1,
      // None of these count — separate ceiling, no ceiling, and not usage.
      fx: 900,
      premiumCalls: 40,
      rejected: 7,
    });
    expect(total).toBe(6);
  });

  it('treats an absent document as zero usage', () => {
    expect(quotaCountedTotal(null)).toBe(0);
    expect(quotaCountedTotal(undefined)).toBe(0);
    expect(quotaCountedTotal({})).toBe(0);
  });

  it('ignores a non-numeric counter rather than producing NaN', () => {
    // A hand-edited document in the Firebase console is the realistic source
    // of this; a NaN would render as an em-dash and hide real usage.
    const total = quotaCountedTotal({
      chat: 4,
      scan: 'oops' as unknown as number,
    });
    expect(total).toBe(4);
  });
});

describe('startOfMonthUtc', () => {
  it('snaps to the first of the month in UTC', () => {
    expect(startOfMonthUtc(Date.parse('2026-08-10T13:45:00Z'))).toBe(
      Date.parse('2026-08-01T00:00:00Z'),
    );
  });

  it('is already the boundary on the first at midnight', () => {
    const first = Date.parse('2026-08-01T00:00:00Z');
    expect(startOfMonthUtc(first)).toBe(first);
  });

  it('does not roll back a year at the January boundary', () => {
    expect(startOfMonthUtc(Date.parse('2026-01-03T00:00:00Z'))).toBe(
      Date.parse('2026-01-01T00:00:00Z'),
    );
  });
});

describe('isMissingIndexError', () => {
  it('recognises the gRPC FAILED_PRECONDITION shape', () => {
    const e = Object.assign(new Error('The query requires an index. Create it here: ...'), {
      code: 9,
    });
    expect(isMissingIndexError(e)).toBe(true);
  });

  it('recognises the string-coded variant', () => {
    expect(
      isMissingIndexError({
        code: 'failed-precondition',
        message: 'The query requires an index.',
      }),
    ).toBe(true);
  });

  it('ignores a FAILED_PRECONDITION that is not about indexes', () => {
    // Same code is used for aborted transactions and precondition failures on
    // writes; those must keep propagating as real errors.
    expect(
      isMissingIndexError({ code: 9, message: 'Document already exists' }),
    ).toBe(false);
  });

  it('ignores unrelated errors and non-objects', () => {
    expect(isMissingIndexError(new Error('permission denied'))).toBe(false);
    expect(isMissingIndexError(null)).toBe(false);
    expect(isMissingIndexError('failed-precondition index')).toBe(false);
  });
});
