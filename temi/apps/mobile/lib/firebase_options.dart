// Firebase config for the Temi Finance Firebase project (`temi-finance`).
//
// Web is configured. Android / iOS are not yet: when you build the mobile
// apps, run `flutterfire configure --platforms=android,ios,web` from
// apps/mobile and it will regenerate this file with all three.
//
// These values are public identifiers (they ship inside every web/mobile
// build) — access is controlled by firestore.rules / storage.rules and
// Firebase Auth, not by keeping this file secret.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'Mobile Firebase apps are not configured yet — run '
          '`flutterfire configure --platforms=android,ios,web` in apps/mobile.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA4-R6j4Wd6VEzBzjx9j9WEUXooqeTeOIw',
    appId: '1:160705895217:web:3e6294f6a2a5ba6750ee10',
    messagingSenderId: '160705895217',
    projectId: 'temi-finance',
    authDomain: 'temi-finance.firebaseapp.com', // switch to temi.finance after OAuth redirect URI is added
    storageBucket: 'temi-finance.firebasestorage.app',
    measurementId: 'G-R3J7957V2D',
  );
}
