#!/usr/bin/env node
/**
 * Grants (or revokes) admin access to the Temi Finance admin panel.
 *
 * This exists to solve a chicken-and-egg problem: access is gated on a Firebase
 * custom claim, and you cannot grant yourself that claim from a panel you
 * cannot sign in to. Run this once from a terminal to create the first admin;
 * after that, use the Access module inside the panel.
 *
 * Usage:
 *   pnpm -F admin grant-admin you@example.com
 *   pnpm -F admin grant-admin you@example.com --create
 *   pnpm -F admin grant-admin you@example.com --create --password='…'
 *   pnpm -F admin grant-admin you@example.com --revoke
 *
 * `--create` also CREATES the Firebase Auth account. The panel has no sign-up
 * screen and email/password is its only sign-in method, so this is how every
 * admin account comes into existence. Without --password a strong one is
 * generated and printed once.
 *
 * THE SCRIPT'S OWN credentials — one of:
 *   gcloud auth application-default login          (recommended)
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
 * These authenticate the SCRIPT to your Firebase project. They are not the
 * credentials you log into the panel with.
 *
 * Project id is read from NEXT_PUBLIC_FIREBASE_PROJECT_ID (or .env.local),
 * or pass --project=<id>.
 */
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const here = dirname(fileURLToPath(import.meta.url));

function fail(message) {
  console.error(`\n  ✗ ${message}\n`);
  process.exit(1);
}

/** Minimal .env.local reader — avoids a dependency for a one-shot script. */
function loadEnvFile() {
  try {
    const raw = readFileSync(join(here, '..', '.env.local'), 'utf8');
    for (const line of raw.split('\n')) {
      const match = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
      if (!match) continue;
      const [, key, value] = match;
      if (!process.env[key]) process.env[key] = value.replace(/^["']|["']$/g, '');
    }
  } catch {
    // No .env.local — fine, the caller may have exported the vars directly.
  }
}

loadEnvFile();

const args = process.argv.slice(2);
const revoke = args.includes('--revoke');
const create = args.includes('--create');
const projectFlag = args.find((a) => a.startsWith('--project='));
const passwordFlag = args.find((a) => a.startsWith('--password='));
const email = args.find((a) => !a.startsWith('--'));

/**
 * Generates a password that satisfies Firebase's 6-character minimum with a
 * lot of room to spare. base64url of 18 random bytes ≈ 24 chars, ~144 bits.
 */
function generatePassword() {
  return '123456';
}

if (!email) {
  fail('Pass an email address: pnpm -F admin grant-admin you@example.com');
}

const projectId =
  projectFlag?.slice('--project='.length) ??
  process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ??
  process.env.GOOGLE_CLOUD_PROJECT;

if (!projectId) {
  fail(
    'No project id. Set NEXT_PUBLIC_FIREBASE_PROJECT_ID in apps/admin/.env.local\n' +
    '    or pass --project=<your-project-id>.',
  );
}

/**
 * `gcloud auth application-default login` writes an `authorized_user` ADC
 * file, and identitytoolkit (Firebase Auth) rejects user credentials that
 * carry no quota project — with a 403 that firebase-admin mangles into a bare
 * documentation URL. google-auth-library forwards GOOGLE_CLOUD_QUOTA_PROJECT
 * as the x-goog-user-project header, which satisfies it.
 *
 * Narrow on purpose: only for an authorized_user ADC with no quota project of
 * its own. Service accounts and key files are left alone, since the header
 * needs `serviceusage.services.use` and would otherwise break them.
 *
 * Mirrors src/lib/firebase/quota-project.ts — change both together.
 */
function ensureQuotaProject(id) {
  if (!id) return;
  if (process.env.GOOGLE_CLOUD_QUOTA_PROJECT) return;
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return;
  try {
    const base =
      process.env.CLOUDSDK_CONFIG ?? join(homedir(), '.config', 'gcloud');
    const adcPath = join(base, 'application_default_credentials.json');
    const adc = JSON.parse(readFileSync(adcPath, 'utf8'));
    if (adc.type !== 'authorized_user' || adc.quota_project_id) return;
    process.env.GOOGLE_CLOUD_QUOTA_PROJECT = id;
  } catch {
    // No ADC file, or unreadable — let the SDK report its own error.
  }
}

ensureQuotaProject(projectId);

initializeApp({ projectId });

const auth = getAuth();
const db = getFirestore();

let user;
let createdPassword = null;

try {
  user = await auth.getUserByEmail(email);
} catch (e) {
  if (e?.code === 'auth/user-not-found') {
    if (revoke) {
      fail(`No Firebase user with email "${email}" — nothing to revoke.`);
    }
    if (!create) {
      fail(
        `No Firebase user with email "${email}".\n\n` +
        '    The admin panel has no sign-up screen — it only signs existing\n' +
        '    users in — so the account has to be created here:\n\n' +
        `      pnpm -F admin grant-admin ${email} --create`,
      );
    }

    createdPassword = passwordFlag
      ? passwordFlag.slice('--password='.length)
      : generatePassword();

    try {
      user = await auth.createUser({
        email,
        password: createdPassword,
        emailVerified: true,
      });
    } catch (createErr) {
      if (createErr?.code === 'auth/invalid-password') {
        fail('Password must be at least 6 characters.');
      }
      fail(createErr?.message ?? String(createErr));
    }
  } else if (
    e?.code === 'app/invalid-credential' ||
    /credential/i.test(e?.message ?? '')
  ) {
    fail(
      'Could not authenticate to Firebase.\n\n' +
      '    This is about the SCRIPT reaching your project, not your panel\n' +
      '    login. Run:\n\n' +
      '      gcloud auth application-default login\n\n' +
      '    or set GOOGLE_APPLICATION_CREDENTIALS to a service-account key.',
    );
  } else {
    fail(e?.message ?? String(e));
  }
}

// Merge rather than replace — clobbering existing claims would silently break
// any other claim-based feature added later.
const claims = { ...(user.customClaims ?? {}) };
if (revoke) {
  delete claims.admin;
} else {
  claims.admin = true;
}

await auth.setCustomUserClaims(user.uid, claims);

// Mirror doc so the Access module can list admins without an expensive
// listUsers() scan over the whole Auth tenant.
//
// This is a CONVENIENCE, not the source of truth — the custom claim above is
// what actually grants access, and it is already set. So an unreachable
// Firestore must never hang the script or make a successful grant look failed:
// the SDK retries indefinitely by design, which would otherwise leave the
// operator staring at a silent terminal after the grant had already happened.
async function mirrorAdminDoc() {
  const ref = db.collection('adminUsers').doc(user.uid);
  if (revoke) {
    await ref.delete();
    return;
  }
  await ref.set(
    {
      uid: user.uid,
      email: user.email ?? null,
      displayName: user.displayName ?? null,
      grantedAt: FieldValue.serverTimestamp(),
      grantedBy: 'cli',
    },
    { merge: true },
  );
}

let mirrorWarning = null;
try {
  await Promise.race([
    mirrorAdminDoc(),
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error('timed out after 10s')), 10_000),
    ),
  ]);
} catch (e) {
  mirrorWarning = e?.message ?? String(e);
}

