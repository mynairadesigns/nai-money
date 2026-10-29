'use client';

import { useRouter } from 'next/navigation';
import { useMemo, useState, type ComponentProps } from 'react';

import { Badge, Button, Card, CardTitle, Input, Select } from '@/components/ui';
import { DEMO_MODE_MESSAGE, isDemoMode } from '@/lib/config/demo-mode';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import {
  DRIFT_LABEL,
  computeChanges,
  validateChanges,
  type DriftFinding,
  type DriftSeverity,
  type LiveParameter,
  type PendingChange,
} from '@/lib/remote-config/diff';
import {
  RC_MANIFEST,
  RC_READ_BY_BLURB,
  RC_READ_BY_LABEL,
  RC_READ_BY_ORDER,
  validateRcValue,
  type RcKeyDef,
} from '@/lib/remote-config/manifest';

/**
 * The Remote Config editor.
 *
 * A client component because it holds an edit buffer, but it deliberately owns
 * no knowledge: the manifest (with its validators) is imported directly, and
 * the live template arrives as plain serializable data from the page.
 *
 * TWO-PHASE by design. Nothing publishes straight from the form — the operator
 * confirms an explicit before → after list first. Remote Config has no staging
 * environment and no undo beyond rolling back a whole template version, so a
 * mistyped ceiling reaches production users on the next fetch.
 *
 * The edit buffer holds ONLY keys the operator actually changed. Fields are
 * pre-filled with the live value (or the built-in default, when the key is
 * absent), so an untouched pre-filled field can never be swept into a publish
 * and quietly create a parameter nobody asked for.
 */

export interface EditorProps {
  live: Record<string, LiveParameter>;
  findings: DriftFinding[];
  etag: string | null;
  /** Set when Remote Config could not be read — publishing is then blocked. */
  unreachable: boolean;
}

interface PublishResponse {
  ok?: boolean;
  published?: boolean;
  changes?: PendingChange[];
  versionNumber?: string | null;
  auditError?: string | null;
  message?: string;
  error?: string;
  fieldErrors?: Record<string, string>;
}

type Phase = 'edit' | 'confirm';

const SEVERITY_TONE: Record<
  DriftSeverity,
  ComponentProps<typeof Badge>['tone']
> = {
  error: 'critical',
  warning: 'warning',
  info: 'neutral',
};

