import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

Future<fb.User?> signInWithGooglePlatform() async {
  final GoogleSignIn googleSignIn = GoogleSignIn();
  final GoogleSignInAccount? account = await googleSignIn.signIn();
  if (account == null) return null;
  final GoogleSignInAuthentication auth = await account.authentication;
  final fb.OAuthCredential credential = fb.GoogleAuthProvider.credential(
    idToken: auth.idToken,
    accessToken: auth.accessToken,
  );
  final fb.UserCredential userCred = await fb.FirebaseAuth.instance.signInWithCredential(credential);
  return userCred.user;
}




