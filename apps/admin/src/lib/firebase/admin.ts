import 'server-only';

import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { getRemoteConfig, type RemoteConfig } from 'firebase-admin/remote-config';

import { ensureQuotaProject } from './quota-project';

/**
 * Server-side Firebase Admin SDK singleton.
 *
 * The admin panel reads ALL data through this — the browser never holds a
 * Firestore handle. That is deliberate: the Admin SDK bypasses security rules,
 * so `firestore.rules` can stay strictly owner-scoped (`request.auth.uid ==
 * userId`) instead of growing an admin carve-out that would widen the blast
 * radius of the whole product.
 *
 * Credentials, in order of preference:
 *   1. Application Default Credentials — what App Hosting and Cloud Run inject
 *      automatically. No key file is ever shipped or stored. This is the
 *      production path.
 *   2. GOOGLE_APPLICATION_CREDENTIALS — a local key file path, for development.
 *   3. FIREBASE_SERVICE_ACCOUNT_JSON — the raw JSON, for hosts that only offer
 *      env vars.
 *
 * The `server-only` import above makes it a build error to pull this into a
 * client component.
 */
function initAdminApp(): App {
  const existing = getApps();
  if (existing.length > 0) return existing[0];

  const projectId =
    process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ??
    process.env.GCLOUD_PROJECT ??
    process.env.GOOGLE_CLOUD_PROJECT;

  // Local ADC user credentials need a quota project or Firebase Auth 403s.
  // No-op in production. See ./quota-project.ts.
  ensureQuotaProject(projectId);

  const rawServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (rawServiceAccount) {
    return initializeApp({
      credential: cert(JSON.parse(rawServiceAccount)),
      projectId,
    });
  }

  // ADC — resolves from the metadata server in production, or from
  // `gcloud auth application-default login` / GOOGLE_APPLICATION_CREDENTIALS
  // locally.
  return initializeApp({ projectId });
}

let _app: App | undefined;
let _firestore: Firestore | undefined;

function app(): App {
  _app ??= initAdminApp();
  return _app;
}

export function adminAuth(): Auth {
  return getAuth(app());
}

/**
 * Guards `settings()` across module instances.
 *
 * A module-scoped flag is not enough. The bundler can evaluate this file more
 * than once in a single process — a route handler and a page land in separate
 * chunks — and each copy gets its own `_firestore`, while `getFirestore()`
 * returns the ONE instance firebase-admin keeps in its own registry. The second
 * copy then calls `settings()` on an instance that has already been used, which
 * throws "Firestore has already been initialized". A cross-realm symbol on
 * globalThis is shared by every copy, so the call happens exactly once.
 */
const CONFIGURED = Symbol.for('moneymind.admin.firestoreConfigured');

export function adminDb(): Firestore {
  if (!_firestore) {
    _firestore = getFirestore(app());

    const g = globalThis as Record<symbol, unknown>;
    if (!g[CONFIGURED]) {
      g[CONFIGURED] = true;
      try {
        // Firestore Timestamps carry more precision than JS Dates; we convert
        // explicitly at the serialization boundary instead.
        _firestore.settings({ ignoreUndefinedProperties: true });
      } catch {
        // Already configured by another copy that raced us here. The setting is
        // identical either way, so this is safe to ignore — and it must be, or
        // an unrelated caller inherits a fatal error from initialisation order.
      }
    }
  }
  return _firestore;
}

export function adminRemoteConfig(): RemoteConfig {
  return getRemoteConfig(app());
}
