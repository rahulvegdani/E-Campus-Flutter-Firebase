# E-Campus Flutter + Firebase

Standalone Android-first college management app for students, teachers, and administrators. This folder is separate from the existing workspace application and does not modify or delete its data.

## Project status

The Flutter source, Firebase rules/indexes, Cloud Function source, Android project shell, data model, and tests are included. This workspace did not contain Flutter, Dart, Android SDK, Firebase CLI, or the owner's Firebase client configuration, so compilation and live Firebase behavior could not be executed here. The credential-free `lib/firebase_options.dart` intentionally shows a setup screen until it is replaced by FlutterFire output.

## Windows setup

Install Flutter 3.47.1, Dart 3.13.1, Android Studio with an Android SDK/emulator, Node.js 20, and the Firebase CLI. Then run PowerShell from this directory:

```powershell
flutter doctor
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Install FlutterFire CLI if needed and connect the existing project, without creating a new Firebase project:

```powershell
dart pub global activate flutterfire_cli
flutterfire configure --project=e-campus-f025f --platforms=android --android-package-name=com.ecampus.e_campus
```

This replaces the safe placeholder in `lib/firebase_options.dart` with client configuration. Never paste a service-account private key into Flutter. The Android package name must remain `com.ecampus.e_campus`.

## Firebase Console checklist

1. Select project `e-campus-f025f`.
2. Enable Phone provider in Authentication and add the Android SHA-1 and SHA-256 fingerprints from the Android Studio signing report.
3. Enable Cloud Firestore and create the database in the intended region.
4. Enable Firebase Storage and review the included `storage.rules`.
5. Enable Cloud Messaging; request notification permission at runtime on Android 13+.
6. Create one `authorized_users` document whose ID is the exact E.164 phone number, for example `+15551234567`, with `phone`, `name`, `role` (`student`, `teacher`, or `admin`), `active: true`, and class fields.
7. Deploy rules and indexes after reviewing them:

```powershell
firebase login
firebase use e-campus-f025f
firebase deploy --only firestore:rules,firestore:indexes,storage
```

Do not make an administrator by editing the Flutter client. Seed the first administrator through a restricted operator process or Firebase Admin SDK script kept outside source control.

## Run in Android Studio

Open `/app/ecampus_flutter` as a Flutter project, let Android Studio sync, start an emulator or connect an Android device, then run:

```powershell
flutter run -d <device-id>
flutter build apk --debug
```

If Android Studio reports missing Gradle metadata, run `flutter create .` from this directory **only after backing up the source folder**. Keep the existing `lib`, `firebase.json`, rules, functions, and docs. This workspace could not generate the platform wrapper because the Flutter SDK is not installed.

## AI assistant

The Flutter client writes a request to `ai_requests`; it never holds an AI key. Install and deploy the function after enabling billing/limits appropriate for the Firebase project:

```powershell
cd functions
npm install
firebase functions:secrets:set GEMINI_API_KEY --project e-campus-f025f
cd ..
firebase deploy --only functions:processAiRequest --project e-campus-f025f
```

If the function or secret is missing, the assistant reports that it is unavailable rather than returning fake content.

## Role and data rules

Authorization is based on the Auth phone number matching `authorized_users`, followed by a UID-keyed `users` profile. Role and active status are immutable to the account owner. Teacher attendance writes require a matching `teacher_assignments` document; administrators can oversee records. Students can query only their own `attendance_records`. Conversation reads/writes require participant membership.

## Firebase data migration

The session-based attendance model is additive. Review `docs/data_model.md` and create a dry-run export before mapping legacy `attendance` data. Do not delete or overwrite existing users, notices, messages, or attendance documents.

## Known limitations and setup still required

- `firebase_options.dart` must be generated for the existing Firebase app.
- Firebase Console must enable phone auth, Firestore, Storage, FCM, and Android fingerprints.
- Initial authorized users and teaching assignments must be provisioned securely.
- Cloud Function deployment and `GEMINI_API_KEY` are required for the AI assistant.
- Live GPS bus tracking is deliberately not fabricated; the app shows published routes/schedules and clearly reports when a tracking source is absent.
- A real Flutter/Android build and Firebase integration test must be run on Windows; see `docs/test_report.md`.