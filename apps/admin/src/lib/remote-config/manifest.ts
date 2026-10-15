/**
 * The Remote Config manifest — which keys exist, what actually reads them, and
 * what counts as a legal value.
 *
 * Deliberately NOT `server-only`: this is pure data plus pure validators, so
 * the editor's client component and the unit tests can both import it.
 *
 * GROUND RULE — every entry below was verified against the shipped code, not
 * against PRD §9. Where the two disagree the CODE wins and the disagreement is
 * recorded in `note`. That is the point of this file: an operator editing a key
 * that nothing reads has been misled by the documentation, and quietly omitting
 * such a key would hide the problem instead of surfacing it.
 *
 * Verification method, re-runnable in one step:
 *   grep -rn '<key>' apps/functions/src apps/mobile/lib
 * `readSites` records every hit as `path:line` from that pass.
 *
 * What reads what, in summary:
 *   - Cloud Functions read RC in exactly ONE place,
 *     `apps/functions/src/providers/select_provider.ts`, and only ever look at
 *     a parameter's `defaultValue`. Conditions and percentage rollouts have no
 *     server-side effect whatsoever.
 *   - The mobile client registers in-app defaults in
 *     `apps/mobile/lib/core/config/remote_config_init.dart` and reads keys at
 *     the call sites listed per entry.
 */

export type RcType = 'string' | 'int' | 'bool';

/**
 * Which surface actually consumes the key.
 *
 * `none` is not a filler value — it is the single most useful thing this
 * manifest records. TWELVE of the twenty-one keys PRD §9 documents are read by
 * nothing at all, and an operator setting one of them would otherwise expect a
 * behaviour change that can never arrive. (The count is asserted in
 * manifest.test.ts so this comment cannot quietly go stale.)
 */
export type RcReadBy = 'server' | 'client' | 'none';

export interface RcKeyDef {
  readonly name: string;
  readonly type: RcType;
  /**
   * The value the shipped code falls back to when the key is absent. Remote
   * Config stores every value as a string, so this is the string form even for
   * ints and bools.
   */
  readonly defaultValue: string;
  readonly description: string;
  readonly readBy: RcReadBy;
  /** `path:line` evidence for `readBy`. Empty when nothing reads the key. */
  readonly readSites: readonly string[];
  /** A discrepancy, trap, or caveat the operator needs before editing. */
  readonly note?: string;
  /**
   * The complete set of legal values, when there is one. The editor renders a
   * picker instead of a free-text field — the only way to be sure a value the
   * server would silently ignore never gets typed in the first place.
   */
  readonly choices?: readonly string[];
  /** Returns an error message, or null when [raw] is acceptable. */
  validate(raw: string): string | null;
}

/* ---------------------------------------------------------- validators --- */

/** Anything goes, empty included — an unset string key is a meaningful state. */
function anyString(): (raw: string) => string | null {
  return () => null;
}

/**
 * Strict integer.
 *
 * Rejects `5.0`, `1e3`, and ` 5 ` even though the server's `Number(raw)` would
 * happily parse all three: the mobile client reads these through the platform
 * SDK's `getInt`, which parses strictly and silently falls back to the in-app
 * default on anything it cannot read. A value the two runtimes disagree about
 * is worse than no value at all.
 */
function integer(opts: { min: number; max?: number }) {
  return (raw: string): string | null => {
    if (!/^-?\d+$/.test(raw)) {
      return 'Must be a whole number in plain digits — no decimal point, exponent, or surrounding spaces.';
    }
    const n = Number(raw);
    if (n < opts.min) return `Must be ${opts.min} or greater.`;
    if (opts.max != null && n > opts.max) return `Must be ${opts.max} or less.`;
    return null;
  };
}

