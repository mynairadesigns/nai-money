# Temi Finance on the web — setup guide

This copy of Temi Finance builds for **Android, iOS and web** from the same code.
On web, Premium is sold through **Paystack** instead of the app stores.

Do these steps in order. Steps 1–4 are one-time setup.

---

## 0. What changed (summary)

| Area | Mobile | Web |
|---|---|---|
| Local database (Drift) | SQLite file | SQLite in WebAssembly (`web/sqlite3.wasm` + `web/drift_worker.js`), stored in the browser |
| Receipt scanner | Camera / gallery | Camera (phones) or file upload; images resized to ≤ 2000px |
| Google sign-in | Native Google sheet | Firebase popup |
| Apple sign-in | iOS only | Hidden |
| Payments | RevenueCat (App Store / Play) | **Paystack** (card, bank transfer, USSD) |
| Ads (AdMob) | On (if enabled) | Off — AdMob has no web SDK |
| Local notifications | On | Hidden — not supported in browsers |
| App lock | PIN + biometric | PIN only |
| Backup export | Share sheet | Downloads a `.json` file |
| Layout | Bottom bar | Side rail on wide screens; content capped at 1100px |

**A security fix that affects mobile too.** In the original code, any signed-in user
could write `premiumStatus: 'premium'` to their own Firestore document and get
unlimited AI calls (paid for by you). On the web that takes about 10 seconds in the
browser console. `firestore.rules` now blocks clients from writing billing fields.
Only Cloud Functions can set them. The mobile app's quick premium sync now calls the
existing `refreshEntitlement` function instead of writing directly. That function
needs the `REVENUECAT_API_KEY` secret (step 3), which the original setup guide
already asks for.

**Heads-up about the listing:** the CodeCanyon page says the on-device database
uses SQLCipher, but the code doesn't (see `lib/data/local/app_database.dart`: *"SQLCipher
encryption will be wired up in P7 polish"*). Local data is **not** encrypted on
either mobile or web. Raise this with the seller.

---

## 1. Add the web app to Firebase

From `apps/mobile`:

```bash
flutterfire configure --platforms=android,ios,web
```

This regenerates `lib/firebase_options.dart` with a web entry.

In the Firebase console:
- **Authentication → Sign-in method:** make sure Email/Password and Google are enabled.
- **Authentication → Settings → Authorized domains:** add your web domain
  (`localhost` is already there for testing).

## 2. Allow the browser to read receipts from Storage (CORS)

The web app downloads the temporary receipt image to move it to its permanent
location. Browsers block that unless the bucket allows your domain.

Edit `storage.cors.json` (repo root) and replace `https://YOUR-WEB-DOMAIN`, then:

```bash
gsutil cors set storage.cors.json gs://YOUR-PROJECT-ID.appspot.com
# (newer projects: gs://YOUR-PROJECT-ID.firebasestorage.app)
```

## 3. Set up Paystack

1. **Create two plans.** Paystack dashboard → *Products → Plans → Create plan*.
   - "Temi Finance Premium Monthly", interval **Monthly**, e.g. ₦4,500
   - "Temi Finance Premium Yearly", interval **Annually**, e.g. ₦27,000

   Copy each plan code (`PLN_…`). **Prices shown in the app come from these plans**,
   so to change a price, change it in Paystack.
2. **Function config.** Copy `apps/functions/.env.example` to `apps/functions/.env`
   and fill in the plan codes, the lifetime price **in kobo** (or `0` to hide
   lifetime), and your web domain(s).
3. **Secret key.** Use your **test** key (`sk_test_…`) first:
   ```bash
   firebase functions:secrets:set PAYSTACK_SECRET_KEY
   ```
   If you haven't already set it for mobile:
   ```bash
   firebase functions:secrets:set REVENUECAT_API_KEY
   ```
4. **Deploy** functions and the new rules:
   ```bash
   firebase deploy --only functions,firestore:rules
   ```
5. **Webhook.** Paystack dashboard → *Settings → API Keys & Webhooks* → **Webhook URL**:
   ```
   https://europe-west1-YOUR-PROJECT-ID.cloudfunctions.net/handlePaystackWebhook
   ```
   Set it in **both** Test and Live mode when you go live.

### How Paystack billing works here

