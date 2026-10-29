import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Thin wrapper over the AdMob SDK + Remote Config gates.
///
/// Reads the buyer-facing ad unit IDs + frequency knobs from Remote
/// Config (PRD §9):
///   - `ads_enabled`               — global kill switch
///   - `admob_banner_id_android`   — banner unit id, Android
///   - `admob_banner_id_ios`       — banner unit id, iOS
///   - `admob_interstitial_id_android`
///   - `admob_interstitial_id_ios`
///   - `interstitial_frequency`    — every Nth tx add (default 5)
///
/// SDK init is idempotent: callers may invoke [initialize] more than
/// once cheaply (e.g. main.dart fire-and-forget + first banner load).
class AdsService {
  AdsService(this._rc);
  final FirebaseRemoteConfig _rc;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return; // AdMob is mobile-only.
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  /// Always false on web — AdMob has no web SDK. This is the single gate
  /// every ad widget/controller reads (via `adsEnabledProvider`).
  bool get rcAdsEnabled => !kIsWeb && _rc.getBool('ads_enabled');

  String bannerAdUnitId() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _rc.getString('admob_banner_id_ios');
    if (defaultTargetPlatform == TargetPlatform.android) return _rc.getString('admob_banner_id_android');
    return '';
  }

  String interstitialAdUnitId() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _rc.getString('admob_interstitial_id_ios');
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _rc.getString('admob_interstitial_id_android');
    }
    return '';
  }

  int interstitialFrequency() {
    final n = _rc.getInt('interstitial_frequency');
    return n > 0 ? n : 5;
  }
}

final adsServiceProvider = Provider<AdsService>(
  (ref) => AdsService(FirebaseRemoteConfig.instance),
);