/**
 * Boolean, restricted to the four spellings that mean the same thing on both
 * platforms.
 *
 * Android's SDK also accepts `yes`/`y`/`t`/`on`; iOS accepts some of those and
 * not others. Rather than encode that asymmetry we reject everything outside
 * the unambiguous set — a key that resolves true on one platform and false on
 * the other is a bug nobody finds quickly.
 */
function boolean(raw: string): string | null {
  const v = raw.toLowerCase();
  if (v === 'true' || v === 'false' || v === '1' || v === '0') return null;
  return 'Must be "true" or "false".';
}

/**
 * `ai_provider`. Empty is legal and means "unset" — `selectProvider` then
 * leaves each callable on its own `featureDefault`, which is the shipped
 * intent. Any other string is silently ignored by the server, so it is a
 * misconfiguration rather than an override and we refuse to publish it.
 */
function providerName(raw: string): string | null {
  if (raw === '' || raw === 'openai' || raw === 'gemini') return null;
  return 'Must be "openai", "gemini", or empty. Any other value is ignored by the server, leaving each callable on its own default.';
}

/** AdMob ad unit id, or empty for "not configured". */
function admobUnitId(raw: string): string | null {
  if (raw === '') return null;
  if (!/^ca-app-pub-\d+\/\d+$/.test(raw)) {
    return 'Must look like ca-app-pub-0000000000000000/0000000000, or be empty.';
  }
  return null;
}

/**
 * RevenueCat **public SDK** key. The `appl_` / `goog_` prefix check exists to
 * catch the two mistakes that actually happen: pasting the iOS key into the
 * Android slot, and pasting the secret REST key (`sk_…`) into a slot the mobile
 * app ships to devices.
 */
function revenueCatKey(prefix: 'appl_' | 'goog_') {
  return (raw: string): string | null => {
    if (raw === '') return null;
    if (raw.startsWith('sk_')) {
      return 'That is a RevenueCat SECRET key. Only the public SDK key belongs here — this value ships inside the app.';
    }
    if (!raw.startsWith(prefix)) {
      return `Must start with "${prefix}" — this is the public SDK key for that platform.`;
    }
    return null;
  };
}

function httpUrl(raw: string): string | null {
  if (raw === '') return null;
  if (!/^https?:\/\/\S+$/.test(raw)) {
    return 'Must be an http(s) URL, or empty.';
  }
  return null;
}

function emailAddress(raw: string): string | null {
  if (raw === '') return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw)) {
    return 'Must be an email address, or empty.';
  }
  return null;
}

/** ISO 4217 alphabetic code. */
function currencyCode(raw: string): string | null {
  if (raw === '') return null;
  if (!/^[A-Z]{3}$/.test(raw)) {
    return 'Must be a 3-letter uppercase ISO 4217 code (e.g. USD), or empty.';
  }
  return null;
}

/* ------------------------------------------------------------- manifest --- */

/**
 * A trap shared by three of the client-read ceilings: the Flutter call sites
 * all read `limit > 0 ? limit : <hardcoded fallback>`, so publishing 0 does NOT
 * mean "zero allowed" — it silently restores the built-in default. The
 * validators below therefore require 1 or greater.
 *
 * `free_tier_ai_quota` is the exception and is genuinely different: the server
 * applies whatever number it reads, so 0 there really does block every
 * free-tier AI call. See the note on that entry.
 */
const CLIENT_CEILING_TRAP =
  'The client reads this as `limit > 0 ? limit : fallback`, so 0 does not mean "none allowed" — it silently reverts to the built-in default.';

