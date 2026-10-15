import 'server-only';

import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

/**
 * Works around a sharp edge in local development with user credentials.
 *
 * `gcloud auth application-default login` writes an `authorized_user` ADC file.
 * Several Google APIs — identitytoolkit (Firebase Auth) among them — refuse
 * user credentials that carry no quota project, with a 403 that firebase-admin
 * then mangles down to a bare documentation URL:
 *
 *   "The identitytoolkit.googleapis.com API requires a quota project,
 *    which is not set by default."
 *
 * google-auth-library reads GOOGLE_CLOUD_QUOTA_PROJECT and forwards it as the
 * x-goog-user-project header, which satisfies the requirement.
 *
 * This is deliberately narrow. It only acts when ADC is an `authorized_user`
 * file with no quota_project_id of its own — i.e. exactly the local-dev case.
 * Production runs on a service account via the metadata server, where no ADC
 * file exists, so this is a no-op there. That matters: adding the header
 * requires `serviceusage.services.use`, so setting it unconditionally could
 * turn a working production deployment into a 403.
 */
export function ensureQuotaProject(projectId: string | undefined): void {
  if (!projectId) return;
  if (process.env.GOOGLE_CLOUD_QUOTA_PROJECT) return;
  // An explicit key file is a service account — it needs no quota project.
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return;

  try {
    const base =
      process.env.CLOUDSDK_CONFIG ?? join(homedir(), '.config', 'gcloud');
    const adcPath = join(base, 'application_default_credentials.json');
    if (!existsSync(adcPath)) return;

    const adc = JSON.parse(readFileSync(adcPath, 'utf8'));
    if (adc.type !== 'authorized_user') return;
    if (adc.quota_project_id) return;

    process.env.GOOGLE_CLOUD_QUOTA_PROJECT = projectId;
  } catch {
    // Unreadable or malformed ADC — leave the environment alone and let the
    // Admin SDK surface its own error.
  }
}
