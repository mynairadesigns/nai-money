// Firebase config for the `nai-money` project.
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
    apiKey: 'AIzaSyBF1gW6KkhASy9p6Zxu2TwplWTN72szDvw',
    appId: '1:924103830011:web:6a64a78e51aa6c3d40435e',
    messagingSenderId: '924103830011',
    projectId: 'nai-money',
    authDomain: 'homa.finance', // custom domain → Google sign-in shows homa.finance
    storageBucket: 'nai-money.firebasestorage.app',
    measurementId: 'G-WCZB7ZQN7B',
  );
}
