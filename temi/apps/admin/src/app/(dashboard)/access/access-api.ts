/**
 * Shared browser client for POST /api/admin/access.
 *
 * Both islands on this page need the same response shape and the same "a
 * non-2xx still carries a JSON body worth showing" handling — and getting that
 * wrong on the revoke side would silently swallow a safety-rail refusal, which
 * is the one message an operator most needs to read.
 */

export interface AccessResponse {
  ok?: boolean;
  action?: 'grant' | 'revoke';
  uid?: string;
  email?: string | null;
  alreadyAdmin?: boolean;
  orphan?: boolean;
  self?: boolean;
  mirrorError?: string | null;
  sessionError?: string | null;
  auditError?: string | null;
  message?: string;
  error?: string;
  /** Longer guidance that accompanies a refusal — what to do instead. */
  hint?: string;
  requiresConfirmSelf?: boolean;
}

export type AccessRequest =
  | { action: 'grant'; email: string }
  | { action: 'revoke'; uid: string; confirmSelf?: boolean };

export async function postAccess(body: AccessRequest): Promise<AccessResponse> {
  const response = await fetch('/api/admin/access', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

  const parsed: AccessResponse = await response.json().catch(() => ({}));

  // A framework-level 500 has no JSON body at all. Without this the caller
  // would render nothing as the reason nothing happened.
  if (!response.ok && !parsed.error) {
    return { ...parsed, error: `The request failed (HTTP ${response.status}).` };
  }
  return parsed;
}

/**
 * Partial failures that must be shown even though the operation SUCCEEDED.
 *
 * Each of these leaves the claim — the thing that actually grants access — in
 * the state the operator asked for, while something downstream did not follow.
 * Reporting a clean success would hide a real gap in each case.
 */
export function accessWarnings(result: AccessResponse): string[] {
  const warnings: string[] = [];

  if (result.mirrorError) {
    warnings.push(
      `The claim was written but the adminUsers mirror was not: ${result.mirrorError} — ` +
        'access is correct, since the claim is what grants it, but this list is now out of step. ' +
        'Repeat the action once Firestore is reachable to repair the row.',
    );
  }

  if (result.sessionError) {
    warnings.push(
      `The claim was removed but their existing sessions could not be revoked: ${result.sessionError} — ` +
        'so this revoke is NOT immediate. They keep panel access until their session cookie expires, up to 14 days. ' +
        'Retry, or revoke the sessions from the Firebase console.',
    );
  }

  if (result.auditError) {
    warnings.push(
      `The change was made but writing the audit entry failed: ${result.auditError} — ` +
        'this change is missing from the audit log. Record it by hand if your deployment relies on that trail.',
    );
  }

  return warnings;
}
