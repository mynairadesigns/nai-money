import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pinHashKey = 'mm_pin_hash';
const _pinSaltKey = 'mm_pin_salt';
const _lockEnabledKey = 'mm_lock_enabled';
const _biometricEnabledKey = 'mm_biometric_enabled';
const _autoLockMinutesKey = 'mm_auto_lock_minutes';

/// Handles all security concerns: PIN storage (salted SHA-256 in secure
/// storage), biometric authentication (via local_auth), and non-secret
/// lock preference flags (via SharedPreferences).
///
/// Autolock sentinel values:
///   0  = lock immediately on background
///   1  = lock after 1 minute
///   5  = lock after 5 minutes
///   15 = lock after 15 minutes
///  -1  = never auto-lock (only manual lock)
class SecurityService {
  SecurityService({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secure = secureStorage,
        _prefs = prefs;

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;
  final LocalAuthentication _localAuth = LocalAuthentication();

  // ---------------------------------------------------------------------------
  // PIN management
  // ---------------------------------------------------------------------------

  /// Stores a salted SHA-256 hash of [pin] in secure storage.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _secure.write(key: _pinSaltKey, value: salt);
    await _secure.write(key: _pinHashKey, value: hash);
  }

  /// Returns true if [pin] matches the stored hash.
  Future<bool> verifyPin(String pin) async {
    final salt = await _secure.read(key: _pinSaltKey);
    final storedHash = await _secure.read(key: _pinHashKey);
    if (salt == null || storedHash == null) return false;
    final candidate = _hashPin(pin, salt);
    return candidate == storedHash;
  }

  /// Returns true if a PIN has been set.
  Future<bool> hasPin() async {
    final hash = await _secure.read(key: _pinHashKey);
    return hash != null;
  }

  /// Removes the stored PIN hash and salt.
  Future<void> clearPin() async {
    await _secure.delete(key: _pinHashKey);
    await _secure.delete(key: _pinSaltKey);
  }

  // ---------------------------------------------------------------------------
  // Biometric
  // ---------------------------------------------------------------------------

  /// Returns true if the device supports biometric authentication and has
  /// enrolled biometrics.
  Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false; // local_auth has no web implementation.
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user with a biometric authentication dialog showing [reason].
  /// Returns false on any error or cancellation.
  Future<bool> authenticateBiometric(String reason) async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Non-secret flags (SharedPreferences)
  // ---------------------------------------------------------------------------

  bool get lockEnabled => _prefs.getBool(_lockEnabledKey) ?? false;

  Future<void> setLockEnabled(bool value) =>
      _prefs.setBool(_lockEnabledKey, value);

  bool get biometricEnabled => _prefs.getBool(_biometricEnabledKey) ?? false;

  Future<void> setBiometricEnabled(bool value) =>
      _prefs.setBool(_biometricEnabledKey, value);

  /// Sentinel: 0 = immediately, 1 = 1 min, 5 = 5 min, 15 = 15 min, -1 = never.
  int get autoLockMinutes => _prefs.getInt(_autoLockMinutesKey) ?? 0;

  Future<void> setAutoLockMinutes(int value) =>
      _prefs.setInt(_autoLockMinutesKey, value);

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final input = utf8.encode('$salt:$pin');
    return sha256.convert(input).toString();
  }
}
