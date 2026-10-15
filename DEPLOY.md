# Deploying with GitHub → Firebase (no local tools needed)

Every push to `main` builds the web app and deploys hosting, Cloud Functions,
Firestore rules/indexes and Storage rules. The site is then live at
`https://<project-id>.web.app`. You can add a custom domain later in
Firebase → Hosting → Add custom domain.

## One-time setup

1. **Service account for deploys.** Firebase console → Project settings →
   Service accounts → *Generate new private key*. Then Google Cloud console →
   IAM → find `firebase-adminsdk-…@<project>.iam.gserviceaccount.com` → Edit →
   add role **Owner**. The default roles can't deploy Cloud Functions. This
   project is only for this app, so Owner is the simplest choice. Keep the JSON
   private.
2. **GitHub secrets** (repo → Settings → Secrets and variables → Actions → *Secrets*):
   - `FIREBASE_SERVICE_ACCOUNT`: the whole JSON file
   - `OPENAI_API_KEY` and/or `GEMINI_API_KEY`
   - `EXCHANGERATE_API_KEY`: free at exchangerate-api.com
   - `PAYSTACK_SECRET_KEY`: `sk_test_…` first
   - `REVENUECAT_API_KEY`, `REVENUECAT_WEBHOOK_SECRET`: leave unset until you do mobile
3. **Run "Set Firebase secrets"** once from the Actions tab.
4. **Run "Deploy"**, or just push to `main`.

## Paystack (when ready)

Add these under *Variables* (not Secrets): `PAYSTACK_PLAN_MONTHLY`,
`PAYSTACK_PLAN_YEARLY`, `PAYSTACK_LIFETIME_AMOUNT` (kobo), and
`PAYSTACK_ALLOWED_ORIGINS` if you use a custom domain. Re-run Deploy, then set
the webhook URL in Paystack:
`https://europe-west1-<project-id>.cloudfunctions.net/handlePaystackWebhook`.

See WEB_SETUP.md for everything else (CORS, test cards, going live).
