import { describe, expect, it } from 'vitest';

import {
  RC_MANIFEST,
  RC_READ_BY_ORDER,
  isManifestKey,
  rcKey,
  validateRcValue,
} from './manifest';

/** Throws rather than returning undefined so a renamed key fails loudly. */
function key(name: string) {
  const def = rcKey(name);
  if (!def) throw new Error(`manifest is missing "${name}"`);
  return def;
}

describe('manifest shape', () => {
  it('gives every key a type, a default, and a description', () => {
    for (const def of RC_MANIFEST) {
      expect(def.name, 'name').toMatch(/^[a-z0-9_]+$/);
      expect(RC_READ_BY_ORDER, def.name).toContain(def.readBy);
      expect(def.description.length, def.name).toBeGreaterThan(0);
      expect(typeof def.defaultValue, def.name).toBe('string');
      expect(typeof def.validate, def.name).toBe('function');
    }
  });

  it('has no duplicate key names', () => {
    const names = RC_MANIFEST.map((d) => d.name);
    expect(new Set(names).size).toBe(names.length);
  });

  /**
   * The documented default has to be publishable. A validator strict enough to
   * reject its own default would make the key uneditable through the panel,
   * which is exactly the kind of thing that only shows up in production.
   */
  it('accepts its own default for every key', () => {
    for (const def of RC_MANIFEST) {
      expect(def.validate(def.defaultValue), def.name).toBeNull();
    }
  });

  it('cites a read site for every key it claims is read, and none otherwise', () => {
    for (const def of RC_MANIFEST) {
      if (def.readBy === 'none') {
        expect(def.readSites, def.name).toHaveLength(0);
        // A dead key without an explanation is just a claim; the note is what
        // tells the operator where the behaviour actually lives.
        expect(def.note, def.name).toBeTruthy();
      } else {
        expect(def.readSites.length, def.name).toBeGreaterThan(0);
        for (const site of def.readSites) {
          expect(site, def.name).toMatch(/^apps\/(functions|mobile)\/.+:\d+$/);
        }
      }
    }
  });
});

/**
 * These pin the discrepancies between PRD §9 and the shipped code. If someone
 * later "fixes" the manifest to match the PRD without changing the code, these
 * fail — which is the intent.
 */
describe('PRD §9 vs shipped code', () => {
  it('treats free_tier_ai_quota as the key the server reads', () => {
    const def = key('free_tier_ai_quota');
    expect(def.readBy).toBe('server');
    expect(def.readSites).toContain(
      'apps/functions/src/quota/check_quota.ts:31',
    );
  });

  it('keeps the PRD-documented free_tier_ai_actions_monthly marked dead', () => {
    expect(key('free_tier_ai_actions_monthly').readBy).toBe('none');
  });

  it('carries the RevenueCat keys PRD §9 omits', () => {
    expect(key('revenuecat_api_key_ios').readBy).toBe('client');
    expect(key('revenuecat_api_key_android').readBy).toBe('client');
  });

  it('records the price keys as read by nothing', () => {
    for (const name of [
      'premium_monthly_price',
      'premium_yearly_price',
      'premium_lifetime_price',
    ]) {
      expect(key(name).readBy, name).toBe('none');
    }
  });

  it('defaults ads_enabled to the in-app default, not the PRD value', () => {
    // PRD §9 says true; remote_config_init.dart registers false.
    expect(key('ads_enabled').defaultValue).toBe('false');
  });

  /**
   * Pins the headline numbers quoted in this file's own doc comment and on the
   * /remote-config page. If a key gains or loses a read site, this fails and
   * forces the prose to be corrected with it.
   */
  it('holds 24 keys: 2 server-read, 10 client-read, 12 read by nothing', () => {
    const counts = { server: 0, client: 0, none: 0 };
    for (const def of RC_MANIFEST) counts[def.readBy] += 1;

    expect(RC_MANIFEST).toHaveLength(24);
    expect(counts).toEqual({ server: 2, client: 10, none: 12 });
  });
});

describe('ai_provider validation', () => {
  const v = (raw: string) => key('ai_provider').validate(raw);

  it('accepts the two provider names and empty', () => {
    expect(v('openai')).toBeNull();
    expect(v('gemini')).toBeNull();
    expect(v('')).toBeNull();
  });

  it('rejects anything the server would silently ignore', () => {
    // selectProvider compares the raw string, so case and padding matter.
    expect(v('OpenAI')).toBeTruthy();
    expect(v(' gemini')).toBeTruthy();
    expect(v('anthropic')).toBeTruthy();
  });
});

