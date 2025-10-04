import 'package:firebase_auth/firebase_auth.dart' as fb;

Future<fb.User?> signInWithGooglePlatform() async {
  final fb.GoogleAuthProvider provider = fb.GoogleAuthProvider();
  final fb.UserCredential userCred = await fb.FirebaseAuth.instance.signInWithPopup(provider);
  return userCred.user;
}