export const RC_MANIFEST: readonly RcKeyDef[] = [
  /* ---- AI -------------------------------------------------------------- */
  {
    name: 'ai_provider',
    type: 'string',
    defaultValue: '',
    description:
      'Global override for which AI provider every callable uses. Unset means each callable keeps its own per-feature default.',
    readBy: 'server',
    readSites: ['apps/functions/src/providers/select_provider.ts:21'],
    note: 'PRD §9 documents the default as "openai"; the shipped code has no global default at all. Unset, receipt scanning uses gpt-4o and the other eight callables use gemini-2.5-flash-lite. The mobile app registers "gemini" as an in-app default but never reads the key — that default is inert.',
    choices: ['', 'openai', 'gemini'],
    validate: providerName,
  },
  {
    name: 'ai_model_chat',
    type: 'string',
    defaultValue: 'gpt-4o-mini',
    description:
      'Documented as the chat model selector. Nothing reads it — model names are hardcoded per callable.',
    readBy: 'none',
    readSites: [],
    note: 'No read site anywhere. Each callable picks its own model inline, e.g. apps/functions/src/ai/coach_chat.ts:99. Changing this key has no effect; changing the model means editing those files.',
    validate: anyString(),
  },
  {
    name: 'ai_model_vision',
    type: 'string',
    defaultValue: 'gpt-4o',
    description:
      'Documented as the receipt-scanning vision model selector. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site anywhere. apps/functions/src/ai/scan_receipt.ts:58 hardcodes gpt-4o (or gemini-2.5-flash when ai_provider forces gemini).',
    validate: anyString(),
  },

  /* ---- Free-tier ceilings ---------------------------------------------- */
  {
    name: 'free_tier_wallets_max',
    type: 'int',
    defaultValue: '1',
    description:
      'How many wallets a free user may create. Premium users skip the check.',
    readBy: 'client',
    readSites: [
      'apps/mobile/lib/features/wallets/providers/wallets_controller.dart:57',
    ],
    note: `Client-enforced, not server-enforced — the Drift write path is offline-first, so there is no callable to gate. A modified build can ignore it. ${CLIENT_CEILING_TRAP}`,
    validate: integer({ min: 1 }),
  },
  {
    name: 'free_tier_transactions_monthly',
    type: 'int',
    defaultValue: '100',
    description:
      'How many transactions a free user may add per calendar month.',
    readBy: 'client',
    readSites: [
      'apps/mobile/lib/features/transactions/providers/transactions_controller.dart:48',
    ],
    note: `Client-enforced, and counted against the DEVICE's local month while server counters use UTC — the two disagree near a month boundary. ${CLIENT_CEILING_TRAP}`,
    validate: integer({ min: 1 }),
  },
  {
    name: 'free_tier_ai_quota',
    type: 'int',
    defaultValue: '5',
    description:
      'Monthly ceiling shared by all nine AI counters for free users. Server-enforced; premium bypasses it entirely.',
    readBy: 'server',
    readSites: ['apps/functions/src/quota/check_quota.ts:31'],
    note: 'THIS is the key the code reads. PRD §9 documents the name as `free_tier_ai_actions_monthly`, which nothing reads — see that entry. Unlike the client ceilings, 0 here is honoured literally and blocks every free-tier AI call.',
    validate: integer({ min: 0 }),
  },
  {
    name: 'free_tier_ai_actions_monthly',
    type: 'int',
    defaultValue: '5',
    description:
      "PRD §9's name for the monthly AI ceiling. Nothing reads it — the shipped code reads `free_tier_ai_quota`.",
    readBy: 'none',
    readSites: [],
    note: 'Dead key, listed so it is visible if a buyer set it expecting it to work. `checkAndIncrementQuota` reads `free_tier_ai_quota` and nothing else. Setting this changes nothing.',
    validate: integer({ min: 0 }),
  },

  /* ---- Monetization ---------------------------------------------------- */
  {
    name: 'revenuecat_api_key_ios',
    type: 'string',
    defaultValue: '',
    description:
      'RevenueCat public SDK key for iOS. Empty means the paywall renders its "not configured" state instead of loading offerings.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/data/sync/sync_lifecycle_provider.dart:84'],
    note: 'NOT documented in PRD §9, despite being required for purchases to work at all. Read after sign-in, not at cold start.',
    validate: revenueCatKey('appl_'),
  },
  {
    name: 'revenuecat_api_key_android',
    type: 'string',
    defaultValue: '',
    description:
      'RevenueCat public SDK key for Android. Empty means the paywall renders its "not configured" state.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/data/sync/sync_lifecycle_provider.dart:85'],
    note: 'NOT documented in PRD §9, despite being required for purchases to work at all.',
    validate: revenueCatKey('goog_'),
  },
  {
    name: 'premium_monthly_price',
    type: 'string',
    defaultValue: '$4.99',
    description:
      'Documented as a display price. Nothing reads it — the paywall shows the store price.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. apps/mobile/lib/features/billing/presentation/paywall_screen.dart:434 renders `package.storeProduct.priceString`, which comes from App Store / Play via RevenueCat. Real prices are changed there, not here.',
    validate: anyString(),
  },
  {
    name: 'premium_yearly_price',
    type: 'string',
    defaultValue: '$29.99',
    description:
      'Documented as a display price. Nothing reads it — the paywall shows the store price.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. See premium_monthly_price.',
    validate: anyString(),
  },
  {
    name: 'premium_lifetime_price',
    type: 'string',
    defaultValue: '$79.99',
    description:
      'Documented as a display price. Nothing reads it — the paywall shows the store price.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. See premium_monthly_price.',
    validate: anyString(),
  },

  /* ---- Ads ------------------------------------------------------------- */
  {
    name: 'ads_enabled',
    type: 'bool',
    defaultValue: 'false',
    description:
      'Kill switch for AdMob. Ads show only when this is true AND the user is not premium.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/features/ads/data/ads_service.dart:32'],
    note: 'PRD §9 documents the default as `true`; the app registers `false` (remote_config_init.dart:41), so a deployment that never sets this key shows no ads. The in-app default is authoritative.',
    validate: boolean,
  },
  {
    name: 'admob_banner_id_android',
    type: 'string',
    defaultValue: '',
    description: 'AdMob banner unit shown at the bottom of Home on Android.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/features/ads/data/ads_service.dart:36'],
    note: 'Use Google\'s test unit ca-app-pub-3940256099942544/6300978111 during development — serving live ads to your own test traffic risks the AdMob account.',
    validate: admobUnitId,
  },
  {
    name: 'admob_banner_id_ios',
    type: 'string',
    defaultValue: '',
    description: 'AdMob banner unit shown at the bottom of Home on iOS.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/features/ads/data/ads_service.dart:35'],
    validate: admobUnitId,
  },
  {
    name: 'admob_interstitial_id_android',
    type: 'string',
    defaultValue: '',
    description: 'AdMob interstitial unit fired after N transaction adds.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/features/ads/data/ads_service.dart:43'],
    validate: admobUnitId,
  },
  {
    name: 'admob_interstitial_id_ios',
    type: 'string',
    defaultValue: '',
    description: 'AdMob interstitial unit fired after N transaction adds.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/features/ads/data/ads_service.dart:41'],
    validate: admobUnitId,
  },
  {
    name: 'interstitial_frequency',
    type: 'int',
    defaultValue: '5',
    description:
      'Show an interstitial after every N successful transaction adds.',
    readBy: 'client',
    readSites: ['apps/mobile/lib/features/ads/data/ads_service.dart:49'],
    note: `${CLIENT_CEILING_TRAP} To stop interstitials entirely, clear admob_interstitial_id_* or set ads_enabled to false.`,
    validate: integer({ min: 1 }),
  },

  /* ---- Feature toggles & content --------------------------------------- */
  {
    name: 'weekly_recap_enabled',
    type: 'bool',
    defaultValue: 'true',
    description:
      'Documented as a toggle for the weekly recap. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. The weekly recap shipped as a LOCAL notification scheduled by notification_coordinator.dart, gated by a per-user SharedPreferences toggle — not by Remote Config. The FCM push variant this key was written for was deferred.',
    validate: boolean,
  },
  {
    name: 'anomaly_detection_enabled',
    type: 'bool',
    defaultValue: 'true',
    description:
      'Documented as a toggle for anomaly alerts. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. `detectAnomalies` is called from the insights screen with no RC gate; the only per-user control is the notification preference.',
    validate: boolean,
  },
  {
    name: 'default_currency',
    type: 'string',
    defaultValue: 'USD',
    description:
      'Documented as the app-wide default currency. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. Currency is chosen per user during setup and stored on the user document as `defaultCurrency`; every wallet then carries its own currency.',
    validate: currencyCode,
  },
  {
    name: 'support_email',
    type: 'string',
    defaultValue: '',
    description: 'Documented as the support contact. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. about_screen.dart hardcodes mailto:support@homa.finance. A buyer rebranding the app must edit that file — setting this key does nothing.',
    validate: emailAddress,
  },
  {
    name: 'privacy_policy_url',
    type: 'string',
    defaultValue: '',
    description: 'Documented as the privacy policy link. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. about_screen.dart:116 hardcodes https://homa.finance/privacy. Store review will reject an app pointing at the template author\'s policy, so this one is worth fixing in code.',
    validate: httpUrl,
  },
  {
    name: 'terms_url',
    type: 'string',
    defaultValue: '',
    description: 'Documented as the terms of service link. Nothing reads it.',
    readBy: 'none',
    readSites: [],
    note: 'No read site. about_screen.dart hardcodes https://homa.finance/terms. Same store-review caveat as privacy_policy_url.',
    validate: httpUrl,
  },
];