- Monthly and yearly are Paystack subscriptions. Paystack charges the card each
  period, and every successful charge adds one period (+3 days grace) to
  `users/{uid}.premiumExpiry`.
- If the user cancels or the card fails, no charge arrives and Premium simply ends
  at the end of the paid period. Users cancel or change their card from
  **Settings → Subscription → Manage subscription**, which opens a Paystack-hosted page.
- Lifetime is a one-off charge.
- Each charge is applied exactly once even though it can arrive from both the webhook
  and the browser's return-from-checkout check (`paystackTransactions/{reference}`).
- Paystack users get `premiumSource: 'paystack'`. A RevenueCat expiry or cancellation
  for the same person won't downgrade them, so someone who bought on the web
  keeps Premium in the mobile app too, because both read the same Firestore field.
- New functions: `getPaystackPrices`, `startPaystackCheckout`,
  `verifyPaystackPayment`, `getPaystackManageLink`, `handlePaystackWebhook`
  (`apps/functions/src/billing/paystack.ts`).

## 4. Build and deploy the web app

```bash
cd apps/mobile
flutter pub get
flutter run -d chrome          # test locally first
flutter build web --release
cd ../..
firebase deploy --only hosting
```

`firebase.json` now has a `hosting` section that serves `apps/mobile/build/web`.
Any static host works (Vercel, Netlify, Cloudflare Pages, Nginx) as long as
`.wasm` files are served with `Content-Type: application/wasm`.

> **If you ever upgrade `drift` or `sqlite3`** in `pubspec.lock`, replace
> `web/drift_worker.js` and `web/sqlite3.wasm` with the matching versions from
> https://github.com/simolus3/drift/releases and
> https://github.com/simolus3/sqlite3.dart/releases. Mismatched versions break
> the database on web. The shipped files match drift 2.33.0 and sqlite3 3.3.1.

## 5. Test checklist (Paystack test mode)

Paystack test card: **4084 0840 8408 4081**, CVV **408**, any future expiry,
PIN **0000**, OTP **123456**.

- [ ] Sign up with email, sign out, sign in with Google (popup)
- [ ] Add a wallet and a transaction → reload the page → data still there
- [ ] Scan a receipt (upload a photo) → fields pre-filled
- [ ] AI Coach replies
- [ ] Settings → Subscription → Upgrade → Paystack → pay with the test card →
      you land back in the app with "welcome to Premium" and the Premium badge
- [ ] Firestore: `users/{uid}` shows `premiumStatus: premium`, `premiumSource: paystack`
- [ ] Manage subscription opens the Paystack page; cancelling there keeps Premium
      until the expiry date
- [ ] Wide desktop window → side navigation rail, content centred
- [ ] The mobile app still builds: `flutter build apk`

Then switch to live keys:
`firebase functions:secrets:set PAYSTACK_SECRET_KEY` with `sk_live_…`, recreate the
plans in live mode (plan codes differ between test and live), update `.env`, and redeploy.

## Files touched

**Flutter (`apps/mobile`)**: `web/` (new), `lib/main.dart`,
`lib/core/routing/app_router.dart`, `lib/data/local/app_database.dart`,
`lib/data/remote/{auth,billing,firestore,storage,paystack_billing}_service.dart`,
`lib/data/sync/sync_lifecycle_provider.dart`,
`lib/features/ads/data/ads_service.dart`,
`lib/features/billing/{presentation/paywall_screen,presentation/subscription_screen,presentation/web_paywall_screen,providers/paystack_providers}.dart`,
`lib/features/notifications/data/notification_service.dart`,
`lib/features/security/data/security_service.dart`,
`lib/features/settings/presentation/{backup,settings}_screen.dart`,
`lib/features/shared/main_shell.dart`,
`lib/features/transactions/{presentation/receipt_scanner_screen,widgets/receipt_picker_sheet}.dart`

**Functions (`apps/functions`)**: `src/billing/paystack.ts` (new),
`src/billing/paystack_logic.ts` (+ tests, new), `src/billing/handle_revenuecat_webhook.ts`,
`src/billing/refresh_entitlement.ts`, `src/index.ts`, `src/types/user_document.ts`,
`.env.example` (new)

**Root**: `firestore.rules`, `firebase.json`, `storage.cors.json` (new), `WEB_SETUP.md` (new)
