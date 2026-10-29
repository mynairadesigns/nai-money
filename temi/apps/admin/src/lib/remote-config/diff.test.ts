import { describe, expect, it } from 'vitest';

import {
  changesToAuditPayload,
  computeChanges,
  computeDrift,
  summarizeDrift,
  validateChanges,
  type LiveParameter,
} from './diff';
import { RC_MANIFEST, validateRcValue } from './manifest';

/** A live parameter with an explicit value, defaults for the rest. */
function param(value: string | null, extra: Partial<LiveParameter> = {}): LiveParameter {
  return {
    value,
    usesInAppDefault: false,
    hasConditionalValues: false,
    valueType: null,
    ...extra,
  };
}

const AI_PROVIDER = RC_MANIFEST.find((d) => d.name === 'ai_provider')!;
const WALLETS = RC_MANIFEST.find((d) => d.name === 'free_tier_wallets_max')!;

describe('computeDrift', () => {
  it('flags a parameter carrying conditional values', () => {
    // The whole reason this matters: Cloud Functions read defaultValue only,
    // so a condition on a server-read key silently does nothing.
    const findings = computeDrift(
      [AI_PROVIDER],
      new Map([['ai_provider', param('openai', { hasConditionalValues: true })]]),
    );
    expect(findings.some((f) => f.kind === 'conditional')).toBe(true);
  });

  it('flags a value the manifest validator rejects', () => {
    const findings = computeDrift(
      [AI_PROVIDER],
      new Map([['ai_provider', param('claude')]]),
    );
    const invalid = findings.find((f) => f.kind === 'invalid-value');
    expect(invalid?.severity).toBe('error');
  });

  it('flags a key present in the template but absent from the manifest', () => {
    const findings = computeDrift(
      [AI_PROVIDER],
      new Map([
        ['ai_provider', param('openai')],
        ['ai_provdier', param('gemini')], // a realistic typo
      ]),
    );
    expect(findings.find((f) => f.kind === 'unknown-key')?.key).toBe('ai_provdier');
  });

  it('reports a key that defers to the in-app default', () => {
    const findings = computeDrift(
      [WALLETS],
      new Map([['free_tier_wallets_max', param(null, { usesInAppDefault: true })]]),
    );
    expect(findings.some((f) => f.kind === 'in-app-default')).toBe(true);
  });

  it('does not treat an unset key as an error', () => {
    // Every read site has a hardcoded fallback, so absent is the normal state
    // of a fresh project — noisy errors here would train operators to ignore it.
    const findings = computeDrift([WALLETS], new Map());
    expect(findings.every((f) => f.severity !== 'error')).toBe(true);
  });

  it('summarises by severity', () => {
    const findings = computeDrift(
      [AI_PROVIDER, WALLETS],
      new Map([['ai_provider', param('nonsense')]]),
    );
    const summary = summarizeDrift(findings);
    expect(summary.errors).toBeGreaterThan(0);
    expect(summary.errors + summary.warnings + summary.infos).toBe(findings.length);
  });
});

describe('computeChanges', () => {
  const live = new Map([
    ['ai_provider', param('gemini')],
    ['free_tier_wallets_max', param('1')],
  ]);

  it('keeps only values that actually differ', () => {
    const changes = computeChanges(
      live,
      new Map([
        ['ai_provider', 'openai'],
        ['free_tier_wallets_max', '1'], // unchanged — must be dropped
      ]),
    );
    expect(changes).toHaveLength(1);
    expect(changes[0]).toMatchObject({
      key: 'ai_provider',
      before: 'gemini',
      after: 'openai',
      creates: false,
    });
  });

  it('marks a key absent from the template as created', () => {
    const changes = computeChanges(live, new Map([['support_email', 'a@b.com']]));
    expect(changes[0]).toMatchObject({ before: null, creates: true });
  });

  it('treats an in-app-default parameter as a creation', () => {
    // There is no defaultValue to replace, so publishing genuinely adds one.
    const changes = computeChanges(
      new Map([['free_tier_ai_quota', param(null, { usesInAppDefault: true })]]),
      new Map([['free_tier_ai_quota', '10']]),
    );
    expect(changes[0].creates).toBe(true);
  });

  it('is empty when nothing was touched', () => {
    expect(computeChanges(live, new Map())).toEqual([]);
  });

  it('orders deterministically so diff, audit, and publish agree', () => {
    const changes = computeChanges(
      new Map(),
      new Map([
        ['terms_url', 'https://z'],
        ['ads_enabled', 'true'],
        ['support_email', 'a@b.com'],
      ]),
    );
    expect(changes.map((c) => c.key)).toEqual([
      'ads_enabled',
      'support_email',
      'terms_url',
    ]);
  });
});

describe('validateChanges', () => {
  it('reports the offending key with the validator message', () => {
    const changes = computeChanges(
      new Map(),
      new Map([
        ['ai_provider', 'claude'],
        ['free_tier_wallets_max', '3'],
      ]),
    );
    const errors = validateChanges(changes, validateRcValue);
    expect(errors.has('ai_provider')).toBe(true);
    expect(errors.has('free_tier_wallets_max')).toBe(false);
  });

  it('rejects an unknown key rather than letting it through', () => {
    const changes = computeChanges(new Map(), new Map([['made_up_key', 'x']]));
    expect(validateChanges(changes, validateRcValue).has('made_up_key')).toBe(true);
  });

  it('passes a clean change set', () => {
    const changes = computeChanges(new Map(), new Map([['ai_provider', 'openai']]));
    expect(validateChanges(changes, validateRcValue).size).toBe(0);
  });
});

describe('changesToAuditPayload', () => {
  it('splits into before and after maps', () => {
    const changes = computeChanges(
      new Map([['ai_provider', param('gemini')]]),
      new Map([
        ['ai_provider', 'openai'],
        ['support_email', 'a@b.com'],
      ]),
    );
    const { before, after } = changesToAuditPayload(changes);
    expect(before).toEqual({ ai_provider: 'gemini', support_email: null });
    expect(after).toEqual({ ai_provider: 'openai', support_email: 'a@b.com' });
  });
});
