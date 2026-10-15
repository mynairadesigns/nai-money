import { detectSubscriptionCandidates, normalizeNote, type SubTxn } from './subscription_logic';

/** Helper: build a UTC Date N days after a base epoch. */
function daysAfter(baseMs: number, days: number): Date {
  return new Date(baseMs + days * 24 * 60 * 60 * 1000);
}

/** Helper: build a list of N monthly-spaced transactions (30 d apart). */
function monthlyTxns(n: number, overrides: Partial<SubTxn> = {}): SubTxn[] {
  const base = Date.UTC(2026, 0, 1); // 2026-01-01
  return Array.from({ length: n }, (_, i) => ({
    id: `tx-monthly-${i}`,
    note: 'Netflix',
    amount: 15.99,
    currency: 'USD',
    date: daysAfter(base, i * 30),
    ...overrides,
  }));
}

/** Helper: build a list of N weekly-spaced transactions (7 d apart). */
function weeklyTxns(n: number, overrides: Partial<SubTxn> = {}): SubTxn[] {
  const base = Date.UTC(2026, 0, 1);
  return Array.from({ length: n }, (_, i) => ({
    id: `tx-weekly-${i}`,
    note: 'Spotify',
    amount: 9.99,
    currency: 'USD',
    date: daysAfter(base, i * 7),
    ...overrides,
  }));
}

