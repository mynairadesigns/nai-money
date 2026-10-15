import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/firestore_provider.dart';
import '../../core/providers/setup_state_provider.dart';
import '../remote/billing_service.dart';
import 'firestore_hydrator.dart';
import 'firestore_sync_service.dart';

/// Ceiling on the `users/{uid}` setup-status read. The router holds the
/// user on the splash while it's in flight, so this can't be unbounded.
const _setupLookupTimeout = Duration(seconds: 8);

/// Long-lived [FirestoreSyncService] owned by the app. Lazy — the
/// Firestore instance isn't touched until something actually reads this.
final firestoreSyncServiceProvider = Provider<FirestoreSyncService>((ref) {
  final svc = FirestoreSyncService(
    ref.watch(firestoreProvider),
    ref.watch(appDatabaseProvider),
  );
  ref.onDispose(svc.stop);
  return svc;
});

/// Top-level side-effect provider that ties the sync engine to the auth
/// lifecycle. `ref.watch` this once at the app root (MoneymindApp.build)
/// so it stays alive for the session.
///
/// On every auth-state change:
/// - sign-in: resolve this uid's setup status (local per-uid flag first,
///   Firestore `users/{uid}.setupCompletedAt` as the fallback), then start
///   write-through sync.
/// - sign-out (after having been signed in): stop sync. We deliberately do
///   NOT clear the per-uid setup flag — it's keyed by uid, so the next
///   account gets its own state anyway, and keeping it means a re-login
///   resolves instantly instead of racing a network read (which is what
///   used to bounce returning users back into the onboarding wizard).
final syncLifecycleProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) async {
    final user = next.value;
    final setupCtrl = ref.read(setupStatusProvider.notifier);

    if (user != null) {
      // Settle setup status before anything else — the router parks the
      // user on the splash until this resolves. Bounded by a timeout so a
      // hung read can't strand them there; the doc may also not exist yet
      // (race with the post-signup seed), which reads as "incomplete" and
      // sends a fresh sign-up through /setup.
      await setupCtrl.resolveFor(user.uid, () async {
        final doc = await ref
            .read(firestoreProvider)
            .doc('users/${user.uid}')
            .get()
            .timeout(_setupLookupTimeout);
        return doc.exists && doc.data()?['setupCompletedAt'] != null;
      });
      // Pull-direction hydrate (P2.7): fetch every synced subcollection
      // and upsert into Drift. Runs BEFORE the write-through engine so
      // we never overwrite a row that's about to be pushed (the hydrator
      // skips rows with local syncStatus='pending'). Best-effort —
      // failures leave Drift untouched.
      final hydrator = FirestoreHydrator(
        ref.read(firestoreProvider),
        ref.read(appDatabaseProvider),
      );
      await hydrator.hydrate(user.uid);
      ref.read(firestoreSyncServiceProvider).startForUser(user.uid);

      // RevenueCat (P6): lazy-init after sign-in. RC needs the user's
      // uid + the Remote-Config-driven API key, neither of which exists
      // at cold start. Buyers configure the keys in their Firebase
      // Remote Config console (`revenuecat_api_key_ios` / `_android`);
      // if they're not set yet, we skip init quietly and the paywall
      // will render its "not configured" empty state.
      try {
        final remoteConfig = FirebaseRemoteConfig.instance;
        final apiKey = Platform.isIOS
            ? remoteConfig.getString('revenuecat_api_key_ios')
            : remoteConfig.getString('revenuecat_api_key_android');
        if (apiKey.isNotEmpty) {
          final billing = ref.read(billingServiceProvider);
          await billing.configure(apiKey);
          await billing.identify(user.uid);
        }
      } catch (e) {
        debugPrint('syncLifecycle: billing init skipped: $e');
      }
    } else if (prev?.value != null) {
      // Sign-out: stop the sync engine. The per-uid setup flag stays put
      // on purpose (see the doc comment above).
      ref.read(firestoreSyncServiceProvider).stop();
      try {
        await ref.read(billingServiceProvider).logOut();
      } catch (e) {
        debugPrint('syncLifecycle: billing logOut skipped: $e');
      }
    }
  }, fireImmediately: true);
});
