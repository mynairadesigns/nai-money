import 'server-only';

import type {
  RemoteConfigTemplate,
  Version,
} from 'firebase-admin/remote-config';

import { adminRemoteConfig } from '@/lib/firebase/admin';

import {
  computeChanges,
  type LiveParameter,
  type LiveTemplateView,
  type PendingChange,
} from './diff';
import { RC_VALUE_TYPE, rcKey } from './manifest';

/**
 * The write side of Remote Config: fetch the whole template, mutate only the
 * `defaultValue` of the parameters the operator edited, publish it back.
 *
 * Why round-trip the WHOLE template object rather than build a fresh one:
 *   - `conditions`, `parameterGroups`, and every parameter this panel does not
 *     know about survive untouched. Constructing a template from the manifest
 *     would silently delete anything the manifest has not heard of.
 *   - The `etag` is a readonly field on the object firebase-admin hands back,
 *     and `publishTemplate` sends it as `If-Match`. Passing the same object
 *     back is what makes a concurrent edit in the Firebase console FAIL the
 *     publish instead of silently overwriting it.
 *
 * This module is the only place in the panel that writes to Remote Config.
 */

export interface TemplateSnapshot {
  live: LiveTemplateView;
  etag: string | null;
  versionNumber: string | null;
  /** Epoch ms of the last publish, or null when the template has no version. */
  updatedAtMs: number | null;
  updatedByEmail: string | null;
  updateOrigin: string | null;
  /**
   * Set when Remote Config could not be reached at all. The page still renders
   * — an operator debugging a broken deployment needs the manifest and the
   * reason, not a 500.
   */
  error: string | null;
}

const UNREACHABLE: TemplateSnapshot = {
  live: new Map(),
  etag: null,
  versionNumber: null,
  updatedAtMs: null,
  updatedByEmail: null,
  updateOrigin: null,
  error: null,
};

/**
 * Reduces firebase-admin's parameter shape to the structural view diff.ts
 * consumes.
 *
 * `defaultValue` is a union: an explicit `{ value }`, an in-app-default marker,
 * or one of the rollout / personalization / experiment variants, each of which
 * nests its payload one level down (`rolloutValue`, `personalizationValue`, …).
 * The test here is `'value' in defaultValue`, character for character what
 * `select_provider.ts` does — so only the explicit form yields a value, and
 * this view shows what the SERVER sees rather than what the Firebase console
 * displays.
 */
export function toLiveView(template: RemoteConfigTemplate): LiveTemplateView {
  const out = new Map<string, LiveParameter>();

  for (const [name, param] of Object.entries(template.parameters ?? {})) {
    const def = param.defaultValue;

    out.set(name, {
      value: def && 'value' in def ? String(def.value) : null,
      usesInAppDefault: Boolean(
        def && 'useInAppDefault' in def && def.useInAppDefault,
      ),
      hasConditionalValues:
        param.conditionalValues != null &&
        Object.keys(param.conditionalValues).length > 0,
      valueType: param.valueType ?? null,
    });
  }

  return out;
}

function versionFields(version: Version | undefined) {
  const updateTime = version?.updateTime;
  const parsed = updateTime ? Date.parse(updateTime) : NaN;

  return {
    versionNumber: version?.versionNumber ?? null,
    updatedAtMs: Number.isFinite(parsed) ? parsed : null,
    updatedByEmail: version?.updateUser?.email ?? null,
    updateOrigin: version?.updateOrigin ?? null,
  };
}

/** Fetches the live template for display. Never throws. */
export async function fetchTemplateSnapshot(): Promise<TemplateSnapshot> {
  try {
    const template = await adminRemoteConfig().getTemplate();

    return {
      live: toLiveView(template),
      etag: template.etag ?? null,
      ...versionFields(template.version),
      error: null,
    };
  } catch (e) {
    return { ...UNREACHABLE, error: describeError(e) };
  }
}

/* --------------------------------------------------------------- publish -- */

export type PublishFailure =
  /** Someone else published between the page load and this submit. */
  | { kind: 'stale' }
  /** Remote Config rejected the template itself. */
  | { kind: 'rejected'; detail: string }
  /** Credentials, network, IAM. */
  | { kind: 'unavailable'; detail: string };

export type PublishResult =
  | {
      ok: true;
      /** Empty when the submitted values already matched the template. */
      changes: PendingChange[];
      versionNumber: string | null;
      etag: string | null;
    }
  | { ok: false; failure: PublishFailure; message: string };

