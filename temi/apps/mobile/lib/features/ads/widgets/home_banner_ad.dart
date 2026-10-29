import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../providers/ads_providers.dart';

/// Bottom-of-Home banner ad. Renders nothing when:
///   - the user is premium, or
///   - the buyer has disabled `ads_enabled` in Remote Config, or
///   - the banner ad unit id is missing / fails to load.
///
/// Lifecycle: loads once on `initState`, tears down on `dispose`. We
/// also `watch` the gate provider in `build` so the widget reactively
/// hides if the user upgrades to premium mid-session.
class HomeBannerAd extends ConsumerStatefulWidget {
  const HomeBannerAd({super.key});

  @override
  ConsumerState<HomeBannerAd> createState() => _HomeBannerAdState();
}

class _HomeBannerAdState extends ConsumerState<HomeBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  void _maybeLoad() {
    final id = ref.read(bannerAdUnitIdProvider);
    if (id == null) return;
    _ad = BannerAd(
      adUnitId: id,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the gate so we tear down when the user upgrades.
    final id = ref.watch(bannerAdUnitIdProvider);
    if (id == null || !_loaded || _ad == null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: SizedBox(
        width: _ad!.size.width.toDouble(),
        height: _ad!.size.height.toDouble(),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
