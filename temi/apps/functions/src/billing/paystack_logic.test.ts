import * as crypto from 'crypto';

import {
  addMonths,
  computeNewExpiryMs,
  hasActivePaystackEntitlement,
  isAllowedCallbackUrl,
  LIFETIME_MS,
  RENEWAL_GRACE_MS,
  resolvePlanFromCharge,
  verifyPaystackSignature,
} from './paystack_logic';

describe('verifyPaystackSignature', () => {
  const secret = 'sk_test_abc';
  const body = JSON.stringify({ event: 'charge.success', data: { reference: 'r1' } });
  const good = crypto.createHmac('sha512', secret).update(body).digest('hex');

  it('accepts a correct signature', () => {
    expect(verifyPaystackSignature(Buffer.from(body), good, secret)).toBe(true);
  });
  it('rejects a tampered body', () => {
    expect(verifyPaystackSignature(body + ' ', good, secret)).toBe(false);
  });
  it('rejects missing signature or secret', () => {
    expect(verifyPaystackSignature(body, undefined, secret)).toBe(false);
    expect(verifyPaystackSignature(body, good, '')).toBe(false);
  });
});

describe('addMonths', () => {
  it('clamps month ends', () => {
    expect(new Date(addMonths(Date.UTC(2026, 0, 31), 1)).toISOString()).toBe(
      '2026-02-28T00:00:00.000Z',
    );
  });
  it('adds 12 months', () => {
    expect(new Date(addMonths(Date.UTC(2026, 9, 15), 12)).toISOString()).toBe(
      '2027-10-15T00:00:00.000Z',
    );
  });
});

describe('computeNewExpiryMs', () => {
  const now = Date.UTC(2026, 9, 15);
  it('monthly from free', () => {
    expect(computeNewExpiryMs({ plan: 'monthly', currentExpiryMs: null, nowMs: now })).toBe(
      Date.UTC(2026, 10, 15) + RENEWAL_GRACE_MS,
    );
  });
  it('renewal stacks on remaining time', () => {
    const current = Date.UTC(2026, 9, 20);
    expect(computeNewExpiryMs({ plan: 'monthly', currentExpiryMs: current, nowMs: now })).toBe(
      Date.UTC(2026, 10, 20) + RENEWAL_GRACE_MS,
    );
  });
  it('expired entitlement restarts from now', () => {
    expect(
      computeNewExpiryMs({ plan: 'yearly', currentExpiryMs: Date.UTC(2025, 0, 1), nowMs: now }),
    ).toBe(Date.UTC(2027, 9, 15) + RENEWAL_GRACE_MS);
  });
  it('lifetime', () => {
    expect(computeNewExpiryMs({ plan: 'lifetime', currentExpiryMs: null, nowMs: now })).toBe(
      now + LIFETIME_MS,
    );
  });
});

describe('resolvePlanFromCharge', () => {
  const planCodes = { monthly: 'PLN_m', yearly: 'PLN_y' };
  it('uses plan code for renewals without metadata', () => {
    expect(resolvePlanFromCharge({ metadataPlan: undefined, planCode: 'PLN_y', planCodes })).toBe(
      'yearly',
    );
  });
  it('falls back to metadata', () => {
    expect(resolvePlanFromCharge({ metadataPlan: 'lifetime', planCode: null, planCodes })).toBe(
      'lifetime',
    );
  });
  it('rejects unknown', () => {
    expect(resolvePlanFromCharge({ metadataPlan: 'x', planCode: 'PLN_other', planCodes })).toBe(
      null,
    );
  });
});

describe('hasActivePaystackEntitlement', () => {
  const now = 1_000_000;
  const ts = (ms: number) => ({ toMillis: () => ms });
  it('true for active paystack', () => {
    expect(
      hasActivePaystackEntitlement(
        { premiumSource: 'paystack', premiumStatus: 'premium', premiumExpiry: ts(now + 1) },
        now,
      ),
    ).toBe(true);
  });
  it('false when expired or other source', () => {
    expect(
      hasActivePaystackEntitlement(
        { premiumSource: 'paystack', premiumStatus: 'premium', premiumExpiry: ts(now - 1) },
        now,
      ),
    ).toBe(false);
    expect(
      hasActivePaystackEntitlement(
        { premiumSource: 'revenuecat', premiumStatus: 'premium', premiumExpiry: null },
        now,
      ),
    ).toBe(false);
  });
});

describe('isAllowedCallbackUrl', () => {
  it('allows whitelisted https origin', () => {
    expect(isAllowedCallbackUrl('https://app.x.com/paywall?a=1', ['https://app.x.com'])).toBe(true);
  });
  it('blocks other origins and http', () => {
    expect(isAllowedCallbackUrl('https://evil.com/', ['https://app.x.com'])).toBe(false);
    expect(isAllowedCallbackUrl('http://app.x.com/', ['http://app.x.com'])).toBe(false);
  });
  it('allows localhost for dev', () => {
    expect(isAllowedCallbackUrl('http://localhost:5000/', [])).toBe(true);
  });
});
