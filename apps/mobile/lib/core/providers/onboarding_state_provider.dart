import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hasSeenOnboardingKey = 'has_seen_onboarding';

/// Overridden in [main] with the actually-loaded [SharedPreferences]
/// instance — the async initialization happens before `runApp` so the
/// rest of the app can read it synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  ),
);

/// Whether the user has finished the onboarding carousel at least once.
final hasSeenOnboardingProvider = NotifierProvider<OnboardingController, bool>(
  OnboardingController.new,
);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_hasSeenOnboardingKey) ?? false;
  }

  Future<void> markSeen() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_hasSeenOnboardingKey, true);
    state = true;
  }
}