describe('detectSubscriptionCandidates', () => {
  // ── monthly cadence ───────────────────────────────────────────────────────

  it('3 monthly-spaced transactions → 1 monthly candidate', () => {
    const txns = monthlyTxns(3);
    const results = detectSubscriptionCandidates(txns);
    expect(results).toHaveLength(1);
    expect(results[0].frequency).toBe('monthly');
    expect(results[0].occurrences).toBe(3);
    expect(results[0].merchant).toBe('Netflix');
    expect(results[0].amount).toBe(15.99);
    expect(results[0].currency).toBe('USD');
  });

  it('5 monthly-spaced transactions → 1 monthly candidate with 5 occurrences', () => {
    const txns = monthlyTxns(5);
    const results = detectSubscriptionCandidates(txns);
    expect(results).toHaveLength(1);
    expect(results[0].occurrences).toBe(5);
    expect(results[0].sampleTransactionIds).toHaveLength(5);
  });

  it('sampleTransactionIds contains last 5 entries (most recent)', () => {
    const txns = monthlyTxns(7); // 7 entries — last 5 should be indices 2–6
    const results = detectSubscriptionCandidates(txns);
    const expectedIds = txns.slice(2).map((t) => t.id);
    expect(results[0].sampleTransactionIds).toEqual(expectedIds);
  });

  // ── weekly cadence ────────────────────────────────────────────────────────

  it('3 weekly-spaced transactions → 1 weekly candidate', () => {
    const txns = weeklyTxns(3);
    const results = detectSubscriptionCandidates(txns);
    expect(results).toHaveLength(1);
    expect(results[0].frequency).toBe('weekly');
    expect(results[0].occurrences).toBe(3);
    expect(results[0].merchant).toBe('Spotify');
  });

  // ── below minimum occurrences ─────────────────────────────────────────────

  it('2 occurrences only → no candidates (below MIN_OCCURRENCES=3)', () => {
    const txns = monthlyTxns(2);
    expect(detectSubscriptionCandidates(txns)).toHaveLength(0);
  });

  it('1 occurrence → no candidates', () => {
    const txns = monthlyTxns(1);
    expect(detectSubscriptionCandidates(txns)).toHaveLength(0);
  });

  // ── irregular gaps ────────────────────────────────────────────────────────

  it('irregular gaps (5 d, 50 d) → no candidates', () => {
    const base = Date.UTC(2026, 0, 1);
    const txns: SubTxn[] = [
      { id: 't1', note: 'WeirdShop', amount: 10, currency: 'USD', date: daysAfter(base, 0) },
      { id: 't2', note: 'WeirdShop', amount: 10, currency: 'USD', date: daysAfter(base, 5) },
      { id: 't3', note: 'WeirdShop', amount: 10, currency: 'USD', date: daysAfter(base, 55) },
    ];
    expect(detectSubscriptionCandidates(txns)).toHaveLength(0);
  });

  // ── two distinct merchants ────────────────────────────────────────────────

  it('two distinct merchants each with 3 monthly txns → 2 candidates', () => {
    const base = Date.UTC(2026, 0, 1);
    const netflix: SubTxn[] = Array.from({ length: 3 }, (_, i) => ({
      id: `nf-${i}`,
      note: 'Netflix',
      amount: 15.99,
      currency: 'USD',
      date: daysAfter(base, i * 30),
    }));
    const spotify: SubTxn[] = Array.from({ length: 3 }, (_, i) => ({
      id: `sp-${i}`,
      note: 'Spotify',
      amount: 9.99,
      currency: 'USD',
      date: daysAfter(base, i * 30),
    }));
    const results = detectSubscriptionCandidates([...netflix, ...spotify]);
    expect(results).toHaveLength(2);
    const merchants = new Set(results.map((r) => r.merchant));
    expect(merchants.has('Netflix')).toBe(true);
    expect(merchants.has('Spotify')).toBe(true);
  });

  it('same merchant, different amounts → two separate candidates', () => {
    const base = Date.UTC(2026, 0, 1);
    const cheap: SubTxn[] = Array.from({ length: 3 }, (_, i) => ({
      id: `c-${i}`,
      note: 'Amazon',
      amount: 5,
      currency: 'USD',
      date: daysAfter(base, i * 30),
    }));
    const premium: SubTxn[] = Array.from({ length: 3 }, (_, i) => ({
      id: `p-${i}`,
      note: 'Amazon',
      amount: 14.99,
      currency: 'USD',
      date: daysAfter(base, i * 30),
    }));
    const results = detectSubscriptionCandidates([...cheap, ...premium]);
    expect(results).toHaveLength(2);
    const amounts = new Set(results.map((r) => r.amount));
    expect(amounts.has(5)).toBe(true);
    expect(amounts.has(14.99)).toBe(true);
  });

  // ── candidateId stability ─────────────────────────────────────────────────

  it('candidateId is stable/deterministic for the same inputs', () => {
    const txns1 = monthlyTxns(3);
    const txns2 = monthlyTxns(3);
    const [id1] = detectSubscriptionCandidates(txns1).map((c) => c.candidateId);
    const [id2] = detectSubscriptionCandidates(txns2).map((c) => c.candidateId);
    expect(id1).toBe(id2);
    expect(typeof id1).toBe('string');
    expect(id1).toHaveLength(16);
  });

  it('candidateId differs for different merchants', () => {
    const netflix = monthlyTxns(3, { note: 'Netflix', id: 'nf' });
    const hulu = monthlyTxns(3, { note: 'Hulu', id: 'hu' });
    // give each its own ids
    netflix.forEach((t, i) => { t.id = `nf-${i}`; });
    hulu.forEach((t, i) => { t.id = `hu-${i}`; });
    const r1 = detectSubscriptionCandidates(netflix);
    const r2 = detectSubscriptionCandidates(hulu);
    expect(r1[0].candidateId).not.toBe(r2[0].candidateId);
  });

  // ── sorting (occurrences descending) ──────────────────────────────────────

  it('results are sorted by occurrences descending', () => {
    const base = Date.UTC(2026, 0, 1);
    // 4 Netflix monthly, 3 Spotify monthly
    const netflix: SubTxn[] = Array.from({ length: 4 }, (_, i) => ({
      id: `nf-${i}`,
      note: 'Netflix',
      amount: 15.99,
      currency: 'USD',
      date: daysAfter(base, i * 30),
    }));
    const spotify: SubTxn[] = Array.from({ length: 3 }, (_, i) => ({
      id: `sp-${i}`,
      note: 'Spotify',
      amount: 9.99,
      currency: 'USD',
      date: daysAfter(base, i * 30),
    }));
    const results = detectSubscriptionCandidates([...netflix, ...spotify]);
    expect(results[0].occurrences).toBeGreaterThanOrEqual(results[1].occurrences);
    expect(results[0].merchant).toBe('Netflix');
  });

  // ── edge: empty input ─────────────────────────────────────────────────────

  it('empty transaction list → empty candidates', () => {
    expect(detectSubscriptionCandidates([])).toHaveLength(0);
  });

  // ── edge: invalid date is skipped ─────────────────────────────────────────

  it('transactions with invalid date are skipped', () => {
    const base = Date.UTC(2026, 0, 1);
    const valid = monthlyTxns(3);
    const invalid: SubTxn = {
      id: 'bad',
      note: 'Netflix',
      amount: 15.99,
      currency: 'USD',
      date: new Date('not-a-date'),
    };
    // Only 3 valid + 1 invalid — still 3 valid occurrences.
    const results = detectSubscriptionCandidates([...valid, invalid]);
    expect(results).toHaveLength(1);
    expect(results[0].occurrences).toBe(3);

    void base; // suppress unused warning
  });
});

describe('normalizeNote', () => {
  it('lowercases and collapses non-alphanumeric runs', () => {
    expect(normalizeNote('Netflix Premium!')).toBe('netflix premium');
    expect(normalizeNote('  Spotify  ')).toBe('spotify');
    expect(normalizeNote('HBO Max')).toBe('hbo max');
    expect(normalizeNote('123 Corp.')).toBe('123 corp');
  });

  it('returns empty string for blank input', () => {
    expect(normalizeNote('')).toBe('');
    expect(normalizeNote('   ')).toBe('');
  });
});
