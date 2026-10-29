# RevenueCat Setup — Temi Finance

How to wire up subscriptions for your Temi Finance deployment. RevenueCat is the
subscription source of truth; the app and a Firebase webhook both mirror
entitlement state into Firestore (`users/{uid}.premiumStatus` + `premiumExpiry`),
which is what the server-side AI quota bypass reads.

> **TL;DR for the webhook secret:** `REVENUECAT_WEBHOOK_SECRET` is **not** issued
> by RevenueCat. You invent it (a random string), store it in Firebase, and paste
> `Bearer <that secret>` into the RevenueCat webhook's Authorization header.

---

## Two paths: Test Store vs. real stores

You do **not** need App Store Connect / Google Play products configured just to
try the premium flow. There are two ways to set this up:

- **Test Store** — RevenueCat's built-in sandbox for testing the integration
  (paywall, purchase, entitlement granting) with **no store setup**. Its key
  starts with `test_`. Use this to develop and demo. → [Testing with the Test Store](#testing-with-the-test-store).
- **Real stores** — App Store + Play Store apps with store-configured products.
  Required for production / real money. → the numbered sections below
  (**§1–§8** are the production path).

Start with the Test Store to verify everything works, then add the real stores
when you're ready to ship.

---

## Testing with the Test Store

RevenueCat's **Test Store** is purpose-built for exactly this: testing the SDK
integration (offerings, paywall, purchase flow, entitlement granting) **without**
App Store Connect or Google Play setup. The key it issues starts with `test_`.

> If the only API key you can find starts with `test_`, you (or the project) are
> using the Test Store. That's fine for development — it is **not** the native
> `appl_`/`goog_` key, which you only need for production (§4).

### What works with the Test Store

The full premium path works end-to-end for testing:

- `Purchases.configure(test_key)` ✓
- `getOfferings()` returns your packages → the paywall renders ✓
- Buying a package grants the **`premium`** entitlement ✓
- `customerInfoProvider` → `isPremiumProvider` flips to premium ✓
- The client's `_mirrorToFirestore` writes `premiumStatus: 'premium'` to Firestore
  → the **server-side AI quota bypass picks it up** ✓

So you can exercise the paywall, the upgrade flow, ad removal, and the AI bypass
without any real store.

### How to wire it into Temi Finance

1. In RevenueCat, set up the **Test Store products**, attach them to an
   entitlement named exactly **`premium`** ⚠️, and add them to your **current
   Offering**'s packages (Monthly / Annual / Lifetime). Without this the paywall
   has nothing to show and purchases grant nothing. (Same as §3/§5 below, just
   using Test Store products.)
2. Put the `test_` key in the Remote Config slot for your test platform —
   `revenuecat_api_key_android` on Android, `revenuecat_api_key_ios` on iOS. The
   Test Store is platform-agnostic, so it's fine to set the same `test_` key in
   **both** slots so it works on either device. **Publish** Remote Config.

### Caveats

- **Testing only.** The Test Store can't take real money or ship to real users.
  For production you still need real App Store + Play Store apps (→ `appl_`/`goog_`
  keys) and store-configured products — see §1–§8.
- **The webhook path.** The premium flow above works via the **client fast-path
  mirror**, so it's covered regardless. It's not guaranteed that Test Store
  purchases fire the RevenueCat → Firebase webhook (the authoritative server
  path). If they do, you'll see `RevenueCat: granted premium…` in
  `firebase functions:log`; if not, the client mirror still updates Firestore so
  premium + AI bypass still work. To truly validate the **webhook**, use a real
  App Store **sandbox** / Play **internal-test** purchase later.

---

## 1. The three RevenueCat credentials (don't mix them up)

> These are the **production** credentials. For dev/testing you can skip ahead to
> [Testing with the Test Store](#testing-with-the-test-store) and use the `test_`
> key instead.

RevenueCat exposes several keys that go to **different** places. Getting these
crossed is the #1 setup mistake.

| Credential | Where you get it | Where it goes | Secret? |
| --- | --- | --- | --- |
| **Public SDK keys** (`appl_…`, `goog_…`) | RC → Project Settings → **API Keys** (per-app public keys) | Remote Config `revenuecat_api_key_ios` / `revenuecat_api_key_android` | No — safe to ship in the app |
| **Secret REST key** (`sk_…`) | RC → Project Settings → API Keys → **Secret keys** | Firebase secret `REVENUECAT_API_KEY` (used by the `refreshEntitlement` function) | **Yes — server only** |
| **Webhook auth secret** | **You invent it** (see below) | RC webhook header **and** Firebase secret `REVENUECAT_WEBHOOK_SECRET` | **Yes** |
| **Test Store key** (`test_…`) | RC → add a **Test Store** app | Remote Config `revenuecat_api_key_ios` / `_android` (dev only) | No — testing only, never production |

### Generating the webhook secret

```bash
openssl rand -hex 32
```

Keep the output. You'll use it in two places:

- **Firebase** — stored as the **bare** value (no `Bearer ` prefix).
- **RevenueCat** — stored as the Authorization header value `Bearer <secret>`.

The webhook function builds `Bearer ${REVENUECAT_WEBHOOK_SECRET}` and compares it
to the incoming `Authorization` header; a mismatch returns `401`.

---

## 2. Create the products in the stores

> Production path only — **skip this** if you're testing with the
> [Test Store](#testing-with-the-test-store).

Products live in the app stores — RevenueCat only reads them. Create them
**first**.

**App Store Connect** → 3 in-app purchases (suggested IDs + PRD pricing):

| Product ID | Type | Price |
| --- | --- | --- |
| `temi_premium_monthly` | Auto-renewing subscription | $4.99 / month |
| `temi_premium_yearly` | Auto-renewing subscription | $29.99 / year |
| `temi_premium_lifetime` | Non-consumable | $79.99 one-time |

**Google Play Console** → the equivalent subscriptions + one-time product (the
same IDs are fine).

> Product IDs are your choice — the paywall reads them dynamically from
> RevenueCat offerings. Only the **entitlement name** in step 3 is hardcoded.

---

## 3. Configure the RevenueCat project

1. Create an account at [app.revenuecat.com](https://app.revenuecat.com) → **new Project**.
2. Add an **iOS app** and an **Android app**; connect each to App Store Connect /
   Google Play (App Store shared secret + Play service-account JSON — RevenueCat
   walks you through it).
3. **Products** → import/add the 3 store products.
4. **Entitlements** → create one named **exactly `premium`** ⚠️
   - The app checks `entitlements.active['premium']`. Any other name and premium
     never activates.
   - Attach all 3 products to this entitlement.
5. **Offerings** → use the default/**current** offering; add 3 **Packages**
   (Monthly / Annual / Lifetime) and attach the matching products. The paywall
   renders whatever the current offering contains.

---

## 4. Public API keys → Remote Config

The public SDK key is **per-app / per-platform**, not per-project: each platform
app you add gets its own key (`appl_…` for the App Store app, `goog_…` for the
Play Store app). So **seeing only one key is normal if you've only added one
platform app** — the app uses the platform-matching key at runtime (iOS reads
`revenuecat_api_key_ios`, Android reads `revenuecat_api_key_android`). Ship one
platform → set one key; ship both → add both apps and set both.

**Where to find them:** Project switcher → **⚙️ Project settings → API keys** tab
→ the **App-specific (public) keys** section lists one key per app. (The `sk_…`
Secret key for `REVENUECAT_API_KEY` is on the same page under "Secret keys".) If
the page shows no public keys, no platform app exists yet — add one under
**Project settings → Apps** (the key is generated when the app is created).

Copy each key into **Firebase Console → Remote Config**, then **publish**:

| Remote Config key | Value |
| --- | --- |
| `revenuecat_api_key_ios` | the Apple app's public key (`appl_…`) — set when you ship iOS |
| `revenuecat_api_key_android` | the Play app's public key (`goog_…`) — set when you ship Android |

The app reads these post-sign-in to call `Purchases.configure(...)`. The two
keys are not interchangeable — each only works for its own platform app.

---

## 5. Webhook → RevenueCat

RC → **Integrations → Webhooks → Add**:

- **URL** — your deployed function's trigger URL. Get the exact value from the
  `firebase deploy` output or **Firebase Console → Functions →
  `handleRevenueCatWebhook` → trigger URL**. It is region-pinned to
  `europe-west1`:

  ```
  https://europe-west1-<your-project-id>.cloudfunctions.net/handleRevenueCatWebhook
  ```

- **Authorization header value** — `Bearer <your-secret>` (include the literal
  `Bearer ` prefix; that's exactly what the handler compares against).

The webhook handles these events:

- **Grant premium:** `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`,
  `UNCANCELLATION`, `NON_RENEWING_PURCHASE` (lifetime → expiry ~100 years out).
- **Revoke premium:** `EXPIRATION`, `CANCELLATION`, `BILLING_ISSUE`.
- All other events are acknowledged with `200` and ignored.

---

## 6. Firebase secrets + deploy

```bash
# Bare secret (NO "Bearer " prefix) — must match the value used in step 5.
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET

# The sk_… Secret REST key from RevenueCat (used by refreshEntitlement).
firebase functions:secrets:set REVENUECAT_API_KEY

firebase deploy --only functions
```

> In **Firebase** you store the bare secret; in **RevenueCat** you store
> `Bearer ` + the same secret.

---

## 7. App User ID — already wired (no action)

On sign-in the app calls `Purchases.logIn(firebaseUid)`, so RevenueCat's
`app_user_id` **is** the Firebase uid — which is the field the webhook uses to
locate `users/{uid}`. They line up automatically; there's nothing to configure
in the dashboard.

---

## 8. Verify end-to-end

1. Make a **sandbox / TestFlight** purchase → the app shows Premium immediately
   (client fast-path mirror to Firestore).
2. Within ~30s the webhook fires. `firebase functions:log` shows
   `RevenueCat: granted premium to <uid> (INITIAL_PURCHASE)`, and
   `users/<uid>.premiumStatus == 'premium'` in Firestore.
3. Trigger a 6th AI action that month → it **succeeds** (premium bypasses the
   free-tier cap); `users/<uid>/aiUsage/<YYYY-MM>.premiumCalls` increments.
4. Cancel in sandbox → webhook logs `revoked premium` → Firestore flips back to
   `free`.

---

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Webhook returns `401` in logs | Authorization header in RC isn't `Bearer ` + the exact Firebase secret, or you redeployed without setting the secret. |
| Purchase succeeds but never premium | Entitlement isn't named exactly `premium`, or no product is attached to it. |
| Paywall shows no plans | The current Offering has no packages, or the public SDK keys in Remote Config are wrong / unpublished. |
| Premium on device but server still caps AI | Webhook URL/secret wrong, so Firestore `premiumStatus` never updated; check `firebase functions:log`. |
| `app_user_id` mismatch | Don't call `Purchases.configure` with a custom appUserID — the app uses anonymous configure + `logIn(uid)` so the uid matches Firebase. |
| Only see a `test_` key | You're using the **Test Store** — fine for development (put it in the platform's Remote Config slot). For production add real App Store / Play Store apps to get `appl_`/`goog_` keys. See [Testing with the Test Store](#testing-with-the-test-store). |

---

## Related keys (other parts of setup)

- **AdMob:** `ads_enabled`, `admob_banner_id_{ios,android}`,
  `admob_interstitial_id_{ios,android}`, `interstitial_frequency` (Remote Config).
- **Free-tier ceilings:** `free_tier_wallets_max` (1), `free_tier_transactions_monthly`
  (100), `free_tier_ai_quota` (5) (Remote Config).
- **AI provider keys:** `OPENAI_API_KEY`, `GEMINI_API_KEY` (Firebase secrets);
  `ai_provider` (Remote Config: `"openai"` | `"gemini"`).

See the PRD §9 for the full Remote Config key reference.
