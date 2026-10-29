import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/providers/onboarding_state_provider.dart';
import '../data/security_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

/// Provides the [FlutterSecureStorage] singleton used for PIN hash storage.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// Provides the [SecurityService] wired with secure storage + shared prefs.
final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService(
    secureStorage: ref.watch(secureStorageProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
});

// ---------------------------------------------------------------------------
// SecuritySettings
// ---------------------------------------------------------------------------

/// Immutable snapshot of the user's security preferences.
class SecuritySettings {
  const SecuritySettings({
    required this.lockEnabled,
    required this.biometricEnabled,
    required this.autoLockMinutes,
    required this.hasPin,
  });

  final bool lockEnabled;
  final bool biometricEnabled;

  /// Sentinel values: 0 = immediately, 1/5/15 = minutes, -1 = never.
  final int autoLockMinutes;
  final bool hasPin;

  SecuritySettings copyWith({
    bool? lockEnabled,
    bool? biometricEnabled,
    int? autoLockMinutes,
    bool? hasPin,
  }) {
    return SecuritySettings(
      lockEnabled: lockEnabled ?? this.lockEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      hasPin: hasPin ?? this.hasPin,
    );
  }
}

class SecuritySettingsNotifier extends Notifier<SecuritySettings> {
  @override
  SecuritySettings build() {
    final service = ref.watch(securityServiceProvider);
    // Synchronous reads from SharedPreferences (loaded before runApp).
    // hasPin is async — we optimistically read false and refresh() fills it.
    return SecuritySettings(
      lockEnabled: service.lockEnabled,
      biometricEnabled: service.biometricEnabled,
      autoLockMinutes: service.autoLockMinutes,
      hasPin: false,
    );
  }

  /// Call once after build to populate the async [hasPin] flag.
  Future<void> refresh() async {
    final service = ref.read(securityServiceProvider);
    final pinSet = await service.hasPin();
    state = state.copyWith(hasPin: pinSet);
  }

  Future<void> setLockEnabled(bool value) async {
    await ref.read(securityServiceProvider).setLockEnabled(value);
    state = state.copyWith(lockEnabled: value);
  }

  Future<void> setBiometricEnabled(bool value) async {
    await ref.read(securityServiceProvider).setBiometricEnabled(value);
    state = state.copyWith(biometricEnabled: value);
  }

  Future<void> setAutoLockMinutes(int value) async {
    await ref.read(securityServiceProvider).setAutoLockMinutes(value);
    state = state.copyWith(autoLockMinutes: value);
  }

  /// Re-reads hasPin from secure storage (e.g., after PIN setup completes).
  Future<void> refreshHasPin() async {
    final pinSet = await ref.read(securityServiceProvider).hasPin();
    state = state.copyWith(hasPin: pinSet);
  }
}

/// The security settings provider — use for settings UI and the lock gate.
final securitySettingsProvider =
    NotifierProvider<SecuritySettingsNotifier, SecuritySettings>(
  SecuritySettingsNotifier.new,
);

// ---------------------------------------------------------------------------
// AppLockState
// ---------------------------------------------------------------------------

class AppLockState {
  const AppLockState({required this.isLocked});
  final bool isLocked;
}

class AppLockNotifier extends Notifier<AppLockState> {
  @override
  AppLockState build() {
    final service = ref.watch(securityServiceProvider);
    // If lock is enabled, the app starts locked.
    return AppLockState(isLocked: service.lockEnabled);
  }

  void lock() => state = const AppLockState(isLocked: true);

  void unlock() => state = const AppLockState(isLocked: false);
}

/// The app lock gate state. Read by [AppLockGate] to decide whether to render
/// the child or the [LockScreen] on top.
final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(
  AppLockNotifier.new,
);
