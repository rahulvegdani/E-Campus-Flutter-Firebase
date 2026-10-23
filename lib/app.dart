import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/models/models.dart';
import 'core/services/ai_service.dart';
import 'core/services/data_repository.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell/app_shell.dart';

final authProvider = Provider<FirebaseAuth>((_) => FirebaseAuth.instance);
final firestoreProvider =
    Provider<FirebaseFirestore>((_) => FirebaseFirestore.instance);
final dataRepositoryProvider = Provider<DataRepository>(
    (ref) => DataRepository(ref.watch(firestoreProvider)));
final aiServiceProvider = Provider<AiService>(
    (ref) => AiService(ref.watch(authProvider), ref.watch(firestoreProvider)));
final notificationServiceProvider = Provider<NotificationService>((ref) =>
    NotificationService(
        FirebaseMessaging.instance, ref.watch(firestoreProvider)));
final userProfileProvider = StreamProvider.family<UserProfile?, String>(
    (ref, uid) => ref.watch(dataRepositoryProvider).profile(uid));

class ECampusApp extends StatelessWidget {
  const ECampusApp({super.key, this.startupError});
  final String? startupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      title: 'E-Campus',
      home: startupError == null
          ? const AuthGate()
          : SetupRequiredScreen(error: startupError!));
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.cloud_off,
                  size: 48,
                  color: AppColors.brand,
                ),
                const SizedBox(height: 24),
                Text(
                  'Firebase setup required',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This source project intentionally contains no credentials. '
                  'Run flutterfire configure for e-campus-f025f, then rebuild.',
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamBuilder<User?>(
      stream: ref.watch(authProvider).authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        final user = snapshot.data;
        if (user == null) return const AuthScreen();
        return ref.watch(userProfileProvider(user.uid)).when(
            data: (profile) {
              if (profile == null || !profile.active) {
                return const InactiveAccountScreen();
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final notifications = ref.read(notificationServiceProvider);
                notifications.configureTapHandling();
                notifications.register(user.uid);
              });
              return AppShell(profile: profile);
            },
            loading: () => const Scaffold(
                body: Center(child: CircularProgressIndicator())),
            error: (error, _) =>
                ErrorScreen(message: 'Could not load your account: $error'));
      });
}

class InactiveAccountScreen extends ConsumerWidget {
  const InactiveAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 16),
                Text(
                  'Account access is pending',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'An administrator must activate your authorized college account.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref.read(authProvider).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(message, textAlign: TextAlign.center)))));
}
