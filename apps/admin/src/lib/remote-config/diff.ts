/**
 * Two pure comparisons over Remote Config.
 *
 *   1. DRIFT — the manifest versus what the live template actually contains.
 *      This is a health check: it answers "is this deployment configured the
 *      way the code expects, and is anything here doing nothing?"
 *
 *   2. CHANGES — the operator's pending edit versus the live template. This is
 *      the confirmation step: an explicit before → after list, so nobody
 *      publishes a value they did not mean to touch.
 *
 * Pure on purpose — no `server-only`, no firebase-admin import, not even a
 * type one. The live template is passed in as a plain structural view
 * (`LiveParameter`) built by template.ts, which keeps this file unit-testable
 * and keeps the SDK's shape from leaking into the UI.
 */

import { RC_MANIFEST, RC_VALUE_TYPE, type RcKeyDef } from './manifest';

/**
 * A single live parameter, reduced to what actually matters here.
 *
 * `value` is null both when the parameter is absent AND when it defers to the
 * in-app default, because in both cases the SERVER sees nothing — it reads
 * `defaultValue.value` and skips anything without one. `usesInAppDefault`
 * separates the two, since they are very different problems.
 */
export interface LiveParameter {
  /** The explicit `defaultValue.value`, or null when there isn't one. */
  value: string | null;
  /** True when `defaultValue` is `{ useInAppDefault: true }`. */
  usesInAppDefault: boolean;
  /** True when the parameter carries conditional (per-condition) values. */
  hasConditionalValues: boolean;
  /** The template's declared `valueType`, when the template sets one. */
  valueType: string | null;
}

export type LiveTemplateView = ReadonlyMap<string, LiveParameter>;

/* ----------------------------------------------------------------- drift -- */

export type DriftKind =
  | 'missing'
  | 'in-app-default'
  | 'type-mismatch'
  | 'invalid-value'
  | 'conditional'
  | 'customized'
  | 'unknown-key';

export type DriftSeverity = 'error' | 'warning' | 'info';

export interface DriftFinding {
  key: string;
  kind: DriftKind;
  severity: DriftSeverity;
  message: string;
}

/** Short badge text. Kept beside the kinds so the UI never invents its own. */
export const DRIFT_LABEL: Readonly<Record<DriftKind, string>> = {
  missing: 'not in template',
  'in-app-default': 'in-app default',
  'type-mismatch': 'type mismatch',
  'invalid-value': 'invalid value',
  conditional: 'has conditions',
  customized: 'customized',
  'unknown-key': 'not in manifest',
};

/**
 * Remote Config leaves `valueType` unset on parameters created before it
 * existed, and reports UNSPECIFIED for some console-authored ones. Neither is a
 * mismatch — only a type that positively contradicts the manifest is.
 */
function typeIsUnstated(valueType: string | null): boolean {
  return (
    valueType == null ||
    valueType === '' ||
    valueType === 'PARAMETER_VALUE_TYPE_UNSPECIFIED'
  );
}

function driftForKey(def: RcKeyDef, live: LiveParameter | undefined): DriftFinding[] {
  const out: DriftFinding[] = [];

  if (!live) {
    // Not an error: every read site has a hardcoded fallback, so an absent key
    // is the normal state of a fresh project. It is worth stating because the
    // effective value is then invisible in the Firebase console.
    out.push({
      key: def.name,
      kind: 'missing',
      severity: def.readBy === 'none' ? 'info' : 'warning',
      message:
        def.readBy === 'none'
          ? 'Not in the template. Nothing reads this key, so that has no effect.'
          : `Not in the template — the code falls back to its built-in default (${def.defaultValue || 'empty'}).`,
    });
    return out;
  }

  if (live.usesInAppDefault) {
    // The mobile SDK honours in-app defaults; Cloud Functions have no such
    // concept and simply see the key as absent. For a server-read key this is
    // a genuine misconfiguration, not a stylistic choice.
    out.push({
      key: def.name,
      kind: 'in-app-default',
      severity: def.readBy === 'server' ? 'error' : 'warning',
      message:
        def.readBy === 'server'
          ? 'Set to "use in-app default". Cloud Functions have no in-app defaults, so the server sees no value at all.'
          : 'Set to "use in-app default", so the value shown in the Firebase console comes from the app, not the template.',
    });
  }

  if (live.hasConditionalValues) {
    out.push({
      key: def.name,
      kind: 'conditional',
      severity: def.readBy === 'server' ? 'error' : 'warning',
      message:
        def.readBy === 'server'
          ? 'Carries conditional values. Cloud Functions read defaultValue only, so every condition and percentage rollout on this key is ignored server-side.'
          : 'Carries conditional values. The mobile app honours these, but this panel shows and edits the defaultValue only.',
    });
  }

  if (!typeIsUnstated(live.valueType) && live.valueType !== RC_VALUE_TYPE[def.type]) {
    out.push({
      key: def.name,
      kind: 'type-mismatch',
      severity: 'warning',
      message: `Template declares ${live.valueType}; the code reads this as ${def.type} (${RC_VALUE_TYPE[def.type]}).`,
    });
  }

  if (live.value != null) {
    const error = def.validate(live.value);
    if (error) {
      out.push({
        key: def.name,
        kind: 'invalid-value',
        severity: 'error',
        message: `Live value ${JSON.stringify(live.value)} is not usable: ${error}`,
      });
    } else if (live.value !== def.defaultValue) {
      // Neutral by design. A value differing from the default is the whole
      // point of Remote Config — flagging it as a problem would train the
      // operator to ignore this column.
      out.push({
        key: def.name,
        kind: 'customized',
        severity: 'info',
        message: `Set to ${JSON.stringify(live.value)}; the built-in default is ${JSON.stringify(def.defaultValue)}.`,
      });
    }
  }

  return out;
}

