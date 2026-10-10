# scripts/

Operator-only utilities. **None of this ships inside the mobile app.**

## seed_admin.js — bootstrap admins and teachers

Why a separate script: the Flutter client cannot be allowed to grant admin or teaching permissions (that would let anyone with the APK promote themselves). Privileged seeding is therefore done directly through the Firebase Admin SDK, from a trusted workstation, using a service-account key that is never committed and never leaves that workstation.

### Prerequisites

- Node.js 18+
- Firebase Console → **Project settings → Service accounts → Generate new private key**. Save the JSON somewhere outside this repo and treat it like a password.

### Install

```powershell
cd scripts
npm install
```

(`npm install` is a one-time step; `node_modules/` is intentionally git-ignored.)

### Seed the first administrator

PowerShell on Windows:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
node seed_admin.js --role=admin --phone="+15551234567" --name="Jane Admin"
```

bash / zsh:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/service-account.json"
node seed_admin.js --role=admin --phone="+15551234567" --name="Jane Admin"
```

Writes a single `authorized_users/<E.164 phone>` document with `role: "admin"` and `active: true`.

### Seed a teacher together with their teaching assignments

```powershell
node seed_admin.js --role=teacher `
  --phone="+15559998888" --name="Dr. Smith" `
  --department="MCA" `
  --assignments="big_data:MCA:1:A,machine_learning:MCA:2:B"
```

`--assignments` is a comma-separated list of
`subjectId:department:semester:division` tuples. The script will:

1. Create (or leave alone) `authorized_users/<phone>` with `role: "teacher"`.
2. Look up the teacher in Firebase Authentication via `admin.auth().getUserByPhoneNumber(phone)`. If the account does not yet exist, it is created with that phone number so the UID is known **before** the teacher first logs in.
3. For every tuple, write a `teacher_assignments/<uid>_<subjectId>_<department>_<semester>_<division>` document — exactly the document ID the deployed Firestore security rules check with `exists(...)` when a teacher tries to mark attendance for a class.

This is the piece that makes new teachers productive from their very first OTP sign-in: the moment they land on the attendance screen the "Your assigned lectures" card already lists their classes, and `getAfter(...)` rules let their session writes succeed.

### Safety behaviour

- Refuses to run if `GOOGLE_APPLICATION_CREDENTIALS` is missing.
- Refuses to run if `--phone` is not strictly E.164.
- Refuses to run if `--role` is anything other than `admin` or `teacher`.
- Refuses to use `--assignments` with `--role=admin`.
- Warns (but does not fail) when a teacher is seeded with no assignments — they will be authorized but unable to mark any class until assignments are added.
- Will **not overwrite** an existing `authorized_users` document, so re-running the script is safe.

Delete the service-account JSON (or revoke the key in the Firebase Console) as soon as you have finished seeding.
