import { evaluateQuota } from './quota_logic';

const NOW_MS = Date.UTC(2026, 4, 25, 12, 0, 0); // 2026-05-25 12:00 UTC (fixed clock)
const FUTURE_MS = NOW_MS + 30 * 24 * 60 * 60 * 1000; // 30 days from now
const PAST_MS = NOW_MS - 1; // 1 ms in the past

describe('evaluateQuota — premium bypass', () => {
  it('active premium (status=premium, expiry in future) → bypass', () => {
    const result = evaluateQuota({
      premiumStatus: 'premium',
      premiumExpiryMs: FUTURE_MS,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    expect(result.action).toBe('bypass');
  });

  it('premium with expiry in the past → NOT bypass (expired)', () => {
    const result = evaluateQuota({
      premiumStatus: 'premium',
      premiumExpiryMs: PAST_MS,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    // Expired premium falls through to free-tier logic.
    expect(result.action).toBe('increment');
  });

  it('null expiry + premium status → NOT bypass (lifetime null is not bypassed)', () => {
    // Matches server behaviour: requires `premiumExpiry instanceof Timestamp`.
    // Null expiry → not premium → ceiling applies.
    const result = evaluateQuota({
      premiumStatus: 'premium',
      premiumExpiryMs: null,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    expect(result.action).toBe('increment');
  });

  it('undefined expiry + premium status → NOT bypass', () => {
    const result = evaluateQuota({
      premiumStatus: 'premium',
      premiumExpiryMs: undefined,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    expect(result.action).toBe('increment');
  });

  it('active expiry but status is not "premium" → NOT bypass', () => {
    const result = evaluateQuota({
      premiumStatus: 'free',
      premiumExpiryMs: FUTURE_MS,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    expect(result.action).toBe('increment');
  });

  it('undefined status + future expiry → NOT bypass', () => {
    const result = evaluateQuota({
      premiumStatus: undefined,
      premiumExpiryMs: FUTURE_MS,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    expect(result.action).toBe('increment');
  });
});

describe('evaluateQuota — free-tier increment', () => {
  it('under limit (currentCount=0, limit=5) → increment', () => {
    const result = evaluateQuota({
      premiumStatus: undefined,
      premiumExpiryMs: null,
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 5,
    });
    expect(result.action).toBe('increment');
  });

  it('exactly at limit - 1 (currentCount=4, limit=5) → increment (4+1=5 == limit, allowed)', () => {
    const result = evaluateQuota({
      nowMs: NOW_MS,
      currentCount: 4,
      limit: 5,
    });
    // 4 + 1 = 5 <= 5 → allowed
    expect(result.action).toBe('increment');
  });

  it('limit=1, currentCount=0 → increment', () => {
    const result = evaluateQuota({
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 1,
    });
    expect(result.action).toBe('increment');
  });
});

describe('evaluateQuota — free-tier reject', () => {
  it('at ceiling (currentCount=5, limit=5) → reject (5+1=6 > 5)', () => {
    const result = evaluateQuota({
      nowMs: NOW_MS,
      currentCount: 5,
      limit: 5,
    });
    expect(result.action).toBe('reject');
  });

  it('above ceiling (currentCount=10, limit=5) → reject', () => {
    const result = evaluateQuota({
      nowMs: NOW_MS,
      currentCount: 10,
      limit: 5,
    });
    expect(result.action).toBe('reject');
  });

  it('limit=0, currentCount=0 → reject (0+1=1 > 0)', () => {
    const result = evaluateQuota({
      nowMs: NOW_MS,
      currentCount: 0,
      limit: 0,
    });
    expect(result.action).toBe('reject');
  });
});

describe('evaluateQuota — premium bypasses ceiling entirely', () => {
  it('premium + at ceiling → bypass (not reject)', () => {
    const result = evaluateQuota({
      premiumStatus: 'premium',
      premiumExpiryMs: FUTURE_MS,
      nowMs: NOW_MS,
      currentCount: 1000,
      limit: 5,
    });
    expect(result.action).toBe('bypass');
  });
});
