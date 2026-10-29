import { describe, expect, it } from 'vitest';

import {
  hasAdminClaim,
  sortAdminRows,
  toAdminRow,
  type AdminRow,
  type AuthLookup,
} from './admins';

const NOW = Date.parse('2026-08-10T00:00:00Z');

/** Stands in for a Firestore Timestamp without importing firebase-admin. */
function timestamp(ms: number) {
  return { toMillis: () => ms, toDate: () => new Date(ms) };
}

function found(over: Partial<Extract<AuthLookup, { found: true }>> = {}): AuthLookup {
  return {
    found: true,
    email: 'ada@example.com',
    displayName: 'Ada',
    disabled: false,
    customClaims: { admin: true },
    ...over,
  };
}

describe('hasAdminClaim', () => {
  it('accepts only the boolean true', () => {
    expect(hasAdminClaim({ admin: true })).toBe(true);
  });

  it('rejects truthy look-alikes', () => {
    // requireAdmin() checks `decoded[ADMIN_CLAIM] !== true`, so none of these
    // let anyone sign in. Reporting them as admins would be a lie about access.
    expect(hasAdminClaim({ admin: 'true' })).toBe(false);
    expect(hasAdminClaim({ admin: 1 })).toBe(false);
    expect(hasAdminClaim({ admin: {} })).toBe(false);
  });

  it('rejects an absent claim set', () => {
    expect(hasAdminClaim({})).toBe(false);
    expect(hasAdminClaim(undefined)).toBe(false);
    expect(hasAdminClaim(null)).toBe(false);
  });

  it('ignores unrelated claims', () => {
    expect(hasAdminClaim({ support: true })).toBe(false);
    expect(hasAdminClaim({ support: true, admin: true })).toBe(true);
  });
});

describe('toAdminRow', () => {
  it('reports no drift when the claim and the mirror agree', () => {
    const row = toAdminRow(
      'uid-1',
      {
        uid: 'uid-1',
        email: 'ada@example.com',
        displayName: 'Ada',
        grantedAt: timestamp(NOW),
        grantedBy: 'root@example.com',
      },
      found(),
    );

    expect(row).toEqual({
      uid: 'uid-1',
      email: 'ada@example.com',
      displayName: 'Ada',
      hasClaim: true,
      disabled: false,
      grantedAtMs: NOW,
      grantedBy: 'root@example.com',
      drift: null,
    });
  });

  it('flags a mirror row whose account carries no claim', () => {
    // Revoked out of band, or a grant that wrote the mirror and failed on the
    // claim. Either way the person is listed here but cannot sign in.
    const row = toAdminRow('uid-2', { email: 'bob@example.com' }, found({ customClaims: {} }));

    expect(row.hasClaim).toBe(false);
    expect(row.drift).toBe('claim-missing');
  });

  it('treats a claims object Firebase omitted entirely as no claim', () => {
    // firebase-admin leaves customClaims undefined for an account that has
    // never had one set — the common case, not an edge case.
    expect(toAdminRow('uid-3', {}, found({ customClaims: undefined })).drift).toBe(
      'claim-missing',
    );
  });

  it('flags a mirror row pointing at a deleted account', () => {
    const row = toAdminRow(
      'uid-4',
      {
        email: 'gone@example.com',
        displayName: 'Gone',
        grantedAt: timestamp(NOW),
        grantedBy: 'cli',
      },
      { found: false },
    );

    expect(row.drift).toBe('auth-user-missing');
    expect(row.hasClaim).toBe(false);
    // The stale mirror copy is the only identity left, so it must still render.
    expect(row.email).toBe('gone@example.com');
    expect(row.grantedBy).toBe('cli');
  });

  it('prefers the Auth email over the mirror copy', () => {
    // The mirror is written once at grant time and never updated, so it goes
    // stale the moment the account changes address.
    const row = toAdminRow('uid-5', { email: 'old@example.com' }, found({ email: 'new@example.com' }));
    expect(row.email).toBe('new@example.com');
  });

  it('surfaces a disabled account separately from drift', () => {
    // The claim is intact — the account simply cannot sign in — so this is not
    // mirror drift and must not be reported as it.
    const row = toAdminRow('uid-6', {}, found({ disabled: true }));
    expect(row.disabled).toBe(true);
    expect(row.hasClaim).toBe(true);
    expect(row.drift).toBeNull();
  });

  it('survives a malformed mirror document without throwing', () => {
    // A hand-edited document in the Firestore console is the realistic source:
    // wrong types everywhere, and a row that must still render.
    const row = toAdminRow(
      'uid-7',
      { email: 42, displayName: [], grantedAt: 'yesterday', grantedBy: { by: 'x' } },
      found({ email: null, displayName: null }),
    );

    expect(row.email).toBeNull();
    expect(row.displayName).toBeNull();
    expect(row.grantedAtMs).toBeNull();
    expect(row.grantedBy).toBeNull();
    expect(row.drift).toBeNull();
  });

  it('survives a mirror document that is not an object at all', () => {
    expect(() => toAdminRow('uid-8', 'nonsense', { found: false })).not.toThrow();
    expect(toAdminRow('uid-8', null, { found: false }).uid).toBe('uid-8');
  });
});

describe('sortAdminRows', () => {
  function row(over: Partial<AdminRow>): AdminRow {
    return {
      uid: 'uid',
      email: null,
      displayName: null,
      hasClaim: true,
      disabled: false,
      grantedAtMs: null,
      grantedBy: null,
      drift: null,
      ...over,
    };
  }

  it('orders by email, then uid', () => {
    const sorted = sortAdminRows([
      row({ uid: 'c', email: 'c@example.com' }),
      row({ uid: 'a', email: 'a@example.com' }),
      row({ uid: 'b', email: 'a@example.com' }),
    ]);

    expect(sorted.map((r) => r.uid)).toEqual(['a', 'b', 'c']);
  });

  it('sorts rows with no email last rather than comparing against null', () => {
    const sorted = sortAdminRows([
      row({ uid: 'orphan' }),
      row({ uid: 'z', email: 'z@example.com' }),
    ]);

    expect(sorted.map((r) => r.uid)).toEqual(['z', 'orphan']);
  });

  it('does not mutate its input', () => {
    const input = [row({ uid: 'b', email: 'b@x.com' }), row({ uid: 'a', email: 'a@x.com' })];
    sortAdminRows(input);
    expect(input.map((r) => r.uid)).toEqual(['b', 'a']);
  });
});