export function RemoteConfigEditor({
  live,
  findings,
  etag,
  unreachable,
}: EditorProps) {
  const router = useRouter();

  const [edits, setEdits] = useState<Record<string, string>>({});
  const [phase, setPhase] = useState<Phase>('edit');
  const [busy, setBusy] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [result, setResult] = useState<PublishResponse | null>(null);

  // The server refuses regardless; this only keeps the affordance honest so a
  // viewer is not invited to click something that will be rejected.
  const demo = isDemoMode();

  const liveMap = useMemo(
    () => new Map(Object.entries(live)),
    [live],
  );

  const findingsByKey = useMemo(() => {
    const out = new Map<string, DriftFinding[]>();
    for (const f of findings) {
      const list = out.get(f.key);
      if (list) list.push(f);
      else out.set(f.key, [f]);
    }
    return out;
  }, [findings]);

  const changes = useMemo(
    () => computeChanges(liveMap, new Map(Object.entries(edits))),
    [liveMap, edits],
  );

  const validationErrors = useMemo(
    () => validateChanges(changes, validateRcValue),
    [changes],
  );

  function displayValue(def: RcKeyDef): string {
    return edits[def.name] ?? liveMap.get(def.name)?.value ?? def.defaultValue;
  }

  function setValue(name: string, value: string) {
    setEdits((prev) => ({ ...prev, [name]: value }));
    // A stale verdict next to a field the operator is actively fixing is worse
    // than none, so clear both error channels on edit.
    setFieldErrors((prev) => {
      if (!(name in prev)) return prev;
      const next = { ...prev };
      delete next[name];
      return next;
    });
    setServerError(null);
  }

  function revert(name: string) {
    setEdits((prev) => {
      const next = { ...prev };
      delete next[name];
      return next;
    });
  }

  function discardAll() {
    setEdits({});
    setFieldErrors({});
    setServerError(null);
    setPhase('edit');
  }

  async function publish() {
    setBusy(true);
    setServerError(null);
    setFieldErrors({});

    try {
      const response = await fetch('/api/admin/remote-config', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          expectedEtag: etag,
          values: Object.fromEntries(changes.map((c) => [c.key, c.after])),
        }),
      });

      const body: PublishResponse = await response.json().catch(() => ({}));

      if (!response.ok) {
        setServerError(body.error ?? 'Publish failed.');
        if (body.fieldErrors) setFieldErrors(body.fieldErrors);
        setPhase('edit');
        return;
      }

      setResult(body);
      setEdits({});
      setPhase('edit');
      // The page is a server component reading the live template, so it has to
      // re-render for the "live value" column to stop showing the old values.
      router.refresh();
    } catch (e) {
      setServerError(
        e instanceof Error ? e.message : 'Publish failed — network error.',
      );
      setPhase('edit');
    } finally {
      setBusy(false);
    }
  }

  const blocked = validationErrors.size > 0;

  return (
    <div className="flex flex-col gap-8">
      {demo ? (
        <Card className="flex flex-col gap-2 border-l-4 border-tertiary">
          <CardTitle>Demo mode — read only</CardTitle>
          <p className="max-w-prose text-body-md text-on-surface-variant">
            {DEMO_MODE_MESSAGE} You can still edit fields here to see the diff
            and validation; publishing is what is blocked.
          </p>
        </Card>
      ) : null}

      {result ? (
        <PublishOutcome result={result} onDismiss={() => setResult(null)} />
      ) : null}

      {serverError ? (
        <Card className="flex flex-col gap-2">
          <p role="alert" className="text-label-md text-error">
            {serverError}
          </p>
          <p className="text-body-md text-on-surface-variant">
            Nothing was published. Your edits are still here — reload the page if
            the message above says the template moved on.
          </p>
        </Card>
      ) : null}

      {phase === 'confirm' ? (
        <ConfirmPanel
          changes={changes}
          busy={busy}
          onBack={() => setPhase('edit')}
          onPublish={publish}
        />
      ) : null}

      {RC_READ_BY_ORDER.map((group) => {
        const keys = RC_MANIFEST.filter((def) => def.readBy === group);
        if (keys.length === 0) return null;

        return (
          <Card key={group} className="flex flex-col gap-6">
            <div>
              <CardTitle>{RC_READ_BY_LABEL[group]}</CardTitle>
              <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
                {RC_READ_BY_BLURB[group]}
              </p>
            </div>

            <div className="flex flex-col">
              {keys.map((def) => (
                <KeyRow
                  key={def.name}
                  def={def}
                  live={liveMap.get(def.name)}
                  value={displayValue(def)}
                  edited={def.name in edits}
                  findings={findingsByKey.get(def.name) ?? []}
                  error={
                    fieldErrors[def.name] ?? validationErrors.get(def.name) ?? null
                  }
                  onChange={(v) => setValue(def.name, v)}
                  onRevert={() => revert(def.name)}
                />
              ))}
            </div>
          </Card>
        );
      })}

      <ActionBar
        demo={demo}
        count={changes.length}
        blocked={blocked}
        unreachable={unreachable}
        phase={phase}
        onReview={() => setPhase('confirm')}
        onDiscard={discardAll}
      />
    </div>
  );
}

/* ------------------------------------------------------------------- row -- */

