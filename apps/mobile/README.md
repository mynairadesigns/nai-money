# Moneymind

AI-powered personal finance app (Flutter + Firebase). The backend lives in
`../functions` (Firebase Cloud Functions); product/visual specs are in
`../../docs/` (`PRD.md`, `DESIGN.md`).

## Setup

> **You must wire your own Firebase project first.** The seller's Firebase
> config is **not** shipped — `lib/firebase_options.dart`,
> `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`
> are gitignored. Only `*.example` templates are included. The app will not
> compile until you regenerate them for your own project.

1. **Install tooling** (once):
   ```bash
   dart pub global activate flutterfire_cli
   npm install -g firebase-tools
   ```
2. **Create a Firebase project** (Blaze plan — Cloud Functions require it) and
   enable Authentication (Email/Password), Firestore, Storage, Remote Config,
   and Functions.
3. **Generate your Firebase config** from this directory:
   ```bash
   flutterfire configure
   ```
   This writes `lib/firebase_options.dart`, `android/app/google-services.json`,
   and `ios/Runner/GoogleService-Info.plist` for **your** project.
4. **Install deps**: `flutter pub get`.
5. **Codegen** (after any Drift/model change):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
6. **Run**: `flutter run`. Sign up with email + password; the setup flow seeds
   your first wallet.

The AI features, paywall, and ads stay dormant until you deploy the Functions
and publish the Remote Config keys — see the backend setup below.

## Backend (Cloud Functions) & Remote Config

From the repo root:

```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set EXCHANGERATE_API_KEY
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
firebase functions:secrets:set REVENUECAT_API_KEY
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Then publish the buyer-facing Remote Config keys (RevenueCat keys, AdMob unit
ids, free-tier ceilings, prices) in the Firebase console. RevenueCat setup is
documented in `../../docs/REVENUECAT_SETUP.md`.

> AI/RevenueCat/ExchangeRate keys live **only** in Functions secrets — they
> never ship in the app.

## Build releases

```bash
flutter build appbundle --release   # Android (Play Console)
flutter build ipa --release         # iOS (App Store Connect)
```

Replace the AdMob test ids (`ca-app-pub-3940256099942544~…`) in
`ios/Runner/Info.plist` and `android/app/src/main/AndroidManifest.xml` with
your own before release.

## Packaging for distribution

The Firebase config files are untracked but still sit on your disk, so a plain
`zip -r` of the folder would leak them. Build the distributable archive from
**tracked files only** (this excludes your real config, includes the
`.example` templates):

```bash
# from the repo root
git archive --format=zip -o moneymind-1.0.0.zip HEAD
```

## Verification

```bash
flutter analyze      # static analysis
flutter test         # unit/widget tests
```
