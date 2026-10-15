import 'package:firebase_auth/firebase_auth.dart';

/// Typed auth failures used across the app. Never expose raw
/// [FirebaseAuthException] codes to the UI — funnel through this.
sealed class AuthFailure implements Exception {
  const AuthFailure();

  String get message;

  factory AuthFailure.fromFirebase(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return const InvalidCredentialsFailure();
      case 'email-already-in-use':
        return const EmailInUseFailure();
      case 'weak-password':
        return const WeakPasswordFailure();
      case 'invalid-email':
        return const InvalidEmailFailure();
      case 'user-disabled':
        return const UserDisabledFailure();
      case 'network-request-failed':
        return const NetworkFailure();
      default:
        return UnknownAuthFailure(e.message ?? e.code);
    }
  }
}

class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure();
  @override
  String get message => 'Invalid email or password.';
}

class EmailInUseFailure extends AuthFailure {
  const EmailInUseFailure();
  @override
  String get message => 'An account already exists for this email.';
}

class WeakPasswordFailure extends AuthFailure {
  const WeakPasswordFailure();
  @override
  String get message => 'Password is too weak. Use at least 6 characters.';
}

class InvalidEmailFailure extends AuthFailure {
  const InvalidEmailFailure();
  @override
  String get message => 'That email address looks invalid.';
}

class UserDisabledFailure extends AuthFailure {
  const UserDisabledFailure();
  @override
  String get message => 'This account has been disabled.';
}

class NetworkFailure extends AuthFailure {
  const NetworkFailure();
  @override
  String get message => 'Network error. Check your connection and try again.';
}

class CancelledFailure extends AuthFailure {
  const CancelledFailure();
  @override
  String get message => 'Sign-in cancelled.';
}

class UnknownAuthFailure extends AuthFailure {
  const UnknownAuthFailure(this._detail);
  final String _detail;
  @override
  String get message => 'Something went wrong. ($_detail)';
}
