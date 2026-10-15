import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:homa_finance/core/providers/auth_provider.dart';
import 'package:homa_finance/core/providers/onboarding_state_provider.dart';
import 'package:homa_finance/core/providers/setup_state_provider.dart';

import '../helpers/test_harness.dart';

/// Setup completion gates the `/setup` redirect. The bug this covers:
/// the flag used to be a device-global bool cleared on sign-out, so every
/// re-login re-ran the onboarding wizard while the Firestore answer was
/// still in flight — and stayed stuck there whenever the device was
/// offline.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<({ProviderContainer container, SharedPreferences prefs})> build({
    String uid = 'u1',
    Map<String, Object> seed = const {},
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authServiceProvider.overrideWithValue(FakeAuthService(uid: uid)),
      ],
    );
    addTearDown(container.dispose);
    // `build()` keys off authStateProvider. Hold a live subscription and
    // poll for the first emission — a `.future` read on a StreamProvider
    // leaves a pending completer that errors at dispose (CLAUDE.md §6).
    final sub = container.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    for (var i = 0; i < 100; i++) {
      if (container.read(authStateProvider).hasValue) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return (container: container, prefs: prefs);
  }

  test('a uid this device has never seen starts unknown, not incomplete',
      () async {
    final h = await build();
    // Routing on "incomplete" here is what flashed the wizard.
    expect(h.container.read(setupStatusProvider), SetupStatus.unknown);
  });

  test('a locally-flagged uid resolves complete without touching the network',
      () async {
    final h = await build(seed: {setupKeyFor('u1'): true});

    expect(h.container.read(setupStatusProvider), SetupStatus.complete);

    var remoteCalls = 0;
    await h.container.read(setupStatusProvider.notifier).resolveFor(
      'u1',
      () async {
        remoteCalls++;
        return false;
      },
    );

    expect(remoteCalls, 0, reason: 'local flag must short-circuit');
    expect(h.container.read(setupStatusProvider), SetupStatus.complete);
  });

  test('the flag is per-uid, so another account is not treated as complete',
      () async {
    final h = await build(uid: 'u2', seed: {setupKeyFor('u1'): true});

    expect(h.container.read(setupStatusProvider), SetupStatus.unknown);
  });

  test('remote setupCompletedAt resolves complete and is cached locally',
      () async {
    final h = await build();

    await h.container
        .read(setupStatusProvider.notifier)
        .resolveFor('u1', () async => true);

    expect(h.container.read(setupStatusProvider), SetupStatus.complete);
    // Cached, so the next re-login answers instantly.
    expect(h.prefs.getBool(setupKeyFor('u1')), isTrue);
  });

  test('remote says not-completed → incomplete (fresh sign-up runs setup)',
      () async {
    final h = await build();

    await h.container
        .read(setupStatusProvider.notifier)
        .resolveFor('u1', () async => false);

    expect(h.container.read(setupStatusProvider), SetupStatus.incomplete);
    expect(h.prefs.getBool(setupKeyFor('u1')), isNull);
  });

  test('offline with the legacy device flag falls back to complete', () async {
    // Upgrade path: pre-per-uid installs only have the global key.
    final h = await build(seed: {'has_completed_setup': true});

    await h.container.read(setupStatusProvider.notifier).resolveFor(
          'u1',
          () async => throw Exception('offline'),
        );

    expect(h.container.read(setupStatusProvider), SetupStatus.complete);
    expect(h.prefs.getBool(setupKeyFor('u1')), isTrue);
  });

  test('offline with nothing known falls back to incomplete', () async {
    final h = await build();

    await h.container.read(setupStatusProvider.notifier).resolveFor(
          'u1',
          () async => throw Exception('offline'),
        );

    expect(h.container.read(setupStatusProvider), SetupStatus.incomplete);
  });

  test('a successful remote answer clears the legacy device-global flag',
      () async {
    final h = await build(seed: {'has_completed_setup': true});

    await h.container
        .read(setupStatusProvider.notifier)
        .resolveFor('u1', () async => false);

    expect(h.container.read(setupStatusProvider), SetupStatus.incomplete);
    // Otherwise it would leak into the next account signing in here.
    expect(h.prefs.getBool('has_completed_setup'), isNull);
  });

  test('markCompleted writes the per-uid key', () async {
    final h = await build();

    await h.container.read(setupStatusProvider.notifier).markCompleted('u1');

    expect(h.container.read(setupStatusProvider), SetupStatus.complete);
    expect(h.prefs.getBool(setupKeyFor('u1')), isTrue);
  });
}