function KeyRow({
  def,
  live,
  value,
  edited,
  findings,
  error,
  onChange,
  onRevert,
}: {
  def: RcKeyDef;
  live: LiveParameter | undefined;
  value: string;
  edited: boolean;
  findings: DriftFinding[];
  error: string | null;
  onChange: (value: string) => void;
  onRevert: () => void;
}) {
  const inputId = `rc-${def.name}`;

  return (
    // The 1.4fr:1fr split is a layout proportion, not a design token — it gives
    // the description column the extra width its prose needs while keeping the
    // input comfortably wide. Tailwind has no fractional-ratio grid utility, and
    // grid-cols-2 would cramp the descriptions. Arbitrary values are otherwise
    // banned here; this and the 1.5px focus ring are the only two.
    <div className="grid gap-4 border-b border-outline/10 py-6 first:pt-0 last:border-0 last:pb-0 md:grid-cols-[1.4fr_1fr]">
      <div className="flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <label
            htmlFor={inputId}
            className="rounded-sm bg-surface-container px-1 font-sans text-body-md text-on-surface"
          >
            {def.name}
          </label>
          <span className="text-label-sm uppercase text-on-surface-variant">
            {def.type}
          </span>
          {findings.map((f) => (
            <Badge key={f.kind} tone={SEVERITY_TONE[f.severity]}>
              {DRIFT_LABEL[f.kind]}
            </Badge>
          ))}
        </div>

        <p className="max-w-prose text-body-md text-on-surface-variant">
          {def.description}
        </p>

        {def.note ? (
          <p className="max-w-prose text-label-sm text-on-surface-variant">
            <span className="text-primary">Note — </span>
            {def.note}
          </p>
        ) : null}

        {def.readSites.length > 0 ? (
          <p className="text-label-sm text-on-surface-variant">
            Read at{' '}
            {def.readSites.map((site, i) => (
              <span key={site}>
                {i > 0 ? ', ' : ''}
                <span className="rounded-sm bg-surface-container px-1 font-sans">
                  {site}
                </span>
              </span>
            ))}
          </p>
        ) : null}

        {findings.map((f) => (
          <p key={f.kind} className="max-w-prose text-label-sm text-on-surface-variant">
            {f.message}
          </p>
        ))}
      </div>

      <div className="flex flex-col gap-2">
        <ValueControl id={inputId} def={def} value={value} onChange={onChange} />

        {error ? (
          <p role="alert" className="text-label-sm text-error">
            {error}
          </p>
        ) : null}

        <div className="flex flex-wrap items-baseline gap-4 text-label-sm text-on-surface-variant">
          <span>
            Live:{' '}
            <span className="text-on-surface">
              {live?.usesInAppDefault
                ? 'in-app default'
                : live?.value == null
                  ? 'not set'
                  : quote(live.value)}
            </span>
          </span>
          <span>
            Built-in: <span className="text-on-surface">{quote(def.defaultValue)}</span>
          </span>
        </div>

        {edited ? (
          <div>
            <Button type="button" variant="text" onClick={onRevert}>
              Undo this change
            </Button>
          </div>
        ) : null}
      </div>
    </div>
  );
}

/**
 * A picker where the manifest fixes the legal values, a text field otherwise.
 *
 * The `<select>` is styled by hand rather than pulled from `components/ui`,
 * which has no Select primitive yet. Classes mirror `Input` exactly so the two
 * stay visually identical; if a Select is ever added there, delete this.
 */
function ValueControl({
  id,
  def,
  value,
  onChange,
}: {
  id: string;
  def: RcKeyDef;
  value: string;
  onChange: (value: string) => void;
}) {
  const choices = def.choices ?? (def.type === 'bool' ? ['true', 'false'] : null);

  if (choices) {
    return (
      <Select id={id} value={value} onChange={(e) => onChange(e.target.value)}>
        {choices.map((choice) => (
          <option key={choice} value={choice}>
            {choice === '' ? '(unset)' : choice}
          </option>
        ))}
        {/* A live value outside the legal set must stay selectable, or the
            control would silently rewrite it just by rendering. */}
        {choices.includes(value) ? null : (
          <option value={value}>{quote(value)} — not a legal value</option>
        )}
      </Select>
    );
  }

  return (
    <Input
      id={id}
      value={value}
      inputMode={def.type === 'int' ? 'numeric' : undefined}
      onChange={(e) => onChange(e.target.value)}
      placeholder={def.defaultValue || '(empty)'}
    />
  );
}

/* --------------------------------------------------------------- confirm -- */

function ConfirmPanel({
  changes,
  busy,
  onBack,
  onPublish,
}: {
  changes: PendingChange[];
  busy: boolean;
  onBack: () => void;
  onPublish: () => void;
}) {
  return (
    <Card className="flex flex-col gap-6">
      <div>
        <CardTitle>
          Publish {changes.length} change{changes.length === 1 ? '' : 's'}?
        </CardTitle>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          This writes a new Remote Config template version for the whole project.
          Conditions, parameter groups, and keys not listed here are carried
          through untouched.
        </p>
      </div>

      <Table>
        <THead>
          <TH>Key</TH>
          <TH>Before</TH>
          <TH>After</TH>
        </THead>
        <TBody>
          {changes.map((change) => (
            <TR key={change.key}>
              <TD>
                <span className="rounded-sm bg-surface-container px-1 font-sans">
                  {change.key}
                </span>
                {change.creates ? (
                  <span className="ml-2 align-middle">
                    <Badge tone="warning">creates parameter</Badge>
                  </span>
                ) : null}
              </TD>
              <TD className="text-on-surface-variant">
                {change.before == null ? 'not set' : quote(change.before)}
              </TD>
              <TD>{quote(change.after)}</TD>
            </TR>
          ))}
        </TBody>
      </Table>

      <PublishFootguns />

      <div className="flex flex-wrap gap-4">
        <Button type="button" variant="primary" onClick={onPublish} disabled={busy}>
          {busy ? 'Publishing…' : `Publish ${changes.length} change${changes.length === 1 ? '' : 's'}`}
        </Button>
        <Button type="button" variant="ghost" onClick={onBack} disabled={busy}>
          Back to editing
        </Button>
      </div>
    </Card>
  );
}

