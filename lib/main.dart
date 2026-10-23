
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Configure App Check before making Firebase requests.
    if (!kIsWeb) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity,
      );
    }

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    startupError = error.toString();
  }

  runApp(
    ProviderScope(
      child: ECampusApp(startupError: startupError),
    ),
  );
}
