import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/remote_config_init.dart';
import 'core/providers/onboarding_state_provider.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/sync/sync_lifecycle_provider.dart';
import 'features/ads/data/interstitial_controller.dart';
import 'features/billing/providers/paystack_providers.dart';
import 'features/notifications/data/notification_coordinator.dart';
import 'features/security/widgets/app_lock_gate.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Remote Config defaults + fetch — MUST run before sign-in so the
  // RevenueCat keys, free-tier ceilings, and AdMob ids are live. Best-effort
  // (falls back to in-app defaults offline); awaited so values are ready
  // before the auth-driven billing init in syncLifecycleProvider.
  await initRemoteConfig();
  // AdMob init runs in parallel with the rest of startup; fire-and-forget.
  // The SDK is idempotent so subsequent init calls (e.g. when AdsService
  // is asked to lazy-init) are no-ops.
  if (!kIsWeb) unawaited(MobileAds.instance.initialize());
  final prefs = await SharedPreferences.getInstance();
  // Web: returning from Paystack checkout — Paystack appends
  // `?trxref=…&reference=…` to our callback URL. Stash the reference so
  // [PaystackReturnHandler] can verify it once auth has restored.
  if (kIsWeb) {
    final reference = Uri.base.queryParameters['reference'];
    if (reference != null && reference.isNotEmpty) {
      await prefs.setString(kPaystackPendingRefKey, reference);
    }
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MoneymindApp(),
    ),
  );
}

final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MoneymindApp extends ConsumerWidget {
  const MoneymindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Side-effect provider — keeps the auth-state listener alive for the
    // session, which in turn drives the Drift → Firestore write-through
    // sync engine and the post-sign-in setupCompletedAt rehydration.
    ref.watch(syncLifecycleProvider);
    // Eager-instantiate the interstitial controller so it starts
    // listening to `transactionAddCountProvider` from app start.
    ref.watch(interstitialControllerProvider);
    // Eager-instantiate the notification coordinator so it initializes the
    // local-notification plugin and starts scheduling alerts from app start.
    ref.watch(notificationCoordinatorProvider);
    // Web: verify a Paystack checkout the user just returned from.
    if (kIsWeb) {
      ref.listen(paystackReturnHandlerProvider, (_, status) {
        final msg = switch (status) {
          PaystackReturnStatus.success => 'Payment received — welcome to Premium!',
          PaystackReturnStatus.pending =>
            "Payment not completed. If you were charged, Premium will activate shortly.",
          PaystackReturnStatus.failed =>
            "Couldn't confirm your payment yet — we'll check again next time you open the app.",
          _ => null,
        };
        if (msg != null) {
          _scaffoldMessengerKey.currentState
              ?.showSnackBar(SnackBar(content: Text(msg)));
        }
      });
    }

    return MaterialApp.router(
      title: 'Homa Finance',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
      // App-lock overlay (P7 security): gates the entire navigator behind the
      // PIN/biometric lock screen when enabled. Sits above all routes.
      builder: (context, child) => _WebWidthLimit(
        child: AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Web / desktop: the app's screens are designed for phone-to-tablet
/// widths, so on very wide browser windows we centre them in a column of at
/// most [_maxWidth] instead of stretching forms and lists edge to edge.
/// MediaQuery is narrowed to match, so screens that read
/// `MediaQuery.sizeOf(context)` lay out for the visible width.
class _WebWidthLimit extends StatelessWidget {
  const _WebWidthLimit({required this.child});
  final Widget child;

  static const _maxWidth = 1100.0;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    final mq = MediaQuery.of(context);
    if (mq.size.width <= _maxWidth) return child;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Center(
        child: SizedBox(
          width: _maxWidth,
          child: MediaQuery(
            data: mq.copyWith(size: Size(_maxWidth, mq.size.height)),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}