/* -------------------------------------------------------------- helpers --- */

const BY_NAME: ReadonlyMap<string, RcKeyDef> = new Map(
  RC_MANIFEST.map((k) => [k.name, k]),
);

export function rcKey(name: string): RcKeyDef | undefined {
  return BY_NAME.get(name);
}

export function isManifestKey(name: string): boolean {
  return BY_NAME.has(name);
}

/**
 * Validates a candidate value for [name].
 *
 * An unknown key is an error rather than a pass-through: the editor and the
 * route handler both funnel through here, and accepting a key nobody has
 * described would let a typo be published as a real parameter.
 */
export function validateRcValue(name: string, raw: string): string | null {
  const def = BY_NAME.get(name);
  if (!def) return `Unknown key "${name}".`;
  return def.validate(raw);
}

export const RC_READ_BY_ORDER: readonly RcReadBy[] = ['server', 'client', 'none'];

export const RC_READ_BY_LABEL: Readonly<Record<RcReadBy, string>> = {
  server: 'Read by Cloud Functions',
  client: 'Read by the mobile app',
  none: 'Read by nothing',
};

export const RC_READ_BY_BLURB: Readonly<Record<RcReadBy, string>> = {
  server:
    'Read from the template\'s defaultValue by apps/functions/src/providers/select_provider.ts. Each warm instance caches the whole template for its lifetime, so an edit reaches running instances only as they recycle.',
  client:
    'Fetched by the mobile app at startup. Release builds throttle to one fetch per hour, so an edit can take up to an hour plus a restart to reach a device.',
  none:
    'No code in apps/functions or apps/mobile reads these. They are documented in PRD §9 but inert — editing one changes nothing at runtime. Each entry records where the behaviour actually lives.',
};

/**
 * Remote Config's own type enum for each manifest type — used both to label a
 * parameter this panel creates and to spot a template that declares a
 * conflicting one.
 *
 * Typed as a literal union so it is structurally assignable to firebase-admin's
 * `ParameterValueType` without this pure module importing the SDK.
 */
export const RC_VALUE_TYPE: Readonly<
  Record<RcType, 'STRING' | 'NUMBER' | 'BOOLEAN'>
> = {
  string: 'STRING',
  int: 'NUMBER',
  bool: 'BOOLEAN',
};
