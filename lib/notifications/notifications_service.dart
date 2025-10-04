import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:riverpod/riverpod.dart';

class NotificationsService {
  NotificationsService(this._messaging, this._db);
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  Future<void> initAndRegisterToken() async {
    // Request permissions where applicable
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    // iOS/APNs fallback
    if (Platform.isIOS) {
      await _messaging.setAutoInitEnabled(true);
    }

    String? token = await _messaging.getToken();
    if (token == null) return;

    final fb.User? user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _db.collection('users').doc(user.uid).set({
      'fcmTokens': {
        token: {
          'platform': Platform.operatingSystem,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        }
      }
    }, SetOptions(merge: true));

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) async {
      await _db.collection('users').doc(user.uid).set({
        'fcmTokens': {
          newToken: {
            'platform': Platform.operatingSystem,
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          }
        }
      }, SetOptions(merge: true));
    });
  }
}

final Provider<NotificationsService> notificationsServiceProvider = Provider<NotificationsService>((ref) {
  return NotificationsService(FirebaseMessaging.instance, FirebaseFirestore.instance);
});




