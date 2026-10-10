# E-Campus verification report

## Executed in this workspace

- Project files were manually generated under `/app/ecampus_flutter` without modifying `/app/frontend` or `/app/backend`.
- Static source review was performed while generating the files.
- `node --check functions/index.js` passed.
- `firebase.json` and `firestore.indexes.json` parsed as valid JSON.
- Required source/configuration file inventory completed with no missing required paths.
- Repository-wide credential scan found no API keys, private keys, or protected existing-stack environment variables.
- Post-review hardening added exact authorized-user role/active/phone constraints, class-matched attendance record validation, immutable teacher session fields, and FCM tap-handler initialization.
- No Flutter SDK, Dart SDK, Firebase CLI, Android SDK, or Firebase client configuration was available in this workspace.
- Therefore `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, live OTP, Firestore, Storage, FCM, and Cloud Function behavior were **not executed** here.

## Implemented source flows

- Phone OTP sign-in with E.164 validation, resend path, invalid/expired/network error surface, authorized phone lookup, active-account check, and role profile creation.
- Student dashboard, own attendance summary, timetable, notices, library, buses, authorized contacts, 1-to-1 conversation flow, profile, and AI request flow.
- Teacher/admin attendance class selection, roster query, mark-all-present, batch session and record writes, session history with tap-to-export CSV sheet, notice publishing, timetable prefill, weekly trend chart, and role-aware shell.
- Student low-attendance banner with per-subject chips and a one-tap "Message mentor" action backed by `DataRepository.findMentor`.
- Firestore/Storage rules, compound indexes, FCM token registration, Cloud Function AI queue, schema documentation, operator seed script (admin + teacher assignments), and test scaffold.

## Deliberate security decisions

- `/users/{uid}` is readable by any `active()` user. This is required for the campus
  directory (chat contacts, mentor lookup, notice/attendance author display) to work
  without a dedicated Cloud Function. All writes remain strictly controlled: self-updates
  can only touch `name`, `email`, `photoUrl`, and `updatedAt`; `role`, `active`,
  `department`, `semester`, `division` are admin-only.
- Operator seeding is handled by `scripts/seed_admin.js` with the Firebase Admin SDK
  on a trusted workstation. The service-account JSON must never be committed and must
  be deleted after seeding.
- The Flutter client never holds AI provider keys; it writes to `ai_requests` and the
  deployed Cloud Function fulfils the request using a Firebase Functions secret.

## Required validation on Windows

Run the commands in the root README after installing Flutter 3.47.1, Dart 3.13.1,
Android Studio, FlutterFire CLI, and configuring Firebase project `e-campus-f025f`.
