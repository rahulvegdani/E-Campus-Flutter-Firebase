#!/usr/bin/env node
/**
 * E-Campus — first-admin seed script
 * ------------------------------------------------------------
 * Creates a single `authorized_users/{+E164 phone}` document with
 * role=admin and active=true, so one trusted person can sign in
 * via phone-OTP and bootstrap the rest of the system.
 *
 * This script runs OFFLINE on the operator's workstation and uses
 * a Firebase Admin service-account key. The key is NEVER checked
 * into source control and NEVER shipped inside the mobile client.
 *
 * Usage (PowerShell / bash):
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/service-account.json"
 *   node seed_admin.js --phone="+15551234567" --name="Jane Admin" \
 *     [--department="MCA"] [--semester=""] [--division=""]
 *
 * The service-account JSON is downloaded from:
 *   Firebase Console -> Project settings -> Service accounts -> Generate new private key
 * Delete the file (or restrict it with `chmod 600`) as soon as seeding is done.
 *
 * The script refuses to run if:
 *   - GOOGLE_APPLICATION_CREDENTIALS is missing
 *   - The phone number is not in E.164 format
 *   - A document already exists for that phone (prevents accidental overwrite)
 */

const admin = require('firebase-admin');

function parseArgs(argv) {
  const out = {};
  for (const raw of argv.slice(2)) {
    const match = raw.match(/^--([^=]+)=(.*)$/);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

function die(message) {
  console.error(`\n[seed_admin] ${message}\n`);
  process.exit(1);
}

async function main() {
  const args = parseArgs(process.argv);
  const phone = (args.phone || '').trim();
  const name = (args.name || '').trim();

  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    die(
      'GOOGLE_APPLICATION_CREDENTIALS is not set.\n' +
        'Export the absolute path to a service-account JSON before running this script.',
    );
  }
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
    die('Provide --phone in E.164 format, e.g. --phone="+15551234567".');
  }
  if (!name) {
    die('Provide --name="Full name of the administrator".');
  }

  admin.initializeApp({credential: admin.credential.applicationDefault()});
  const db = admin.firestore();
  const ref = db.collection('authorized_users').doc(phone);

  const existing = await ref.get();
  if (existing.exists) {
    die(
      `An authorized_users document already exists for ${phone}.\n` +
        'Delete it from the Firebase Console first if you really want to reseed.',
    );
  }

  const payload = {
    phone,
    name,
    role: 'admin',
    active: true,
    department: (args.department || '').trim(),
    semester: (args.semester || '').trim(),
    division: (args.division || '').trim(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    seededBy: 'scripts/seed_admin.js',
  };

  await ref.set(payload);
  console.log(`\n[seed_admin] authorized_users/${phone} created as admin.`);
  console.log('[seed_admin] Delete the service-account JSON when you are done.\n');
}

main().catch((err) => {
  console.error('\n[seed_admin] Unexpected error:', err);
  process.exit(1);
});
