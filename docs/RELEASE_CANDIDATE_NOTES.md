# E-Campus release-candidate notes

## Changes included in this package

- Phone sign-in accepts authorized-user status stored as either `active` or `isActive`.
- User profiles write both `phone`/`phoneNumber` and `active`/`isActive` for compatibility with the repository and older records.
- Existing profiles are updated only with safe profile/status/phone aliases; role and class metadata are not overwritten during routine sign-in.
- Firestore and Storage rules accept status/phone aliases while still requiring an explicitly active account and preserving role checks.
- Admin authorization controls read and update both status aliases.
- The AI Cloud Function accepts either active-status field.
- A Cloud Function sends an FCM push when a notice transitions to published, using tokens registered in `device_tokens`.
- `scripts/verify_windows.ps1` runs dependency resolution, analyzer, tests, and APK build locally without deploying anything.

## Required setup before live use

1. Review `firestore.rules` and `storage.rules` against the actual production collections and test accounts.
2. Deploy rules, indexes, and Functions only after reviewing the Firebase Console project and having a current backup/export.
3. Set the `GEMINI_API_KEY` Functions secret before deploying the AI processor.
4. Confirm Phone Authentication, Firestore, Storage, and Cloud Messaging are enabled for `e-campus-f025f`.
5. Confirm device tokens are registered and send a test notice to a small test audience before relying on push delivery.
6. Seed authorized users and teacher assignments using the documented trusted operator process.

## Verification status

- Produced from the uploaded source ZIP; generated Android build/cache files were excluded and archive paths normalized.
- Cloud Functions JavaScript syntax and JSON configuration are checked in this environment.
- This environment does not have the user's Flutter/Android toolchain or access to their live Firebase project. Therefore the Flutter build, Firestore Rules Emulator tests, OTP login, push delivery, and end-to-end feature flows have **not** been verified here. This is a release candidate, not a claim of fully production-verified behavior.
