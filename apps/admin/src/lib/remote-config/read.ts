import 'server-only';

import { adminRemoteConfig } from '@/lib/firebase/admin';

/**
 * Read-side access to Remote Config.
 *
 * IMPORTANT — this deliberately mirrors the SERVER's semantics, not the mobile
 * client's. `apps/functions/src/providers/select_provider.ts` reads only a
 * parameter's `defaultValue`, so RC *conditions* and percentage rollouts have
 * no effect on Cloud Functions. The panel must show operators the value their
 * backend actually sees, not a conditional variant that never applies.
 *
 * Cached per request rather than per process: an operator editing a key
 * (Phase 5) needs to see the change on the next page load, unlike the
 * Functions runtime which caches for the life of an instance.
 */
export interface RcTemplateValues {
  values: Map<string, string>;
  /** Parameters carrying conditional values — those the server ignores. */
  conditional: Set<string>;
  etag: string | null;
}

export async function readRemoteConfig(): Promise<RcTemplateValues> {
  const values = new Map<string, string>();
  const conditional = new Set<string>();

  try {
    const template = await adminRemoteConfig().getTemplate();

    for (const [name, param] of Object.entries(template.parameters ?? {})) {
      const def = param.defaultValue;
      if (def && 'value' in def) values.set(name, String(def.value));

      if (
        param.conditionalValues &&
        Object.keys(param.conditionalValues).length > 0
      ) {
        conditional.add(name);
      }
    }

    return { values, conditional, etag: template.etag ?? null };
  } catch {
    // Remote Config being unreachable must not take a page down — callers fall
    // back to the documented defaults, exactly as the mobile app does.
    return { values, conditional, etag: null };
  }
}

export function rcNumber(
  rc: RcTemplateValues,
  key: string,
  fallback: number,
): number {
  const raw = rc.values.get(key);
  if (raw == null) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function rcString(
  rc: RcTemplateValues,
  key: string,
  fallback: string,
): string {
  return rc.values.get(key) ?? fallback;
}

/**
 * The free-tier ceilings, resolved once.
 *
 * Defaults match the in-app defaults registered by the mobile client
 * (`apps/mobile/lib/core/config/remote_config_init.dart`) and the server's
 * quota check, so an unset key reads the same everywhere.
 *
 * Note `free_tier_ai_quota` — PRD §9 documents this key as
 * `free_tier_ai_actions_monthly`, but the shipped code reads
 * `free_tier_ai_quota`. The code is authoritative.
 */
export interface FreeTierLimits {
  wallets: number;
  transactionsMonthly: number;
  aiMonthly: number;
}

export function freeTierLimits(rc: RcTemplateValues): FreeTierLimits {
  return {
    wallets: rcNumber(rc, 'free_tier_wallets_max', 1),
    transactionsMonthly: rcNumber(rc, 'free_tier_transactions_monthly', 100),
    aiMonthly: rcNumber(rc, 'free_tier_ai_quota', 5),
  };
}
