'use client';

import { getApp, getApps, initializeApp, type FirebaseApp } from 'firebase/app';
import {
  connectAuthEmulator,
  getAuth,
  type Auth,
} from 'firebase/auth';

/**
 * Browser-side Firebase, used for EXACTLY ONE THING: signing the operator in
 * and handing the resulting ID token to `POST /api/auth/session`.
 *
 * There is intentionally no Firestore client here. All data access happens
 * server-side through the Admin SDK (see ./admin.ts). If you find yourself
 * wanting `getFirestore` in this file, add a server action or route handler
 * instead — a browser Firestore handle would be bound by the owner-scoped
 * security rules anyway and could not read other users' data.
 */
const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

export function isFirebaseConfigured(): boolean {
  return Boolean(config.apiKey && config.authDomain && config.projectId);
}

function clientApp(): FirebaseApp {
  return getApps().length ? getApp() : initializeApp(config);
}

let _emulatorConnected = false;

export function clientAuth(): Auth {
  const auth = getAuth(clientApp());
  if (
    !_emulatorConnected &&
    process.env.NEXT_PUBLIC_USE_FIREBASE_EMULATORS === 'true'
  ) {
    connectAuthEmulator(auth, 'http://localhost:9099', {
      disableWarnings: true,
    });
    _emulatorConnected = true;
  }
  return auth;
}