/**
 * Applies [values] to the live template and publishes it.
 *
 * TWO concurrency guards, because they cover different windows:
 *   1. `expectedEtag` is the etag the operator's page was rendered from. If the
 *      template has moved on since, we refuse before touching anything — so the
 *      diff they confirmed is still the diff they get.
 *   2. `publishTemplate` then sends the freshly-fetched etag as `If-Match`,
 *      which covers the (tiny) window between our own read and write.
 *
 * `force` is deliberately never passed: that flag exists to bypass exactly the
 * protection above, and an admin panel is the last place that should.
 */
export async function publishValues(opts: {
  expectedEtag: string | null;
  values: ReadonlyMap<string, string>;
}): Promise<PublishResult> {
  let template: RemoteConfigTemplate;
  try {
    template = await adminRemoteConfig().getTemplate();
  } catch (e) {
    return {
      ok: false,
      failure: { kind: 'unavailable', detail: describeError(e) },
      message: `Could not read the current Remote Config template, so nothing was published. ${describeError(e)}`,
    };
  }

  const currentEtag = template.etag ?? null;
  if (opts.expectedEtag != null && currentEtag !== opts.expectedEtag) {
    return {
      ok: false,
      failure: { kind: 'stale' },
      message:
        'The Remote Config template changed since this page was loaded — most likely an edit in the Firebase console or another admin session. Nothing was published. Reload to see the current values and re-apply your change.',
    };
  }

  const changes = computeChanges(toLiveView(template), opts.values);

  // Publishing an identical template still burns a version number and an audit
  // entry, so a no-op submit stops here and reports honestly.
  if (changes.length === 0) {
    return {
      ok: true,
      changes: [],
      versionNumber: template.version?.versionNumber ?? null,
      etag: currentEtag,
    };
  }

  for (const change of changes) {
    applyValue(template, change.key, change.after);
  }

  try {
    const published = await adminRemoteConfig().publishTemplate(template);
    return {
      ok: true,
      changes,
      versionNumber: published.version?.versionNumber ?? null,
      etag: published.etag ?? null,
    };
  } catch (e) {
    return classifyPublishError(e);
  }
}

/**
 * Sets one parameter's `defaultValue`, creating the parameter if needed.
 *
 * Only `defaultValue` is ever written. `conditionalValues` on an existing
 * parameter are left in place — the panel does not present them, so it has no
 * business deleting them either. (Drift flags their presence instead, since the
 * server ignores them.)
 *
 * `description` is written only on creation. Overwriting it on every publish
 * would clobber whatever the operator typed in the Firebase console.
 */
function applyValue(
  template: RemoteConfigTemplate,
  name: string,
  value: string,
): void {
  const def = rcKey(name);
  const existing = template.parameters[name];

  if (existing) {
    existing.defaultValue = { value };
    // Only stamp a valueType where there wasn't a usable one, so an operator's
    // deliberate choice survives.
    if (def && !existing.valueType) existing.valueType = RC_VALUE_TYPE[def.type];
    return;
  }

  template.parameters[name] = {
    defaultValue: { value },
    ...(def
      ? {
          valueType: RC_VALUE_TYPE[def.type],
          // The console truncates past ~100 chars; keep the first sentence.
          description: def.description.slice(0, 100),
        }
      : {}),
  };
}

/* ---------------------------------------------------------------- errors -- */

function describeError(e: unknown): string {
  if (e instanceof Error && e.message) return e.message;
  return 'Unknown error.';
}

function errorCode(e: unknown): string {
  const code = (e as { code?: unknown } | null)?.code;
  return typeof code === 'string' ? code : '';
}

/**
 * Turns a publish rejection into something an operator can act on.
 *
 * An etag mismatch surfaces as `failed-precondition` or `aborted` depending on
 * whether the REST API answered 412 or 409; both mean the same thing here, and
 * both are recoverable by reloading. Everything else is reported verbatim
 * rather than flattened into "publish failed" — the SDK's message usually names
 * the offending parameter.
 */
function classifyPublishError(e: unknown): PublishResult {
  const code = errorCode(e);
  const detail = describeError(e);
  const haystack = `${code} ${detail}`.toLowerCase();

  const stale =
    code === 'remote-config/failed-precondition' ||
    code === 'remote-config/aborted' ||
    haystack.includes('etag') ||
    haystack.includes('version mismatch');

  if (stale) {
    return {
      ok: false,
      failure: { kind: 'stale' },
      message:
        'Remote Config rejected the publish because the template changed underneath it — someone edited it in the Firebase console or another admin session. Nothing was published. Reload and re-apply your change.',
    };
  }

  if (
    code === 'remote-config/invalid-argument' ||
    code === 'remote-config/out-of-range'
  ) {
    return {
      ok: false,
      failure: { kind: 'rejected', detail },
      message: `Remote Config rejected the template: ${detail}`,
    };
  }

  return {
    ok: false,
    failure: { kind: 'unavailable', detail },
    message: `Publish failed: ${detail}`,
  };
}
