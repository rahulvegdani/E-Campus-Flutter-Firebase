# E-Campus improvements in this source update

Implemented in the Flutter source:

- Dashboard quick-access tiles are tappable and navigate to Bus, Campus Chat, AI Assistant, and Notices.
- Dashboard greeting changes by local time and handles a blank display name.
- Profile screen now provides edit fields for name and email, plus photo upload to Firebase Storage. Course placement, role, and active status remain administrator-controlled to match the current Firestore security rules.
- Admin authorized-user list supports text search across name, phone, course, semester, division, and role, plus role filtering.
- Admin can edit authorized-user name, phone, role, department, semester, and division, and activate/deactivate records. When phone changes, the new phone-keyed authorization record is also written; the old record is retained to avoid destructive changes.
- Student roster/contact/mentor queries now use `isActive` to align with current user documents.

## Deployment notes

- The current signed-in user's Firestore rules must permit updating their own profile fields (`name`, `email`, `photoUrl`, `updatedAt`) while preventing role/activation changes.
- Firebase Storage rules must permit an authenticated user to upload to `profile_images/{uid}/...` only for their own UID.
- Admin Firestore rules must permit administrators to update `authorized_users`.
- Phone changes create the new authorization document but do not automatically migrate the Firebase Auth account or existing `users/{uid}` profile. Update those through the institution's trusted admin process if needed.
- The AI assistant still requires its documented Cloud Function/provider-key setup. Empty timetable, bus, library, notices, and attendance views still depend on actual Firestore data, indexes, and rules.
