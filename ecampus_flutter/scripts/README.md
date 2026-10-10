# scripts/

Operator-only utilities. **None of this ships inside the mobile app.**

## seed_admin.js — bootstrap the first administrator

Why a separate script: the Flutter client cannot be allowed to create admins (that would let anyone with the APK promote themselves). The first `authorized_users` document is therefore planted directly through the privileged Firebase Admin SDK, from a trusted workstation, using a service-account key that is never committed and never leaves that workstation.

### Prerequisites

- Node.js 18+
- Firebase Console → **Project settings → Service accounts → Generate new private key**. Save the JSON somewhere outside this repo and treat it like a password.

### Install

```powershell
cd scripts
npm install
```

(`npm install` is a one-time step; `node_modules/` is intentionally git-ignored.)

### Run

PowerShell on Windows:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
node seed_admin.js --phone="+15551234567" --name="Jane Admin"
```

bash / zsh:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/service-account.json"
node seed_admin.js --phone="+15551234567" --name="Jane Admin"
```

Optional class fields: `--department="MCA"`, `--semester=""`, `--division=""`.

### What it writes

A single `authorized_users/<E.164 phone>` document with:

- `role: "admin"`
- `active: true`
- `createdAt` / `updatedAt` server timestamps
- `seededBy: "scripts/seed_admin.js"`

### Safety behaviour

- Refuses to run if `GOOGLE_APPLICATION_CREDENTIALS` is missing.
- Refuses to run if the phone number is not strictly E.164.
- Refuses to run if an `authorized_users` document already exists for that phone — delete it from the Firebase Console first if you really want to reseed.

Delete the service-account JSON (or revoke the key in the Firebase Console) as soon as you have finished seeding.
