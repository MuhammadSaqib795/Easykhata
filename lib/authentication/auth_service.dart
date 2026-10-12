import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:googleapis/drive/v3.dart' as drive;

/// Thrown by [AuthService] with a message that is safe to show to users.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.field});

  final String message;

  /// 'email' or 'password' when the problem belongs to one form field.
  final String? field;

  @override
  String toString() => message;
}

/// The app's only authentication entry point (Firebase Authentication).
///
/// The signed-in Firebase user is the single source of truth: their UID owns
/// the local data and the cloud backup. Nothing else ever picks an account.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleInit;

  /// OAuth "Web client" (client_type 3) from google-services.json. Needed so
  /// Google returns an ID token for Firebase.
  static const String _serverClientId =
      '36925261827-ilde73okhhgkdmj6spm1j6tqkundcelm.apps.googleusercontent.com';

  static const _timeout = Duration(seconds: 30);

  User? get currentUser => _auth.currentUser;

  // ==========================================================
  // EMAIL / PASSWORD
  // ==========================================================

  Future<User> register({
    required String fullName,
    required String email,
    required String password,
  }) => _guard(() async {
    final cred = await _auth
        .createUserWithEmailAndPassword(email: email.trim(), password: password)
        .timeout(_timeout);
    final user = cred.user!;
    try {
      await user.updateDisplayName(fullName.trim());
      await user.sendEmailVerification();
      await user.reload();
    } catch (e) {
      debugPrint('Post-registration step skipped: $e');
    }
    return _auth.currentUser ?? user;
  });

  Future<User> signIn({required String email, required String password}) =>
      _guard(() async {
        final cred = await _auth
            .signInWithEmailAndPassword(email: email.trim(), password: password)
            .timeout(_timeout);
        return cred.user!;
      });

  /// Firebase's free password-reset e-mail.
  Future<void> sendPasswordReset(String email) => _guard(
    () => _auth.sendPasswordResetEmail(email: email.trim()).timeout(_timeout),
  );

  Future<void> resendVerificationEmail() => _guard(() async {
    await _auth.currentUser?.sendEmailVerification().timeout(_timeout);
  });

  // ==========================================================
  // GOOGLE (login, and the Google Drive used for backup)
  // ==========================================================

  /// Drive permission for the backup (app-private folder only).
  static const List<String> driveScopes = [drive.DriveApi.driveAppdataScope];

  GoogleSignInAccount? _driveAccount;

  Future<void> _ensureGoogle() => _googleInit ??= _googleSignIn
      .initialize(serverClientId: _serverClientId)
      .catchError((Object e) {
        _googleInit = null;
        throw e;
      });

  /// Google account id linked to [user] (Google login, or Google Drive
  /// linked once to an e-mail account). Null when none is linked.
  static String? googleIdOf(User user) {
    for (final p in user.providerData) {
      if (p.providerId == GoogleAuthProvider.PROVIDER_ID) return p.uid;
    }
    return null;
  }

  /// E-mail of the Google account whose Drive holds [user]'s backup.
  static String? driveEmailOf(User user) {
    for (final p in user.providerData) {
      if (p.providerId == GoogleAuthProvider.PROVIDER_ID) return p.email;
    }
    return null;
  }

  static bool isGoogleUser(User user) => googleIdOf(user) != null;

  /// Returns null when the user closed Google's dialog.
  Future<User?> signInWithGoogle() => _guard(() async {
    final account = await _pickGoogleAccount();
    if (account == null) return null;
    final User user;
    try {
      final cred = await _auth
          .signInWithCredential(_credentialFor(account))
          .timeout(_timeout);
      user = cred.user!;
    } catch (_) {
      await _safeGoogleSignOut();
      rethrow;
    }
    _driveAccount = account;
    await _requestDrivePermission(account);
    return user;
  });

  /// One-time step for e-mail/password accounts: links a Google account to
  /// the signed-in Easy Khata account. That Google account's Drive then
  /// always holds this user's backup. Returns false if the user cancelled.
  Future<bool> linkGoogleDrive() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Please sign in again.');
    if (isGoogleUser(user)) return reconnectGoogleDrive();

    final account = await _pickGoogleAccount();
    if (account == null) return false;
    try {
      await user.linkWithCredential(_credentialFor(account)).timeout(_timeout);
      await user.reload();
    } on FirebaseAuthException catch (e) {
      await _safeGoogleSignOut();
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        throw const AuthFailure(
          'This Google account is already used by another Easy Khata '
          'account. Please choose a different Google account.',
        );
      }
      rethrow;
    }
    _driveAccount = account;
    await _requestDrivePermission(account);
    return true;
  });

  /// Restores Drive access for the Google account ALREADY linked to the
  /// signed-in user (e.g. after its session expired). Any other Google
  /// account is rejected. Returns false if the user cancelled.
  Future<bool> reconnectGoogleDrive() => _guard(() async {
    final user = _auth.currentUser;
    final linkedId = user == null ? null : googleIdOf(user);
    if (linkedId == null) throw const AuthFailure('Please sign in again.');

    final account = await _pickGoogleAccount();
    if (account == null) return false;
    if (account.id != linkedId) {
      await _safeGoogleSignOut();
      throw AuthFailure(
        'Please choose ${driveEmailOf(user!) ?? 'the Google account linked to Easy Khata'}. '
        'Your backup belongs to that account.',
      );
    }
    _driveAccount = account;
    await _requestDrivePermission(account);
    return true;
  });

  /// The linked Google account of the signed-in user, restored silently.
  /// Never returns a Google account that is not linked to this user.
  Future<GoogleSignInAccount?> driveAccountForCurrentUser() async {
    final user = _auth.currentUser;
    final linkedId = user == null ? null : googleIdOf(user);
    if (linkedId == null) {
      _driveAccount = null;
      return null;
    }
    if (_driveAccount?.id == linkedId) return _driveAccount;
    _driveAccount = null;
    try {
      await _ensureGoogle();
      final restored = await _googleSignIn.attemptLightweightAuthentication();
      if (restored == null || restored.id != linkedId) return null;
      if (_auth.currentUser?.uid != user!.uid) return null;
      _driveAccount = restored;
      return restored;
    } catch (e) {
      debugPrint('Silent Google restore failed: $e');
      return null;
    }
  }

  /// Drop the cached Drive session (e.g. after a 401) so a fresh token is
  /// requested next time.
  Future<void> invalidateDriveSession(String? accessToken) async {
    _driveAccount = null;
    if (accessToken == null) return;
    try {
      await GoogleSignInPlatform.instance.clearAuthorizationToken(
        ClearAuthorizationTokenParams(accessToken: accessToken),
      );
    } catch (e) {
      debugPrint('Clearing Drive token skipped: $e');
    }
  }

  /// Google Drive access token for the Google account LINKED to the
  /// signed-in user. Never shows an account chooser: the account is fixed
  /// (by its id and e-mail), so access granted once is remembered by the
  /// system and reused silently on every start.
  ///
  /// With [prompt] the Drive permission screen may be shown for that same
  /// account. Returns `token: null` when access is missing; `needsConnect`
  /// tells the caller the linked account's session must be restored first.
  Future<({String? token, bool needsConnect})> driveAccessToken({
    bool prompt = false,
  }) async {
    final user = _auth.currentUser;
    final linkedId = user == null ? null : googleIdOf(user);
    final email = user == null ? null : driveEmailOf(user);
    if (linkedId == null) return (token: null, needsConnect: true);

    await _ensureGoogle();
    // Account-specific authorization: silent on Android once granted.
    try {
      final data = await GoogleSignInPlatform.instance
          .clientAuthorizationTokensForScopes(
            ClientAuthorizationTokensForScopesParameters(
              request: AuthorizationRequestDetails(
                scopes: driveScopes,
                userId: linkedId,
                email: email,
                promptIfUnauthorized: prompt,
              ),
            ),
          )
          .timeout(Duration(seconds: prompt ? 90 : 30));
      if (data != null) return (token: data.accessToken, needsConnect: false);
      if (Platform.isAndroid) return (token: null, needsConnect: false);
    } catch (e) {
      debugPrint('Account-specific Drive authorization failed: $e');
      if (Platform.isAndroid && !prompt) {
        return (token: null, needsConnect: false);
      }
    }

    // iOS: authorization belongs to the restored (silent) Google session.
    final account = await driveAccountForCurrentUser();
    if (account == null) return (token: null, needsConnect: true);
    var authz = await account.authorizationClient.authorizationForScopes(
      driveScopes,
    );
    if (authz == null && prompt) {
      authz = await account.authorizationClient.authorizeScopes(driveScopes);
    }
    return (token: authz?.accessToken, needsConnect: false);
  }

  Future<GoogleSignInAccount?> _pickGoogleAccount() async {
    await _ensureGoogle();
    try {
      return await _googleSignIn.authenticate(scopeHint: driveScopes);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  OAuthCredential _credentialFor(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google sign-in could not be completed.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Drive permission prompt for [account] (no account choice). Declining
  /// is fine: the backup screen offers to allow it later.
  Future<void> _requestDrivePermission(GoogleSignInAccount account) async {
    try {
      await account.authorizationClient
          .authorizeScopes(driveScopes)
          .timeout(const Duration(minutes: 1));
    } catch (e) {
      debugPrint('Drive permission not granted: $e');
    }
  }

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  Future<void> signOut() async {
    _driveAccount = null;
    final wasGoogle =
        _auth.currentUser != null && isGoogleUser(_auth.currentUser!);
    if (wasGoogle) await _safeGoogleSignOut();
    await _auth.signOut();
  }

  Future<void> _safeGoogleSignOut() async {
    try {
      await _ensureGoogle();
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google sign-out skipped: $e');
    }
  }

  // ==========================================================
  // ERRORS
  // ==========================================================

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (e) {
      debugPrint('Auth error: ${e.code}');
      throw _fromFirebase(e);
    } on GoogleSignInException catch (e) {
      debugPrint('Google sign-in error: ${e.code}');
      throw const AuthFailure(
        'Google sign-in could not be completed. Please try again.',
      );
    } on TimeoutException {
      throw const AuthFailure(
        'The request took too long. Check your connection and try again.',
      );
    } on SocketException {
      throw const AuthFailure(
        'No internet connection. Please check your network and try again.',
      );
    } catch (e) {
      debugPrint('Unexpected auth error: $e');
      throw const AuthFailure('Something went wrong. Please try again.');
    }
  }

  static AuthFailure _fromFirebase(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return const AuthFailure(
          'Please enter a valid email address.',
          field: 'email',
        );
      case 'email-already-in-use':
        return const AuthFailure(
          'This email is already registered. Please sign in instead.',
          field: 'email',
        );
      case 'weak-password':
        return const AuthFailure(
          'This password is too weak. Use at least 8 characters with letters and numbers.',
          field: 'password',
        );
      case 'user-not-found':
        return const AuthFailure(
          'No account was found with this email address.',
          field: 'email',
        );
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return const AuthFailure('The email or password is incorrect.');
      case 'user-disabled':
        return const AuthFailure(
          'This account has been disabled. Please contact support.',
        );
      case 'too-many-requests':
        return const AuthFailure(
          'Too many attempts. Please wait a few minutes and try again.',
        );
      case 'network-request-failed':
        return const AuthFailure(
          'No internet connection. Please check your network and try again.',
        );
      case 'account-exists-with-different-credential':
        return const AuthFailure(
          'An account already exists with this email. Sign in with your email and password.',
        );
      case 'operation-not-allowed':
        return const AuthFailure(
          'This sign-in method is not available right now.',
        );
      default:
        return const AuthFailure('Something went wrong. Please try again.');
    }
  }
}
