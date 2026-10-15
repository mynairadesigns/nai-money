# Moneymind Admin

A Next.js operations console for a Moneymind deployment: see who signed up, what your AI features are costing, whether RevenueCat is reaching you, and why a particular user is hitting a limit — plus a validated editor for the Remote Config keys that configure the mobile app.

It talks to the **same Firebase project** as the mobile app (`../mobile`) and its Cloud Functions (`../functions`). Full setup walkthrough: [`../../docs/ADMIN_SETUP.md`](../../docs/ADMIN_SETUP.md).

## How access works

> **Signing in is not enough.** The panel is gated on a Firebase Auth custom claim, `admin: true`. An ordinary Moneymind user has a perfectly valid Firebase account and cannot get in. You grant the first admin from a terminal (step 4 below); after that you can grant others from inside the panel.

All data is read **server-side** through the Firebase Admin SDK. The browser never gets a Firestore handle, so `firestore.rules` stays strictly owner-scoped — you do **not** need to loosen your security rules to run this.

## Setup

> **No Firebase config ships with this source.** You must point the panel at your own project. Nothing here is secret — these are the public web app identifiers — but the panel will not start until they are set.

1. **Install dependencies** (from the repo root, so the pnpm workspace resolves):

   ```bash
   pnpm install
   ```

2. **Create a Web app** in your Firebase project if you don't have one: Firebase console → Project settings → Your apps → Add app → Web. Copy the config values.

3. **Configure the environment:**

   ```bash
   cp apps/admin/.env.example apps/admin/.env.local
   # then fill in the NEXT_PUBLIC_FIREBASE_* values
   ```

4. **Enable Email/Password** in Firebase console → Authentication → Sign-in method. That is the panel's only sign-in method; leave it disabled and every sign-in is rejected.

5. **Create your admin account and grant the claim.**

   First authenticate the CLI — this is how the *script* reaches your project, and has nothing to do with the credentials you log in with:

   ```bash
   gcloud auth application-default login
   ```

   Then create the account. The panel has no sign-up screen, so this is the only way an admin comes into existence:

   ```bash
   pnpm -F admin grant-admin you@example.com --create
   ```

   It prints a generated password once. Pass your own with `--password='…'` if you prefer.

   For an account that already exists, drop `--create` to just grant the claim. Either way, **sign out and back in afterwards** — custom claims are baked into the token at sign-in, so an existing session still carries the old, claim-less one.

   To remove access later: `pnpm -F admin grant-admin them@example.com --revoke`.

6. **Run it:**

   ```bash
   pnpm -F admin dev
   ```

   Then open http://localhost:3000.

## Deploy

Vercel, from your GitHub repo. In **Settings → Build & Deployment**:

| Setting | Value |
| --- | --- |
| Root Directory | `apps/admin` |
| Include files outside the root directory | **ON** (the pnpm workspace and its single lockfile are one level up) |

Then set the environment variables in **Settings → Environment Variables** — nothing configuration-related is committed:

- the four `NEXT_PUBLIC_FIREBASE_*` values (build-time; a change needs a redeploy)
- `FIREBASE_SERVICE_ACCOUNT_JSON` — the whole service-account key JSON, marked **Sensitive**

> **Vercel is not a Google runtime, so Application Default Credentials do not exist there.** The Admin SDK cannot authenticate without an explicit key. That key has full administrative access to your Firebase project and bypasses security rules — never commit it, never put it in a `NEXT_PUBLIC_*` variable, and rotate it if exposed. Full walkthrough: [`../../docs/ADMIN_SETUP.md`](../../docs/ADMIN_SETUP.md).

Firebase App Hosting is **not** usable here: its buildpack demands a lock file inside the backend root directory, and pnpm keeps only one at the workspace root (firebase-tools#7478).

### Alternative: any container host

`output: 'standalone'` is enabled everywhere except Vercel, so the app builds to a self-contained server:

```bash
# from the repo root
gcloud run deploy moneymind-admin --source . --region asia-southeast1
```

or build `apps/admin/Dockerfile`. On a Google runtime the runtime service account supplies credentials, so no key file is needed — **never bake one into an image.**

## Verification

```bash
pnpm -F admin lint
pnpm -F admin typecheck
pnpm -F admin test
pnpm -F admin build
```

To exercise the sign-in gate locally, start the Auth emulator and set `NEXT_PUBLIC_USE_FIREBASE_EMULATORS=true` in `.env.local`:

```bash
firebase emulators:start --only auth --project demo-moneymind
```

(The Firestore emulator needs JDK 21 or newer; the Auth emulator does not.)

## Notes

- **Theme** follows your OS by default; the toggle in the header pins light or dark.
- **Remote Config edits** reach the mobile app on its next fetch (up to an hour in release builds) and reach Cloud Functions only as their instances recycle — the editor says so next to the publish button.
- **Cloud Functions read only a key's default value**, so Remote Config *conditions* and percentage rollouts do not affect server-side behavior.
