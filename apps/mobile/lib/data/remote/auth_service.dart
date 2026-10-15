import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../domain/models/auth_failure.dart';

/// Thin wrapper over [FirebaseAuth] + Google + Apple sign-in.
/// All public methods throw [AuthFailure] (never raw FirebaseAuthException).
class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _google = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (displayName.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(displayName.trim());
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Don't leak whether the account exists — Firebase quietly no-ops
      // for unknown emails, but invalid-format etc. still throws.
      if (e.code == 'invalid-email') {
        throw const InvalidEmailFailure();
      }
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    // Web: google_sign_in v7 has no `authenticate()` on web (it only renders
    // Google's own button). Firebase Auth's popup flow is the simplest
    // equivalent and needs no extra client-id wiring — just make sure your
    // web domain is listed under Firebase Auth → Settings → Authorized domains.
    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        return await _auth.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request' ||
            e.code == 'user-cancelled') {
          throw const CancelledFailure();
        }
        throw AuthFailure.fromFirebase(e);
      }
    }
    try {
      await _google.initialize();
      final account = await _google.authenticate();
      final auth = account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const CancelledFailure();
      }
      throw UnknownAuthFailure(e.description ?? e.code.name);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<UserCredential> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final cred = await _auth.signInWithCredential(oauthCredential);
      // Apple only returns the full name on first sign-in. Persist it
      // to the Firebase user profile so subsequent sessions still have it.
      final fullName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].whereType<String>().where((p) => p.isNotEmpty).join(' ');
      if (fullName.isNotEmpty && cred.user?.displayName == null) {
        await cred.user?.updateDisplayName(fullName);
      }
      return cred;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const CancelledFailure();
      }
      throw UnknownAuthFailure(e.message);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      await _google.signOut().catchError((_) {});
    }
    await _auth.signOut();
  }
}
