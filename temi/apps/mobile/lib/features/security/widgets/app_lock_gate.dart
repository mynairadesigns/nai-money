import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/security_providers.dart';
import '../presentation/lock_screen.dart';

/// Wraps the entire router output and intercepts app-lifecycle events to
/// enforce the auto-lock policy.
///
/// Place this around the root widget produced by GoRouter:
/// ```dart
/// MaterialApp.router(
///   routerConfig: router,
///   builder: (context, child) => AppLockGate(child: child ?? const SizedBox()),
/// );
/// ```
///
/// ## Lifecycle behaviour
/// - On `paused`/`inactive`: records [_backgroundedAt].
/// - On `resumed`: if lock is enabled and the elapsed duration meets the
///   auto-lock threshold, calls [AppLockNotifier.lock].
///   - autoLockMinutes == 0  → lock immediately (any pause triggers lock)
///   - autoLockMinutes > 0   → lock only if elapsed >= that many minutes
///   - autoLockMinutes == -1 → never auto-lock (manual lock only)
///
/// ## Rendering
/// - If [appLockProvider] is locked AND lock is currently enabled, renders
///   [LockScreen] instead of [child].
/// - Otherwise renders [child] as-is.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _backgroundedAt = DateTime.now();

      case AppLifecycleState.resumed:
        _onResumed();

      default:
        break;
    }
  }

  void _onResumed() {
    final settings = ref.read(securitySettingsProvider);
    if (!settings.lockEnabled) return;

    final backgrounded = _backgroundedAt;
    final autoLockMinutes = settings.autoLockMinutes;

    if (autoLockMinutes == -1) {
      // Never auto-lock.
      return;
    }

    if (autoLockMinutes == 0) {
      // Lock immediately on any resume.
      ref.read(appLockProvider.notifier).lock();
      return;
    }

    // Lock if elapsed time exceeds the threshold.
    if (backgrounded != null) {
      final elapsed = DateTime.now().difference(backgrounded);
      if (elapsed >= Duration(minutes: autoLockMinutes)) {
        ref.read(appLockProvider.notifier).lock();
      }
    }

    _backgroundedAt = null;
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockProvider);
    final settings = ref.watch(securitySettingsProvider);

    if (lockState.isLocked && settings.lockEnabled) {
      return const LockScreen();
    }
    return widget.child;
  }
}
