import { Badge, Card, CardTitle, Stat } from '@/components/ui';
import { Table, TBody, TD, TH, THead, TR } from '@/components/ui/table';
import { requireAdmin } from '@/lib/auth/require-admin';
import { EMPTY, formatDateTime } from '@/lib/format';
import { driftForTemplate, summarizeDrift } from '@/lib/remote-config/diff';
import { RC_MANIFEST } from '@/lib/remote-config/manifest';
import { fetchTemplateSnapshot } from '@/lib/remote-config/template';

import { RemoteConfigEditor } from './editor';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * Remote Config editor.
 *
 * Shows the LIVE template beside a manifest of every key the code actually
 * reads, because those two sets do not match: PRD §9 documents keys that
 * nothing reads, omits two that are required for purchases to work, and names
 * the AI quota key differently from the code. Each of those is recorded on the
 * key itself rather than smoothed over.
 *
 * The panel edits `defaultValue` and nothing else — that is the only field
 * Cloud Functions look at, and the field the mobile client falls back to.
 * Conditions and parameter groups are preserved on publish but not editable
 * here; the Firebase console is the right tool for those.
 */
export default async function RemoteConfigPage() {
  await requireAdmin();

  const snapshot = await fetchTemplateSnapshot();
  const findings = driftForTemplate(snapshot.live);
  const summary = summarizeDrift(findings);

  // Keys sitting in the template that no code in this repo reads. Rendered
  // separately because the editor only knows manifest keys — without this they
  // would be invisible here while remaining very much present in production.
  const strays = findings.filter((f) => f.kind === 'unknown-key');

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">Remote Config</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          The live template for this project, checked against a manifest of the{' '}
          {RC_MANIFEST.length} keys this codebase knows about. Editing writes a
          key&rsquo;s <code>defaultValue</code> — the only field Cloud Functions
          read.
        </p>
      </div>

      {snapshot.error ? (
        <Card className="flex flex-col gap-2">
          <CardTitle>Remote Config is unreachable</CardTitle>
          <p role="alert" className="max-w-prose text-body-md text-error">
            {snapshot.error}
          </p>
          <p className="max-w-prose text-body-md text-on-surface-variant">
            Every key below therefore shows as unset. That is this page failing
            to read the template, not proof the template is empty — publishing is
            disabled until the read succeeds.
          </p>
        </Card>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="Template version"
          value={snapshot.versionNumber ?? EMPTY}
          hint={
            snapshot.updateOrigin
              ? `last published via ${snapshot.updateOrigin.toLowerCase()}`
              : 'never published'
          }
        />
        <Stat
          label="Last published"
          value={formatDateTime(snapshot.updatedAtMs)}
          hint={snapshot.updatedByEmail ?? 'unknown author'}
        />
        <Stat
          label="ETag"
          value={
            <span className="text-body-md break-all">
              {snapshot.etag ?? EMPTY}
            </span>
          }
          hint="guards against a concurrent console edit"
        />
        <Stat
          label="Drift findings"
          value={summary.errors + summary.warnings}
          hint={`${summary.errors} error · ${summary.warnings} warning · ${summary.infos} info`}
        />
      </div>

      <HowItReaches />

      {strays.length > 0 ? (
        <Card className="flex flex-col gap-4">
          <div>
            <CardTitle>In the template, read by nothing</CardTitle>
            <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
              These parameters exist in Remote Config but appear nowhere in{' '}
              <code>apps/functions</code> or <code>apps/mobile</code>. Usually a
              typo of a real key, or a leftover from a removed feature. This
              panel will not edit them — use the Firebase console.
            </p>
          </div>
          <Table>
            <THead>
              <TH>Parameter</TH>
              <TH>Live value</TH>
            </THead>
            <TBody>
              {strays.map((f) => (
                <TR key={f.key}>
                  <TD>
                    <span className="rounded-sm bg-surface-container px-1 font-sans">
                      {f.key}
                    </span>
                  </TD>
                  <TD className="text-on-surface-variant">
                    {snapshot.live.get(f.key)?.value ?? 'not set'}
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
        </Card>
      ) : null}

      <RemoteConfigEditor
        live={Object.fromEntries(snapshot.live)}
        findings={findings.filter((f) => f.kind !== 'unknown-key')}
        etag={snapshot.etag}
        unreachable={snapshot.error != null}
      />
    </div>
  );
}

/**
 * Reading this page correctly depends on knowing that "the value" is not one
 * thing: the template holds one, each warm Function instance holds whatever it
 * cached, and every device holds whatever it last fetched.
 */
function HowItReaches() {
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-4">
        <CardTitle>How a change reaches production</CardTitle>
        <Badge tone="warning">not instant</Badge>
      </div>

      <ul className="flex flex-col gap-4 text-body-md text-on-surface-variant">
        <li className="flex gap-4">
          <span aria-hidden className="text-primary">
            —
          </span>
          <span>
            <strong className="text-on-surface">Cloud Functions</strong> read the
            template through <code>select_provider.ts</code>, which caches it in
            a module-level variable — one fetch per instance, for the life of
            that instance, with no TTL. A change reaches an instance only when it
            cold-starts, so old and new values run side by side until traffic
            recycles them all.
          </span>
        </li>
        <li className="flex gap-4">
          <span aria-hidden className="text-primary">
            —
          </span>
          <span>
            <strong className="text-on-surface">The mobile app</strong> fetches
            at startup with a minimum interval of 1 hour in release builds (zero
            in debug). Worst case a device runs the old value for an hour plus a
            restart.
          </span>
        </li>
        <li className="flex gap-4">
          <span aria-hidden className="text-primary">
            —
          </span>
          <span>
            <strong className="text-on-surface">
              Only <code>defaultValue</code> is read server-side.
            </strong>{' '}
            Conditions, percentage rollouts, and personalization apply to the
            mobile client only. A condition on a Functions-read key does nothing,
            and a key whose only default is a rollout reads as unset server-side.
          </span>
        </li>
      </ul>
    </Card>
  );
}
