import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final phone = TextEditingController();
  final code = TextEditingController();

  String? verificationId;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    final value = phone.text.trim();

    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value)) {
      setState(() {
        error = 'Enter a valid phone number with country code, '
            'for example +919998404307.';
      });
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await ref.read(authProvider).verifyPhoneNumber(
            phoneNumber: value,
            verificationCompleted: (credential) async {
              await _signIn(credential);
            },
            verificationFailed: (e) {
              if (!mounted) return;
              setState(() {
                busy = false;
                error = e.message ?? 'Phone verification failed.';
              });
            },
            codeSent: (id, _) {
              if (!mounted) return;
              setState(() {
                verificationId = id;
                busy = false;
              });
            },
            codeAutoRetrievalTimeout: (id) {
              verificationId = id;
            },
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.toString();
      });
    }
  }

  Future<void> verify() async {
    if (verificationId == null || code.text.trim().length < 6) {
      setState(() {
        error = 'Enter the six-digit verification code.';
      });
      return;
    }

    await _signIn(
      PhoneAuthProvider.credential(
        verificationId: verificationId!,
        smsCode: code.text.trim(),
      ),
    );
  }

  Future<void> _signIn(PhoneAuthCredential credential) async {
    if (!mounted) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result =
          await ref.read(authProvider).signInWithCredential(credential);

      final user = result.user;

      if (user == null) {
        throw StateError('Phone sign-in failed. Please try again.');
      }

      final key = user.phoneNumber ?? phone.text.trim();
      final firestore = ref.read(firestoreProvider);

      // Look up the authorized college account by phone number.
      final authDoc =
          await firestore.collection('authorized_users').doc(key).get();

      final authorized = authDoc.data();

      // Firestore uses "isActive", not "active".
      if (authorized == null ||
          (authorized['active'] != true && authorized['isActive'] != true)) {
        await ref.read(authProvider).signOut();

        throw StateError(
          'This phone number is not an active authorized college account.',
        );
      }

      // Keep profile field names consistent with the Firestore schema.
      final userRef = firestore.collection('users').doc(user.uid);
      final existingUser = await userRef.get();

      final profile = <String, dynamic>{
        'uid': user.uid,
        'phone': key,
        'phoneNumber': key,
        'name': authorized['name'] ?? 'Campus member',
        'active': true,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Set role/class metadata only when creating the profile. On later sign-ins,
      // do not overwrite administrator-managed fields from a client session.
      if (!existingUser.exists) {
        profile.addAll({
          'role': authorized['role'] ?? 'student',
          'department': authorized['department'] ?? '',
          'semester': authorized['semester'] ?? '',
          'division': authorized['division'] ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await userRef.set(profile, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        busy = false;
        error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCode = verificationId != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 48,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brandTertiary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.school_outlined,
                      color: AppColors.brand,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Welcome to E-Campus',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your secure college companion for classes, attendance, '
                    'resources, and campus life.',
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    enabled: !hasCode && !busy,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+919998404307',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  if (hasCode) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        prefixIcon: Icon(Icons.verified_outlined),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: busy ? null : (hasCode ? verify : sendCode),
                      child: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              hasCode
                                  ? 'Verify and continue'
                                  : 'Send verification code',
                            ),
                    ),
                  ),
                  if (hasCode)
                    Center(
                      child: TextButton(
                        onPressed: busy ? null : sendCode,
                        child: const Text('Use a different number'),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Only phone numbers pre-authorized by your college '
                    'administrator can access E-Campus.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