/**
 * Compares the manifest against the live template in both directions.
 *
 * The reverse direction matters as much as the forward one: a key sitting in
 * the template that the manifest has never heard of is usually a typo of a real
 * key, quietly doing nothing while the operator believes it is in effect.
 */
export function computeDrift(
  manifest: readonly RcKeyDef[],
  live: LiveTemplateView,
): DriftFinding[] {
  const out: DriftFinding[] = [];

  for (const def of manifest) {
    out.push(...driftForKey(def, live.get(def.name)));
  }

  const known = new Set(manifest.map((d) => d.name));
  for (const name of live.keys()) {
    if (known.has(name)) continue;
    out.push({
      key: name,
      kind: 'unknown-key',
      severity: 'info',
      message:
        'In the template but not in the manifest — no code in this repo reads it. Often a typo of a real key.',
    });
  }

  return out;
}

/** Convenience wrapper over the shipped manifest. */
export function driftForTemplate(live: LiveTemplateView): DriftFinding[] {
  return computeDrift(RC_MANIFEST, live);
}

export interface DriftSummary {
  errors: number;
  warnings: number;
  infos: number;
}

export function summarizeDrift(findings: readonly DriftFinding[]): DriftSummary {
  return {
    errors: findings.filter((f) => f.severity === 'error').length,
    warnings: findings.filter((f) => f.severity === 'warning').length,
    infos: findings.filter((f) => f.severity === 'info').length,
  };
}

/** Groups findings by key so a row can render its own badges. */
export function groupDriftByKey(
  findings: readonly DriftFinding[],
): ReadonlyMap<string, DriftFinding[]> {
  const out = new Map<string, DriftFinding[]>();
  for (const f of findings) {
    const list = out.get(f.key);
    if (list) list.push(f);
    else out.set(f.key, [f]);
  }
  return out;
}

/* --------------------------------------------------------------- changes -- */

export interface PendingChange {
  key: string;
  /** The live value, or null when the key does not exist in the template yet. */
  before: string | null;
  after: string;
  /** True when publishing would create the parameter rather than edit it. */
  creates: boolean;
}

/**
 * The before → after list for a pending edit.
 *
 * `desired` holds ONLY the fields the operator touched, so an untouched key can
 * never be dragged into a publish by a pre-filled form control. Entries whose
 * value already matches the template are dropped — re-publishing an identical
 * value would still burn a template version and an audit entry for nothing.
 *
 * A parameter that defers to the in-app default reads as `before: null` here,
 * matching the LiveParameter contract: the template holds no value to replace,
 * so publishing genuinely creates one. The UI labels that case explicitly.
 */
export function computeChanges(
  live: LiveTemplateView,
  desired: ReadonlyMap<string, string>,
): PendingChange[] {
  const out: PendingChange[] = [];

  for (const [key, after] of desired) {
    const before = live.get(key)?.value ?? null;
    if (before === after) continue;
    out.push({ key, before, after, creates: before === null });
  }

  // Stable ordering so the confirmation list, the audit entry, and the publish
  // all read the same way.
  out.sort((a, b) => a.key.localeCompare(b.key));
  return out;
}

/** Validation errors for a pending edit, keyed by parameter name. */
export function validateChanges(
  changes: readonly PendingChange[],
  validate: (key: string, raw: string) => string | null,
): ReadonlyMap<string, string> {
  const errors = new Map<string, string>();
  for (const change of changes) {
    const error = validate(change.key, change.after);
    if (error) errors.set(change.key, error);
  }
  return errors;
}

/**
 * Reduces a change list to the `{ key: value }` shape the audit log records.
 * Two objects rather than one so a reader can diff them at a glance.
 */
export function changesToAuditPayload(changes: readonly PendingChange[]): {
  before: Record<string, string | null>;
  after: Record<string, string>;
} {
  const before: Record<string, string | null> = {};
  const after: Record<string, string> = {};
  for (const change of changes) {
    before[change.key] = change.before;
    after[change.key] = change.after;
  }
  return { before, after };
}
