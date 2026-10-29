import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../providers/ads_providers.dart';
import 'ads_service.dart';

/// Listens to [transactionAddCountProvider]. Every Nth increment
/// (RC `interstitial_frequency`, default 5 — PRD §6.14.1), pre-loads +
/// shows an interstitial. Skips when ads are disabled (premium or RC
/// off, see [adsEnabledProvider]).
///
/// Strategy:
///   - On non-Nth increments we kick off a background preload so the ad
///     is ready by the time the user hits the Nth add.
///   - On the Nth increment, if a preloaded ad is ready we show it
///     immediately; otherwise we preload (and miss this round — better
///     than blocking the UI on a network call).
class InterstitialAdController {
  InterstitialAdController(this._ref) {
    _ref.listen<int>(transactionAddCountProvider, (prev, next) {
      _onCount(next);
    });
  }

  final Ref _ref;
  InterstitialAd? _ready;
  bool _loading = false;

  void _onCount(int count) {
    final unitId = _ref.read(interstitialAdUnitIdProvider);
    if (unitId == null) return;
    final freq = _ref.read(adsServiceProvider).interstitialFrequency();
    if (count <= 0 || count % freq != 0) {
      _preload(unitId);
      return;
    }
    if (_ready != null) {
      _show();
    } else {
      _preload(unitId);
    }
  }

  void _preload(String unitId) {
    if (_loading || _ready != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ready = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) {
              a.dispose();
              _ready = null;
            },
            onAdFailedToShowFullScreenContent: (a, _) {
              a.dispose();
              _ready = null;
            },
          );
        },
        onAdFailedToLoad: (_) {
          _loading = false;
        },
      ),
    );
  }

  void _show() {
    _ready?.show();
    _ready = null;
  }
}

final interstitialControllerProvider = Provider<InterstitialAdController>(
  (ref) => InterstitialAdController(ref),
);
