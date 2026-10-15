import { Card, CardTitle } from '@/components/ui';

/**
 * Placeholder for a module the roadmap has not delivered yet.
 *
 * These exist so the shell's navigation is never a dead link, and so it is
 * obvious from inside the product what is built and what is not — rather than
 * a half-working screen implying data is missing when the feature simply is
 * not there.
 */
export function ModuleStub({
  title,
  summary,
  phase,
  planned,
}: {
  title: string;
  summary: string;
  phase: string;
  planned: string[];
}) {
  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-headline-lg text-on-surface">{title}</h1>
        <p className="mt-1 max-w-prose text-body-md text-on-surface-variant">
          {summary}
        </p>
      </div>

      <Card>
        <CardTitle>Not built yet — {phase}</CardTitle>
        <ul className="mt-4 flex flex-col gap-2">
          {planned.map((item) => (
            <li
              key={item}
              className="flex gap-4 border-b border-outline/10 pb-2 text-body-md text-on-surface-variant last:border-0 last:pb-0"
            >
              <span aria-hidden className="text-primary">
                —
              </span>
              <span>{item}</span>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
