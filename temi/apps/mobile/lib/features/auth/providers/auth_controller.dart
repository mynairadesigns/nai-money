import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../domain/models/auth_failure.dart';

/// Drives the auth forms (sign-in, sign-up, forgot-password, social).
/// UI watches the [AsyncValue] state for loading + error display; on
/// success [authStateProvider] flips and the router redirect handles
/// the navigation transition.
///
/// Post-success contract: for any flow that creates a brand-new user
/// (sign-up, first-time Google, first-time Apple) we also write the
/// `users/{uid}` Firestore doc defensively — the `onUserCreate` Cloud
/// Function will also fire, but the client write avoids the race where
/// the app reads the doc before the trigger has written it.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authServiceProvider)
          .signInWithEmail(email: email, password: password);
    });
  }

  Future<void> signUpWithEmail({
    required String displayName,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final cred = await ref.read(authServiceProvider).signUpWithEmail(
            email: email,
            password: password,
            displayName: displayName,
          );
      await _seedIfNeeded(cred);
    });
  }

  Future<void> sendPasswordReset(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final cred = await ref.read(authServiceProvider).signInWithGoogle();
      await _seedIfNeeded(cred);
    });
  }

  Future<void> signInWithApple() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final cred = await ref.read(authServiceProvider).signInWithApple();
      await _seedIfNeeded(cred);
    });
  }

  Future<void> _seedIfNeeded(UserCredential cred) async {
    if (cred.additionalUserInfo?.isNewUser != true) return;
    final user = cred.user;
    if (user == null) return;
    try {
      await ref.read(firestoreServiceProvider).seedUserDocument(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName,
            photoUrl: user.photoURL,
          );
    } catch (_) {
      // Trigger is the safety net — never block the auth flow if the
      // defensive write fails (e.g. transient network blip).
    }
  }

  /// Pulls a friendly message from the latest error, if any. Surfaced
  /// in the UI via SnackBar/banner on top of [AsyncValue.error].
  String? errorMessage() {
    final err = state.error;
    if (err is AuthFailure) return err.message;
    if (err == null) return null;
    return 'Something went wrong.';
  }
}
