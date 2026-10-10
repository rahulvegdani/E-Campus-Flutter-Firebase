# E-Campus — Flutter + Firebase (Standalone Delivery)

## Product
A standalone Flutter + Firebase college-management Android app (students, teachers, administrators), delivered as a source ZIP for the user to open and build in Android Studio on Windows. The existing workspace app is untouched.

## Deliverable
`/app/E-Campus-Flutter-Firebase.zip` — complete Flutter project at `ecampus_flutter/`, re-zipped after the latest `firestore.rules` hardening and after adding `.env.example`.

## Scope implemented (source only)
- Phone-OTP auth flow, authorized-user gating, role-based routing.
- Modules: Notices, Timetable, Attendance (session-based), E-Library, Tech News, Bus Tracking (routes/schedules; live GPS honestly disabled), Chat, AI Assistant (via Cloud Function), Profile.
- Firestore + Storage security rules, indexes, data model doc.
- Cloud Function `processAiRequest` that calls Gemini using `GEMINI_API_KEY` secret.

## Explicitly NOT verified in this environment
- `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug` — Flutter SDK not available in this container.
- Live Firebase Auth/Firestore/Storage/FCM behavior — requires the user's Firebase Console setup.
- Gemini responses — require the `GEMINI_API_KEY` secret on the user's Firebase project.

The user must perform the local checks per the README and `docs/test_report.md`.

## Credentials
No admin or user credentials were created or shipped. `test_credentials.md` intentionally empty — nothing to publish.
