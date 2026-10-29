import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Initializes Firebase Remote Config once at startup:
///   1. registers in-app defaults so the app behaves sanely before/without a
///      network fetch (offline, first launch),
///   2. sets a dev-friendly minimum fetch interval so console changes show up
///      immediately in debug (throttled in release),
///   3. does a best-effort `fetchAndActivate`.
///
/// MUST run before the app reads any RC value — without it,
/// `FirebaseRemoteConfig.instance.getString(...)` returns empty and the
/// RevenueCat keys, free-tier ceilings, and AdMob ids all read as unset
/// (symptom: the paywall shows "Subscriptions aren't configured yet").
///
/// Keys mirror PRD §9. RevenueCat + AdMob ids default to empty on purpose:
/// an empty key means "not configured", which the paywall / ad gates handle
/// gracefully. The numeric ceilings carry their PRD defaults so free-tier
/// enforcement works even offline.
Future<void> initRemoteConfig() async {
  final rc = FirebaseRemoteConfig.instance;
  try {
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Debug: always re-fetch so console edits propagate instantly.
        // Release: throttle to 1h (Remote Config best practice).
        minimumFetchInterval:
            kReleaseMode ? const Duration(hours: 1) : Duration.zero,
      ),
    );
    await rc.setDefaults(const {
      // Monetization — RevenueCat (empty = not configured → paywall guides setup).
      'revenuecat_api_key_ios': '',
      'revenuecat_api_key_android': '',
      // Free-tier ceilings (PRD §6.14.1).
      'free_tier_wallets_max': 1,
      'free_tier_transactions_monthly': 100,
      'free_tier_ai_quota': 10,
      // Ads (empty ids + disabled by default; buyer opts in via console).
      'ads_enabled': false,
      'admob_banner_id_ios': '',
      'admob_banner_id_android': '',
      'admob_interstitial_id_ios': '',
      'admob_interstitial_id_android': '',
      'interstitial_frequency': 5,
      // AI provider override (server also reads this; client default is informational).
      'ai_provider': 'gemini',
    });
    await rc.fetchAndActivate();
  } catch (e) {
    // Offline / throttled / misconfigured — fall back to the in-app defaults
    // above. Never block or crash startup on Remote Config.
    debugPrint('initRemoteConfig: using defaults ($e)');
  }
}
