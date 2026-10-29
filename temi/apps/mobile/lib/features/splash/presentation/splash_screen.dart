import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/onboarding_state_provider.dart';
import '../../../core/providers/setup_state_provider.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';

/// PRD §6.1: app logo, ≥1s, then auto-route based on auth state.
///
/// Logic:
/// - signed-in → /home
/// - signed-out + onboarded → /auth/sign-in
/// - signed-out + new        → /onboarding
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _minDelayElapsed = false;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _minDelayElapsed = true);
      _maybeRoute();
    });
  }

  void _maybeRoute() {
    if (!mounted || !_minDelayElapsed) return;
    final auth = ref.read(authStateProvider);
    if (auth.isLoading) return; // wait for first emit
    final hasOnboarded = ref.read(hasSeenOnboardingProvider);

    if (auth.value != null) {
      // Setup status may still be resolving (first sign-in on this
      // device). Stay on the splash — routing to /home now would let the
      // redirect bounce the user into /setup before the real answer
      // lands. The listener below re-runs this once it resolves.
      final status = ref.read(setupStatusProvider);
      if (status == SetupStatus.unknown) return;
      context.go(status == SetupStatus.complete ? '/home' : '/setup');
    } else if (hasOnboarded) {
      context.go('/auth/sign-in');
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state and setup status arriving after the min
    // delay so the splash advances as soon as all conditions are met.
    ref.listen(authStateProvider, (_, _) => _maybeRoute());
    ref.listen(setupStatusProvider, (_, _) => _maybeRoute());

    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandLogo(size: 96),
            const SizedBox(height: AppSpacing.lg),
            Text('Temi Finance', style: theme.textTheme.headlineLarge),
          ],
        ),
      ),
    );
  }
}