/**
 * The two things that make Remote Config behave unlike a settings screen. They
 * sit immediately above the publish button rather than in a help page, because
 * both change what the operator should expect in the minutes AFTER publishing —
 * which is exactly when they would otherwise conclude the change did not work
 * and publish something else on top of it.
 */
function PublishFootguns() {
  return (
    <ul className="flex flex-col gap-4 text-body-md text-on-surface-variant">
      <li className="flex gap-4">
        <span aria-hidden className="text-primary">
          —
        </span>
        <span>
          Cloud Functions read a key&rsquo;s <strong>defaultValue only</strong>.
          Conditions and percentage rollouts have no server-side effect: a key
          whose only default is a rollout is invisible to the server, which
          silently falls back to its built-in value.
        </span>
      </li>
      <li className="flex gap-4">
        <span aria-hidden className="text-primary">
          —
        </span>
        <span>
          <strong>This will not land instantly, or all at once.</strong> Each warm
          Function instance caches the template for its whole lifetime with no
          TTL, so it picks up the change only when it recycles; the mobile app
          throttles to one fetch per hour in release builds. Expect old and new
          values to be in use simultaneously for a while.
        </span>
      </li>
    </ul>
  );
}

/* -------------------------------------------------------------- outcomes -- */

function PublishOutcome({
  result,
  onDismiss,
}: {
  result: PublishResponse;
  onDismiss: () => void;
}) {
  const changes = result.changes ?? [];

  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-4">
        <CardTitle>
          {result.published ? 'Published' : 'Nothing to publish'}
        </CardTitle>
        {result.versionNumber ? (
          <Badge tone="positive">version {result.versionNumber}</Badge>
        ) : null}
      </div>

      <p className="max-w-prose text-body-md text-on-surface-variant">
        {result.message ??
          `${changes.length} key${changes.length === 1 ? '' : 's'} updated. Running Function instances keep their cached template until they recycle.`}
      </p>

      {changes.length > 0 ? (
        <ul className="flex flex-col gap-1 text-label-sm text-on-surface-variant">
          {changes.map((change) => (
            <li key={change.key}>
              <span className="rounded-sm bg-surface-container px-1 font-sans">
                {change.key}
              </span>{' '}
              {change.before == null ? 'not set' : quote(change.before)} →{' '}
              <span className="text-on-surface">{quote(change.after)}</span>
            </li>
          ))}
        </ul>
      ) : null}

      {result.auditError ? (
        <p role="alert" className="max-w-prose text-label-md text-error">
          The change was published, but writing the audit entry failed:{' '}
          {result.auditError} — this publish is missing from the audit log.
          Record it by hand if your deployment relies on that trail.
        </p>
      ) : null}

      <div>
        <Button type="button" variant="ghost" onClick={onDismiss}>
          Dismiss
        </Button>
      </div>
    </Card>
  );
}

function ActionBar({
  demo,
  count,
  blocked,
  unreachable,
  phase,
  onReview,
  onDiscard,
}: {
  demo: boolean;
  count: number;
  blocked: boolean;
  unreachable: boolean;
  phase: Phase;
  onReview: () => void;
  onDiscard: () => void;
}) {
  if (count === 0) return null;

  return (
    <div className="sticky bottom-0 flex flex-wrap items-center gap-4 rounded-lg bg-surface-container-high px-6 py-4 shadow-level-2">
      <span className="flex-1 text-body-md text-on-surface">
        {count} pending change{count === 1 ? '' : 's'}
        {blocked ? ' — fix the highlighted values first' : ''}
        {demo && !blocked ? ' — demo mode, publishing is disabled' : ''}
      </span>

      <Button type="button" variant="ghost" onClick={onDiscard}>
        Discard
      </Button>
      <Button
        type="button"
        variant="primary"
        onClick={onReview}
        disabled={demo || blocked || unreachable || phase === 'confirm'}
      >
        {demo
          ? 'Demo mode'
          : unreachable
            ? 'Remote Config unreachable'
            : 'Review changes'}
      </Button>
    </div>
  );
}

/** Quotes a value so an empty string and a missing one cannot look alike. */
function quote(value: string): string {
  return value === '' ? '""' : value;
}
