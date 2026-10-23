import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
RemoteMessage message,
) async {
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);
}

class NotificationService {
NotificationService(this.messaging, this.db);

final FirebaseMessaging messaging;
final FirebaseFirestore db;

bool _tapConfigured = false;
bool _tokenRefreshConfigured = false;

void configureTapHandling() {
if (_tapConfigured) return;

_tapConfigured = true;

FirebaseMessaging.onMessageOpenedApp.listen((message) {
// Notification data is never trusted for authorization.
debugPrint('Notification opened: ${message.messageId}');
});
}

Future<void> register(String uid) async {
try {
final settings = await messaging.requestPermission(
alert: true,
badge: true,
sound: true,
);

if (settings.authorizationStatus == AuthorizationStatus.denied) {
debugPrint('Notification permission denied.');
return;
}

final token = await messaging.getToken();

if (token == null || token.isEmpty) {
debugPrint('FCM token is not available yet.');
return;
}

// Notification registration is optional. A Firestore permission
// error here must not interrupt authentication or app startup.
await _saveToken(uid, token);

// Register the token-refresh listener only once per service instance.
if (!_tokenRefreshConfigured) {
_tokenRefreshConfigured = true;

messaging.onTokenRefresh.listen(
(nextToken) async {
if (nextToken.isEmpty) return;
await _saveToken(uid, nextToken);
},
onError: (Object error) {
debugPrint('FCM token refresh stream error: $error');
},
);
}
} catch (error, stackTrace) {
debugPrint('Notification registration failed: $error');
debugPrintStack(stackTrace: stackTrace);

// Do not rethrow: notification setup should not crash login.
}
}

Future<void> _saveToken(String uid, String token) async {
try {
await db.collection('device_tokens').doc(uid).set({
'token': token,
'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
} catch (error, stackTrace) {
debugPrint('Device token save failed for user $uid: $error');
debugPrintStack(stackTrace: stackTrace);

// Firestore rules may not yet allow device_tokens writes.
// This failure must not block login.
}
}
}
