import { describe, expect, it } from 'vitest';

import { isCredentialError } from './errors';

/**
 * The distinction this guards: a server that cannot verify ANY sign-in is
 * broken, and must not report itself as "your credentials are invalid".
 */
describe('isCredentialError', () => {
  it('recognises the real firebase-admin missing-ADC failure', () => {
    // Captured verbatim from createSessionCookie() with no credentials
    // available — the exact case an operator hits before running
    // `gcloud auth application-default login`.
    const real = Object.assign(
      new Error(
        'Credential implementation provided to initializeApp() via the ' +
          '"credential" property failed to fetch a valid Google OAuth2 access ' +
          'token with the following error: "Could not load the default ' +
          'credentials. Browse to https://cloud.google.com/docs/authentication"',
      ),
      { code: 'app/invalid-credential' },
    );

    expect(isCredentialError(real)).toBe(true);
  });

  it('recognises the mangled missing-quota-project 403', () => {
    // Identity Toolkit rejects ADC user credentials with no quota project.
    // firebase-admin reduces that 403 to the bare tail of the doc URL and
    // labels it `auth/internal-error` — captured verbatim below. The URL
    // fragment is the only usable signal, since the code is a catch-all we
    // otherwise treat as an ordinary token failure.
    const mangled = Object.assign(
      new Error('//cloud.google.com/docs/authentication/adc-troubleshooting/user-creds .'),
      { code: 'auth/internal-error' },
    );
    expect(isCredentialError(mangled)).toBe(true);
  });

  it('recognises the un-mangled quota-project message', () => {
    expect(
      isCredentialError(
        new Error(
          'Your application is authenticating by using local Application ' +
            'Default Credentials. The identitytoolkit.googleapis.com API ' +
            'requires a quota project, which is not set by default.',
        ),
      ),
    ).toBe(true);
  });

  it('recognises the failure by code alone', () => {
    expect(
      isCredentialError(Object.assign(new Error('x'), { code: 'app/invalid-credential' })),
    ).toBe(true);
  });

  it.each([
    'Could not load the default credentials',
    'Unable to detect a Project Id in the current environment',
    'Error fetching access token',
    'invalid_grant: account not found',
  ])('recognises the failure by message: %s', (message) => {
    expect(isCredentialError(new Error(message))).toBe(true);
  });

  it('does NOT classify ordinary token failures as server misconfiguration', () => {
    // These are genuine 401s. Reporting them as a broken deployment would
    // send the operator chasing infrastructure that is working fine.
    const tokenFailures = [
      Object.assign(new Error('Decoding Firebase ID token failed.'), {
        code: 'auth/argument-error',
      }),
      Object.assign(new Error('Firebase ID token has expired.'), {
        code: 'auth/id-token-expired',
      }),
      Object.assign(new Error('Firebase session cookie has been revoked.'), {
        code: 'auth/session-cookie-revoked',
      }),
      Object.assign(new Error('The user record is disabled.'), {
        code: 'auth/user-disabled',
      }),
      // The catch-all code must not be treated as a credential problem.
      Object.assign(new Error('An internal error occurred.'), {
        code: 'auth/internal-error',
      }),
    ];

    for (const e of tokenFailures) {
      expect(isCredentialError(e), e.code).toBe(false);
    }
  });

  it('handles junk input without throwing', () => {
    expect(isCredentialError(null)).toBe(false);
    expect(isCredentialError(undefined)).toBe(false);
    expect(isCredentialError('a string')).toBe(false);
    expect(isCredentialError({})).toBe(false);
  });
});