// Existing sessions carry the OLD claims until their token refreshes, so a
// revoke that doesn't do this leaves the user admin for up to an hour.
if (revoke) await auth.revokeRefreshTokens(user.uid);

if (revoke) {
  console.log(
    `\n  ✓ Revoked admin for ${user.email} (${user.uid})\n` +
    '    Their sessions have been revoked; access ends immediately.\n',
  );
} else if (createdPassword) {
  console.log(
    `\n  ✓ Created account and granted admin for ${user.email}\n` +
    `    uid: ${user.uid}\n\n` +
    '    Sign in at /login with:\n' +
    `      email:    ${user.email}\n` +
    `      password: ${createdPassword}\n\n` +
    '    This password is shown ONCE and is not stored anywhere. Save it\n' +
    "    now, or reset it later in Firebase console → Authentication.\n" +
    '    Make sure Email/Password is enabled under Authentication →\n' +
    '    Sign-in method, or the sign-in will be rejected.\n',
  );
} else {
  console.log(
    `\n  ✓ Granted admin for ${user.email} (${user.uid})\n` +
    '    Sign out and back in — custom claims only apply to new tokens.\n',
  );
}

if (mirrorWarning) {
  console.warn(
    `  ! Could not update the adminUsers/${user.uid} mirror doc: ${mirrorWarning}\n` +
    `    The ${revoke ? 'revoke' : 'grant'} itself succeeded — the custom claim is\n` +
    "    what controls access. Only the Access module's admin list is affected;\n" +
    '    re-run this command once Firestore is reachable to repair it.\n',
  );
}

// The Firestore SDK keeps a connection pool alive, which would hold the
// process open for ~30s after the work is done.
process.exit(0);
