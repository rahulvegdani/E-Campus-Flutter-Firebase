import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class NotificationService {
  NotificationService(this.messaging, this.db);
  final FirebaseMessaging messaging;
  final FirebaseFirestore db;
  bool _tapConfigured = false;

  void configureTapHandling() {
    if (_tapConfigured) return;
    _tapConfigured = true;
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      // The next app resume can use message.data['route'] for deep navigation.
      // Notification content is never trusted for authorization.
      debugPrint('Notification opened: ${message.messageId}');
    });
  }

  Future<void> register(String uid) async {
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await messaging.getToken();
    if (token == null) return;
    await db.collection('device_tokens').doc(uid).set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    messaging.onTokenRefresh.listen((next) => db.collection('device_tokens').doc(uid).update({'token': next, 'updatedAt': FieldValue.serverTimestamp()}));
  }
}