import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart' hide GoogleSignIn; // avoid web build issues
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter/material.dart' show debugPrint; 
// Conditional imports for Google Sign-In
import 'google_signin_stub.dart' if (dart.library.html) 'google_signin_web.dart' if (dart.library.io) 'google_signin_mobile.dart';

/// Simple user representation for stubs
@immutable
class AppUser {
  const AppUser({required this.uid, this.email, this.phoneNumber, this.displayName});
  final String uid;
  final String? email;
  final String? phoneNumber;
  final String? displayName;
}

/// Repository responsible for authentication flows
class AuthRepository {
  const AuthRepository();

  Future<AppUser?> signInWithGoogle() async {
    try {
      final fb.User? u = await signInWithGooglePlatform();
      if (u == null) return null;
      return AppUser(uid: u.uid, email: u.email, displayName: u.displayName);
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      rethrow;
    }
  }

  Future<AppUser?> signInWithApple() async {
    final bool isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      throw StateError('Apple Sign-In is not available on this platform.');
    }
    final AuthorizationCredentialAppleID apple = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    final fb.OAuthCredential oauth = fb.OAuthProvider("apple.com").credential(
      idToken: apple.identityToken,
      accessToken: apple.authorizationCode,
    );
    final fb.UserCredential userCred = await fb.FirebaseAuth.instance.signInWithCredential(oauth);
    final fb.User? u = userCred.user;
    if (u == null) return null;
    return AppUser(uid: u.uid, email: u.email, displayName: u.displayName);
  }

  Future<AppUser?> signInWithEmailPassword({required String email, required String password}) async {
    final fb.UserCredential userCred = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final fb.User? u = userCred.user;
    if (u == null) return null;
    return AppUser(uid: u.uid, email: u.email, displayName: u.displayName);
  }

  Future<AppUser?> signUpWithEmailPassword({required String email, required String password}) async {
    final fb.UserCredential userCred = await fb.FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final fb.User? u = userCred.user;
    if (u == null) return null;
    return AppUser(uid: u.uid, email: u.email, displayName: u.displayName);
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return fb.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<AppUser?> signInWithPhoneNumber({required String phoneNumber}) async {
    final Completer<AppUser?> completer = Completer<AppUser?>();
    await fb.FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (fb.PhoneAuthCredential credential) async {
        final fb.UserCredential cred = await fb.FirebaseAuth.instance.signInWithCredential(credential);
        final fb.User? u = cred.user;
        completer.complete(u == null ? null : AppUser(uid: u.uid, phoneNumber: u.phoneNumber, displayName: u.displayName));
      },
      verificationFailed: (fb.FirebaseAuthException e) {
        completer.completeError(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        // store verificationId in provider for later confirmation
        _phoneAuthState?.setVerification(verificationId, resendToken);
        completer.complete(null);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _phoneAuthState?.setVerification(verificationId, null);
      },
    );
    return completer.future;
  }

  Future<AppUser?> confirmPhoneCode({required String verificationId, required String smsCode}) async {
    final fb.PhoneAuthCredential credential = fb.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final fb.UserCredential cred = await fb.FirebaseAuth.instance.signInWithCredential(credential);
    final fb.User? u = cred.user;
    if (u == null) return null;
    return AppUser(uid: u.uid, phoneNumber: u.phoneNumber, displayName: u.displayName);
  }

  Future<void> signOut() async {
    await fb.FirebaseAuth.instance.signOut();
  }
}

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = const AuthRepository();
  _phoneAuthState = ref.read(phoneAuthStateProvider.notifier);
  ref.onDispose(() => _phoneAuthState = null);
  return repo;
});

class CurrentUser extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  void set(AppUser? user) {
    state = user;
  }
}

final NotifierProvider<CurrentUser, AppUser?> currentUserProvider =
    NotifierProvider<CurrentUser, AppUser?>(CurrentUser.new);

class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier() {
    _sub = fb.FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final Provider<AuthChangeNotifier> authChangeNotifierProvider = Provider<AuthChangeNotifier>((ref) {
  final notifier = AuthChangeNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});

class PhoneAuthState extends Notifier<({String? verificationId, int? resendToken})> {
  @override
  ({String? verificationId, int? resendToken}) build() => (verificationId: null, resendToken: null);

  void setVerification(String verificationId, int? resendToken) {
    state = (verificationId: verificationId, resendToken: resendToken);
  }

  void clear() {
    state = (verificationId: null, resendToken: null);
  }
}

final NotifierProvider<PhoneAuthState, ({String? verificationId, int? resendToken})>
    phoneAuthStateProvider = NotifierProvider<PhoneAuthState, ({String? verificationId, int? resendToken})>(
  PhoneAuthState.new,
);

// internal handle to update from repository
PhoneAuthState? _phoneAuthState;


