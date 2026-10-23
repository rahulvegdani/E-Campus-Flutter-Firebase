# Firestore data model and migration notes

All user documents use the Firebase Auth UID as their document ID. Existing collections are preserved; the new session model is additive.

| Collection | Key fields | Access |
|---|---|---|
| `authorized_users/{phoneE164}` | `phone`, `name`, `role`, `active`, class fields | Admin writes; matching authenticated phone reads |
| `users/{uid}` | `uid`, `phone`, `name`, `role`, `active`, `department`, `semester`, `division` | Owner profile fields; admin/staff read |
| `notices/{id}` | title, description, category, authorUid, published, publishedAt | Active users read published; staff publish |
| `timetable/{id}` | class fields, subjectId, teacherUid, dayOfWeek, startTime, endTime, room | Active read; admin manage |
| `teacher_assignments/{uid_subject_class}` | teacherUid, subjectId, department, semester, division | Admin manage; assigned teacher read |
| `attendance_sessions/{stableId}` | class fields, teacherUid, dateKey, subjectId, counts, status | Teacher owner/admin; student only through own record |
| `attendance_records/{sessionId_uid}` | sessionId, studentUid, teacherUid, subjectId, status | Student own; teacher owner/admin |
| `library/{id}` | title, description, category, downloadUrl, storagePath | Active read; staff manage |
| `buses/{id}` | name, stops, schedule, lastUpdated, location | Active read; admin manage |
| `chat_conversations/{id}/messages/{id}` | senderUid, text, sentAt, readBy | Participants only |
| `device_tokens/{uid}` | token, updatedAt | Token owner only |
| `ai_requests/{id}` | uid, prompt, status, response | Additive queue; deploy function and tighten production rules if needed |

Migration is non-destructive: export existing data, map legacy attendance documents into `attendance_sessions` and `attendance_records`, then deploy rules/indexes. Never delete the legacy `attendance` collection until a verified migration report exists.