describe('integer ceilings', () => {
  it('rejects zero on the client ceilings, which silently means "default"', () => {
    expect(key('free_tier_wallets_max').validate('0')).toBeTruthy();
    expect(key('free_tier_transactions_monthly').validate('0')).toBeTruthy();
    expect(key('interstitial_frequency').validate('0')).toBeTruthy();
  });

  it('allows zero on the AI quota, where the server honours it literally', () => {
    expect(key('free_tier_ai_quota').validate('0')).toBeNull();
  });

  it('rejects negatives, decimals, exponents, and padding', () => {
    const v = (raw: string) => key('free_tier_wallets_max').validate(raw);
    expect(v('-1')).toBeTruthy();
    expect(v('1.0')).toBeTruthy();
    expect(v('1e3')).toBeTruthy();
    expect(v(' 3')).toBeTruthy();
    expect(v('3 ')).toBeTruthy();
    expect(v('three')).toBeTruthy();
    expect(v('')).toBeTruthy();
  });

  it('accepts plain positive integers', () => {
    expect(key('free_tier_transactions_monthly').validate('250')).toBeNull();
  });
});

describe('boolean validation', () => {
  const v = (raw: string) => key('ads_enabled').validate(raw);

  it('accepts the spellings both platforms agree on', () => {
    for (const raw of ['true', 'false', 'TRUE', 'False', '1', '0']) {
      expect(v(raw), raw).toBeNull();
    }
  });

  it('rejects spellings that resolve differently per platform, and junk', () => {
    // "on"/"off" are true/false on Android and neither on iOS.
    expect(v('on')).toBeTruthy();
    expect(v('yes')).toBeTruthy();
    expect(v('')).toBeTruthy();
    expect(v('maybe')).toBeTruthy();
  });
});

describe('AdMob unit ids', () => {
  const v = (raw: string) => key('admob_banner_id_android').validate(raw);

  it('accepts empty and the Google test unit', () => {
    expect(v('')).toBeNull();
    expect(v('ca-app-pub-3940256099942544/6300978111')).toBeNull();
  });

  it('rejects a bare publisher id or a mistyped unit', () => {
    expect(v('ca-app-pub-3940256099942544')).toBeTruthy();
    expect(v('pub-3940256099942544/6300978111')).toBeTruthy();
    expect(v('ca-app-pub-abc/def')).toBeTruthy();
  });
});

describe('RevenueCat keys', () => {
  it('enforces the per-platform prefix so the two cannot be swapped', () => {
    expect(key('revenuecat_api_key_ios').validate('appl_abc123')).toBeNull();
    expect(key('revenuecat_api_key_ios').validate('goog_abc123')).toBeTruthy();
    expect(key('revenuecat_api_key_android').validate('goog_abc')).toBeNull();
    expect(key('revenuecat_api_key_android').validate('appl_abc')).toBeTruthy();
  });

  it('names the secret key specifically, since it must never ship', () => {
    const err = key('revenuecat_api_key_ios').validate('sk_live_abc');
    expect(err).toContain('SECRET');
  });

  it('accepts empty as "not configured"', () => {
    expect(key('revenuecat_api_key_ios').validate('')).toBeNull();
  });
});

describe('content keys', () => {
  it('validates URLs', () => {
    expect(key('terms_url').validate('https://example.com/terms')).toBeNull();
    expect(key('terms_url').validate('')).toBeNull();
    expect(key('terms_url').validate('example.com/terms')).toBeTruthy();
  });

  it('validates the support email', () => {
    expect(key('support_email').validate('help@example.com')).toBeNull();
    expect(key('support_email').validate('help@example')).toBeTruthy();
    expect(key('support_email').validate('not an address')).toBeTruthy();
  });

  it('validates the currency code', () => {
    expect(key('default_currency').validate('KHR')).toBeNull();
    expect(key('default_currency').validate('usd')).toBeTruthy();
    expect(key('default_currency').validate('DOLLAR')).toBeTruthy();
  });
});

describe('validateRcValue', () => {
  it('refuses an unknown key rather than passing it through', () => {
    expect(validateRcValue('not_a_key', 'x')).toContain('Unknown key');
    expect(isManifestKey('not_a_key')).toBe(false);
  });

  it('dispatches to the key\'s own validator', () => {
    expect(validateRcValue('ai_provider', 'gemini')).toBeNull();
    expect(validateRcValue('ai_provider', 'nope')).toBeTruthy();
  });
});
