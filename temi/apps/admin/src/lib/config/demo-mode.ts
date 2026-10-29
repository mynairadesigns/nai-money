/**
 * Demo mode — the panel renders everything, but writes nothing.
 *
 * Intended for showing the console to someone (a buyer evaluating the product,
 * a screenshot, a shared staging link) without handing them the ability to
 * change a live deployment. Every read-only surface behaves normally; every
 * mutation is refused.
 *
 * ENFORCED ON THE SERVER. Each write endpoint checks this before doing anything,
 * because hiding a button is not a control — the endpoint is still reachable
 * with curl. The UI checks it too, but only so the affordance matches reality
 * rather than failing after a click.
 *
 * `NEXT_PUBLIC_` so the client bundle can read the same value and disable the
 * controls. It is deployment configuration, not a secret: knowing that a panel
 * is in demo mode grants nothing, and the server refuses regardless.
 *
 * Inlined at BUILD time by Next, so changing it needs a rebuild — on App
 * Hosting that means a new rollout, not just an env edit.
 */
export function isDemoMode(): boolean {
  return process.env.NEXT_PUBLIC_DEMO_MODE === 'true';
}

/** Refusal message, shared so the API and the UI say the same thing. */
export const DEMO_MODE_MESSAGE =
  'This panel is running in demo mode, so nothing can be changed. Set NEXT_PUBLIC_DEMO_MODE=false (or remove it) and rebuild to enable writes.';
