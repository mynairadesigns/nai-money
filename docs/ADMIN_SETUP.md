# Admin Panel Setup

> **TL;DR** — Install deps, point `apps/admin/.env.local` at your Firebase project, enable Email/Password sign-in, run `pnpm -F admin grant-admin you@example.com --create` to create your admin account and give it the `admin` custom claim, then `deploy it on Vercel with Root Directory `apps/admin`. Requires the Blaze plan (which Cloud Functions already need).

The admin panel (`apps/admin`) is a Next.js operations console for your Homa Finance deployment. It shows user counts and growth, what your AI features are costing, whether RevenueCat is reaching you, and why a given user is hitting a limit — and it gives you a validated editor for the Remote Config keys that configure the mobile app.

It is optional. The mobile app works without it.

---

## 1. How access control works

Access is gated on a Firebase Auth **custom claim**, `admin: true` — not on a password, not on an email allowlist.

This matters for two reasons:

- **An ordinary Homa Finance user cannot get in.** They have a valid Firebase account; they do not have the claim. Signing in successfully is not the same as being authorized.
- **You do not need to change your security rules.** The panel reads everything server-side through the Firebase Admin SDK, which bypasses Firestore rules entirely. Your `firestore.rules` stays strictly owner-scoped (`request.auth.uid == userId`) exactly as it ships. Nothing about running the panel widens what a mobile client can reach.

The panel never puts a Firestore handle in the browser. The browser's only job is to sign you in and hand the resulting ID token to the server, which verifies it, checks the claim, and issues an httpOnly session cookie.

---

## 2. Prerequisites

- A Firebase project with the mobile app already set up (see [`../apps/mobile/README.md`](../apps/mobile/README.md)).
- **Blaze (pay-as-you-go) plan.** Already required for Cloud Functions.
- Node.js 22 and pnpm.
- firebase-tools **14.4 or newer** — `npx firebase --version`.
- The `gcloud` CLI, for the one-time admin bootstrap.

---

## 3. Configure the panel

Install from the repository root so the pnpm workspace resolves:

```bash
pnpm install
```

If you don't already have a Web app registered, create one: **Firebase console → Project settings → Your apps → Add app → Web**. Then copy the config into an env file:

```bash
cp apps/admin/.env.example apps/admin/.env.local
```

Fill in the four `NEXT_PUBLIC_FIREBASE_*` values. These are public identifiers, not secrets — they are safe in a build.

Enable **Email/Password** under **Authentication → Sign-in method**. That is the panel's only sign-in method — leave it disabled and every sign-in is rejected.

---

## 4. Grant yourself admin

This is the one step you cannot do from inside the panel — you cannot grant yourself a claim through a door you cannot open.

First authenticate the CLI. **This is how the script reaches your Firebase project — it is not the credential you log into the panel with:**

```bash
gcloud auth application-default login
```

Then create your admin account. The panel has **no sign-up screen** — it only signs existing users in — so the CLI is the only way an admin comes into existence:

```bash
pnpm -F admin grant-admin you@example.com --create
```

This creates the Firebase Auth user, grants the `admin` claim, and prints a generated password **once**:

```
  ✓ Created account and granted admin for you@example.com
    uid: s3aE05X9iQVg04vd6DRz3Tjk6oza

    Sign in at /login with:
      email:    you@example.com
      password: x3mxUaNaxfoH4ZXn-xvRj5nz
