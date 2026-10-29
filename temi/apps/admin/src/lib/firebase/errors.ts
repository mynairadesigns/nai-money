import 'server-only';

/**
 * Distinguishes "this deployment cannot verify anything" from "this caller
 * presented a bad token".
 *
 * Both surface as a thrown error from the Admin SDK, and collapsing them into
 * a single 401 is actively misleading: an operator with perfectly good
 * credentials sees "sign-in failed" and starts debugging their account, when
 * the real problem is that the server has no Application Default Credentials.
 */
const CREDENTIAL_MARKERS = [
  'could not load the default credentials',
  'application default credentials',
  'unable to detect a project id',
  'failed to determine project id',
  'invalid_grant',
  'error fetching access token',
  'could not refresh access token',
  'reauthentication is needed',
  'getting metadata from plugin failed',
  // Identity Toolkit rejects ADC user credentials that carry no quota project.
  // firebase-admin mangles that 403 down to a bare doc URL and reports it as
  // the catch-all `auth/internal-error`, so the URL is the only usable signal.
  'requires a quota project',
  'adc-troubleshooting',
];

// Only codes that unambiguously mean "the server's own credentials failed".
// `auth/internal-error` is deliberately NOT here: it is a catch-all that also
// covers ordinary token problems, and misreporting one of those as a broken
// deployment is worse than the generic 401.
const CREDENTIAL_CODES = ['app/invalid-credential'];

export function isCredentialError(e: unknown): boolean {
  if (!e) return false;

  const code = (e as { code?: string }).code?.toLowerCase() ?? '';
  if (CREDENTIAL_CODES.includes(code)) return true;

  const message = (
    (e as { message?: string }).message ?? String(e)
  ).toLowerCase();

  return CREDENTIAL_MARKERS.some((marker) => message.includes(marker));
}

/** Operator-facing guidance for a credential failure. Safe to log. */
export const CREDENTIAL_HELP =
  'The server has no usable Firebase credentials. Locally, run ' +
  '`gcloud auth application-default login`, and if Firebase Auth still 403s, ' +
  '`gcloud auth application-default set-quota-project <your-project-id>` ' +
  '(user credentials need a quota project). On Vercel there is no Application ' +
  'Default Credentials, so set FIREBASE_SERVICE_ACCOUNT_JSON to the whole ' +
  'service-account key JSON. On a Google runtime, grant the runtime service ' +
  'account roles/firebaseauth.admin and roles/datastore.user instead. ' +
  'See docs/ADMIN_SETUP.md.';
