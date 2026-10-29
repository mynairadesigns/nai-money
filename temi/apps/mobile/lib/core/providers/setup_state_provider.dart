import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'onboarding_state_provider.dart';

/// Pre-multi-account device-global key. Still read as an offline fallback
/// during the first resolve on an upgraded install, then cleared once
/// Firestore has given us a per-uid answer.
const _legacySetupKey = 'has_completed_setup';

/// Setup completion is a fact about a *user*, not a device — an install
/// can see several accounts. Keying by uid is what stops account A's
/// completed setup from short-circuiting account B's wizard.
String setupKeyFor(String uid) => 'has_completed_setup_$uid';

/// Tri-state, because "not known yet" and "known to be incomplete" must
/// route differently. Collapsing them into a bool is exactly what made
/// re-login flash (or get stuck in) the setup wizard: the router read a
/// synchronous `false` while the Firestore answer was still in flight.
enum SetupStatus {
  /// No answer for this uid yet — the router holds on the splash rather
  /// than guessing.
  unknown,

  /// This user still has to run the wizard.
  incomplete,

  /// This user has finished the wizard at least once.
  complete,
}

/// Whether the signed-in user has finished the post-signup setup wizard.
///
/// Resolution order, cheapest first:
/// 1. `has_completed_setup_<uid>` in SharedPreferences — set the moment
///    the wizard commits, and **never cleared on sign-out**, so a re-login
///    on the same device answers instantly with no network round-trip.
/// 2. `users/{uid}.setupCompletedAt` in Firestore — the canonical truth,
///    resolved by [SetupStateController.resolveFor] on sign-in (called
///    from `syncLifecycleProvider`) for uids this device hasn't seen.
final setupStatusProvider =
    NotifierProvider<SetupStateController, SetupStatus>(
  SetupStateController.new,
);

class SetupStateController extends Notifier<SetupStatus> {
  @override
  SetupStatus build() {
    // Rebuilds on every auth change, so switching accounts re-reads the
    // new uid's flag instead of inheriting the previous user's state.
    final uid = ref.watch(authStateProvider).value?.uid;
    if (uid == null) return SetupStatus.unknown;
    final prefs = ref.watch(sharedPreferencesProvider);
    return (prefs.getBool(setupKeyFor(uid)) ?? false)
        ? SetupStatus.complete
        : SetupStatus.unknown;
  }

  /// Settles [SetupStatus.unknown] for [uid] using the remote truth.
  ///
  /// [remoteLookup] returns whether `users/{uid}.setupCompletedAt` is set,
  /// or throws when it can't be reached. Injected rather than read off a
  /// provider so this stays testable without Firebase.
  Future<void> resolveFor(
    String uid,
    Future<bool> Function() remoteLookup,
  ) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(setupKeyFor(uid)) ?? false) {
      state = SetupStatus.complete;
      return;
    }
    try {
      final completed = await remoteLookup();
      if (completed) {
        await markCompleted(uid);
      } else {
        state = SetupStatus.incomplete;
      }
      // Firestore answered, so the device-global legacy flag has served
      // its purpose and must not leak into the next account.
      await prefs.remove(_legacySetupKey);
    } catch (_) {
      // Offline / permission error. Fall back to the legacy device flag
      // so an upgraded install doesn't re-run the wizard, otherwise send
      // the user through setup — the only safe default for an account
      // this device knows nothing about.
      final legacy = prefs.getBool(_legacySetupKey) ?? false;
      if (legacy) {
        await markCompleted(uid);
      } else {
        state = SetupStatus.incomplete;
      }
    }
  }

  /// Records that [uid] (defaulting to the signed-in user) finished setup.
  Future<void> markCompleted([String? uid]) async {
    final id = uid ?? ref.read(authServiceProvider).currentUser?.uid;
    if (id == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(setupKeyFor(id), true);
    state = SetupStatus.complete;
  }

  /// Resolves the state for a brand-new account without a round-trip — a
  /// just-created uid has definitionally not run the wizard. Skips the
  /// splash hold that a fresh sign-up would otherwise sit through while
  /// [resolveFor] queried a `users/{uid}` doc the trigger may not have
  /// written yet.
  void markIncomplete() => state = SetupStatus.incomplete;
}
