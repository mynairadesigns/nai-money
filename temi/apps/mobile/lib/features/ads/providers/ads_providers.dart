import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../billing/providers/premium_providers.dart';
import '../data/ads_service.dart';

/// Single gate: ads only render when the user is NOT premium AND the
/// buyer hasn't disabled ads globally via Remote Config (`ads_enabled`).
final adsEnabledProvider = Provider<bool>((ref) {
  final isPremium = ref.watch(isPremiumProvider);
  if (isPremium) return false;
  return ref.watch(adsServiceProvider).rcAdsEnabled;
});

/// Banner unit id, or null when ads are disabled / unit id is missing.
/// Widgets should treat null as "render nothing" — see [HomeBannerAd].
final bannerAdUnitIdProvider = Provider<String?>((ref) {
  if (!ref.watch(adsEnabledProvider)) return null;
  final id = ref.watch(adsServiceProvider).bannerAdUnitId();
  return id.isEmpty ? null : id;
});

/// Interstitial unit id, or null when ads are disabled / unit id missing.
final interstitialAdUnitIdProvider = Provider<String?>((ref) {
  if (!ref.watch(adsEnabledProvider)) return null;
  final id = ref.watch(adsServiceProvider).interstitialAdUnitId();
  return id.isEmpty ? null : id;
});

/// Monotonic counter that the transactions controller increments after a
/// successful tx add. The [InterstitialAdController] listens to this and
/// shows an ad every Nth increment (RC `interstitial_frequency`, default
/// 5 — PRD §6.14.1).
class TransactionAddCount extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
}

final transactionAddCountProvider =
    NotifierProvider<TransactionAddCount, int>(TransactionAddCount.new);