```

Save it — it is not stored anywhere. Supply your own instead with `--password='…'` (minimum 6 characters). If you lose it, reset it in Firebase console → Authentication → Users.

For an account that already exists, drop `--create` to grant the claim alone:

```bash
pnpm -F admin grant-admin you@example.com
```

**Sign out and back in.** Custom claims are baked into the token at sign-in, so an existing session still carries the old, claim-less token.

To revoke someone later:

```bash
pnpm -F admin grant-admin them@example.com --revoke
```

Revoking also kills their active sessions, so access ends immediately rather than whenever their token would have expired.

After the first admin exists, use the panel's **Access** module to grant and revoke others.

---

## 5. Deploy the security rules and indexes

The panel adds explicit deny rules for its own collections and one composite index for the premium-filtered user list. Deploy both:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Index builds are asynchronous — the premium filter in the Users module returns an error until the index finishes building. Watch progress in **Firebase console → Firestore → Indexes**.

---

## 6. Deploy the panel (Vercel)

The panel is a standard Next.js app, so Vercel deploys it from your GitHub repo with no extra tooling.

**Why not Firebase App Hosting:** its buildpack requires a dependency lock file inside the backend's root directory, and pnpm keeps exactly one `pnpm-lock.yaml` at the workspace root. Pointing it at `apps/admin` fails with `fah/missing-lock-file` (firebase-tools#7478). Vercel resolves pnpm workspaces natively.

### 1. Import the repo

In Vercel: **Add New → Project → import your GitHub repository**. Then under **Settings → Build & Deployment**:

| Setting | Value |
| --- | --- |
| Root Directory | `apps/admin` |
| Include files outside the root directory | **ON** — required; the workspace and its single lockfile are one level up |
| Framework Preset | Next.js (auto-detected) |

Leave the build and install commands on their defaults — Vercel detects pnpm from the root lockfile.

### 2. Environment variables

**Settings → Environment Variables.** Nothing configuration-related is committed, so everything the panel needs is set here:

| Variable | Notes |
| --- | --- |
| `NEXT_PUBLIC_FIREBASE_API_KEY` | build-time |
| `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN` | build-time |
| `NEXT_PUBLIC_FIREBASE_PROJECT_ID` | build-time |
| `NEXT_PUBLIC_FIREBASE_APP_ID` | build-time |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | **secret** — see below |
| `NEXT_PUBLIC_DEMO_MODE` | optional; `true` makes the panel read-only |
| `REVENUECAT_API_KEY` | optional; enables the live entitlement lookup |

Copy the four `NEXT_PUBLIC_*` values from your `apps/admin/.env.local`. They are inlined into the client bundle at build time, so changing one needs a redeploy, not just an edit.

### 3. The service-account key — read this

Firebase's Admin SDK normally authenticates through Application Default Credentials, which a Google runtime provides automatically. **Vercel is not a Google runtime, so ADC does not exist there.** You must supply a key explicitly:

1. Firebase console → **Project settings → Service accounts → Generate new private key**.
2. Open the downloaded JSON and copy the whole thing.
3. In Vercel, add `FIREBASE_SERVICE_ACCOUNT_JSON` with that JSON as the value, on one line, and mark it **Sensitive**.

> **This is a real credential with full administrative access to your Firebase project** — it bypasses all security rules. Treat it accordingly: never commit it, never put it in a `NEXT_PUBLIC_*` variable (those are public), restrict who can read your Vercel project's environment variables, and rotate it in the Firebase console if it is ever exposed. It is the one meaningful security cost of hosting outside Google.

### 4. Region

Set the function region near your data. Firestore and all Cloud Functions are in `europe-west1` (Singapore), so pick **Singapore (sin1)** under Settings → Functions. Leaving it in the US adds a round trip to every Firestore read.

> Set it in the dashboard rather than in `vercel.json`. Multi-region is a Pro feature, so a `regions` entry in the file is a deploy-time failure on Hobby, whereas the project setting works on every plan.

`apps/admin/vercel.json` is deliberately minimal — just `$schema` and `framework`. Its schema sets `additionalProperties: false`, so **any key Vercel does not recognise fails the deploy** with `should NOT have additional property`. JSON has no comment syntax either, so there is nowhere in that file to explain itself; that is what this document is for.

### 5. Deploy

Push to your default branch and Vercel builds automatically. Every pull request also gets a preview deployment — those share the same environment variables, so a preview has the same production access unless you scope the variables per environment.

---

## 7. Alternative hosting

The app also builds to a standalone Node server (`output: 'standalone'`, enabled everywhere except Vercel), so any container host works. From the repository root:

```bash
gcloud run deploy homa-admin --source . --region europe-west1
```

or build `apps/admin/Dockerfile` yourself. On a Google runtime the runtime service account supplies credentials automatically, so `FIREBASE_SERVICE_ACCOUNT_JSON` is not needed — grant that account `roles/datastore.user`, `roles/firebaseauth.admin`, and `roles/firebaseremoteconfig.admin` instead. **Never bake a service-account key into an image.**

---

## Troubleshooting

**"This account does not have admin access."**
The claim is missing, or your token predates it. Run `grant-admin`, then sign out and back in — the token is only refreshed at sign-in.

**`grant-admin` says "Could not authenticate to Firebase."**
Run `gcloud auth application-default login`, or set `GOOGLE_APPLICATION_CREDENTIALS` to a service-account key path.

**An error that is just a bare URL, like `✗ //cloud.google.com/docs/authentication/adc-troubleshooting/user-creds .`**
This is the missing-quota-project 403, mangled by firebase-admin. `gcloud auth application-default login` writes a *user* credential, and the Identity Toolkit API (Firebase Auth) rejects user credentials that carry no quota project.

Both the script and the panel now set one automatically for local development, so you should not see this. If you do — for instance because you set `GOOGLE_CLOUD_QUOTA_PROJECT` to something else — fix it globally with:

```bash
gcloud auth application-default set-quota-project your-project-id
```

This does not affect production, where the runtime service account needs no quota project.

**`grant-admin` says "No Firebase user with email ..."**
The account doesn't exist yet. Re-run with `--create` to make it.

**`grant-admin` warns it could not update the `adminUsers` mirror doc.**
Harmless to access — the custom claim is what grants it, and that succeeded. Only the Access module's admin list is affected. Re-run once Firestore is reachable to repair it.

**Sign-in is rejected even though the account exists.**
Check that **Email/Password** is enabled under Firebase console → Authentication → Sign-in method.

**Vercel build fails to resolve dependencies.**
Turn on **Include files outside the root directory** in Settings → Build & Deployment. The pnpm workspace and its single lockfile live one level above `apps/admin`, and without that setting Vercel cannot see them.

**Pages 500 with a credentials error.**
`FIREBASE_SERVICE_ACCOUNT_JSON` is missing or malformed. It must be the entire key JSON on one line. There is no Application Default Credentials on Vercel.

**The premium filter errors on the Users page.**
Its composite index is still building, or wasn't deployed. See §5.

**A Remote Config change didn't take effect.**
The mobile app caches for up to an hour in release builds. Cloud Functions cache per instance and pick up changes as instances recycle. Also note Functions read only a key's **default value** — conditions and percentage rollouts do not affect server-side behavior.

**The Firestore emulator won't start.**
It needs JDK 21 or newer. The Auth emulator is pure Node and runs on any JDK, which is enough to exercise sign-in locally.

---

## Related

- [`../apps/admin/README.md`](../apps/admin/README.md) — developer-oriented quick reference
- [`REVENUECAT_SETUP.md`](REVENUECAT_SETUP.md) — subscription setup
- [`codecanyon/index.html`](codecanyon/index.html) — full product documentation
