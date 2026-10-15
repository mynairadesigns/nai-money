import * as admin from 'firebase-admin';

import { GeminiClient } from './gemini_client';
import { OpenAIClient } from './openai_client';
import { AIProvider } from './provider';

export type ProviderName = 'openai' | 'gemini';

let _rcCache: Promise<Map<string, string>> | null = null;

/**
 * Reads Remote Config `ai_provider` once per function instance and
 * returns it if it's a valid provider name. Falls back to
 * [featureDefault] if RC is unreadable, the key is unset, or the value
 * is malformed. Never throws — AI features must work even if RC is down.
 */
export async function selectProvider(opts: {
  featureDefault: ProviderName;
  overrideKey?: string;
}): Promise<ProviderName> {
  const key = opts.overrideKey ?? 'ai_provider';
  try {
    const all = await _loadRemoteConfig();
    const override = all.get(key);
    if (override === 'openai' || override === 'gemini') return override;
    return opts.featureDefault;
  } catch (e) {
    console.warn('selectProvider: RC unreadable, falling back to default', e);
    return opts.featureDefault;
  }
}

async function _loadRemoteConfig(): Promise<Map<string, string>> {
  _rcCache ??= (async () => {
    const tpl = await admin.remoteConfig().getTemplate();
    const out = new Map<string, string>();
    for (const [name, param] of Object.entries(tpl.parameters)) {
      const v = param.defaultValue;
      if (v && 'value' in v) out.set(name, String(v.value));
    }
    return out;
  })();
  return _rcCache;
}

/**
 * Numeric Remote Config read with fallback. Used by quota for
 * `free_tier_ai_quota`.
 */
export async function getRcNumber(
  key: string,
  fallback: number,
): Promise<number> {
  try {
    const all = await _loadRemoteConfig();
    const raw = all.get(key);
    if (raw == null) return fallback;
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : fallback;
  } catch {
    return fallback;
  }
}

/** Instantiates the right client with the requested model. */
export function getProvider(name: ProviderName, model: string): AIProvider {
  switch (name) {
    case 'openai':
      return new OpenAIClient(model);
    case 'gemini':
      return new GeminiClient(model);
  }
}
