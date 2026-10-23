#!/usr/bin/env node
/**
 * E-Campus — operator seed script
 * ------------------------------------------------------------
 * Plants the very first administrator OR a teacher (with
 * their teacher_assignments) into Firestore from a trusted
 * workstation. This script never ships inside the mobile app
 * because it needs Firebase Admin SDK credentials, which must
 * never be bundled into a client.
 *
 * Usage (PowerShell / bash):
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/service-account.json"
 *
 *   # 1) First administrator
 *   node seed_admin.js --role=admin \
 *     --phone="+15551234567" --name="Jane Admin"
 *
 *   # 2) New teacher + their class/subject assignments
 *   node seed_admin.js --role=teacher \
 *     --phone="+15559998888" --name="Dr. Smith" \
 *     --department="MCA" \
 *     --assignments="big_data:MCA:1:A,machine_learning:MCA:2:B"
 *
 * --assignments is a comma-separated list of
 *   subjectId:department:semester:division
 * tuples. The script writes one teacher_assignments document per
 * tuple with the composite ID the firestore.rules expect, so the
 * teacher can start marking attendance on their very first login.
 *
 * The service-account JSON is downloaded from:
 *   Firebase Console -> Project settings -> Service accounts -> Generate new private key
 * Delete the file (or restrict it with `chmod 600`) as soon as seeding is done.
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

function parseAssignments(csv) {
  if (!csv) return [];
  return csv
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const bits = part.split(':').map((b) => b.trim());
      if (bits.length !== 4) {
        die(
          `Assignment "${part}" is not in the required subjectId:department:semester:division shape.`,
        );
      }
      const [subjectId, department, semester, division] = bits;
      if (!subjectId || !department || !semester || !division) {
        die(`Assignment "${part}" has an empty field.`);
      }
      return {subjectId, department, semester, division};
    });
}

async function resolveTeacherUid(phone) {
  try {
    const user = await admin.auth().getUserByPhoneNumber(phone);
    return user.uid;
  } catch (err) {
    if (err && err.code === 'auth/user-not-found') {
      const created = await admin.auth().createUser({phoneNumber: phone});
      console.log(`[seed_admin] Firebase Auth user created for ${phone} (uid=${created.uid}).`);
      return created.uid;
    }
    throw err;
  }
}

async function writeAuthorizedUser({phone, name, role, department}) {
  const db = admin.firestore();
  const ref = db.collection('authorized_users').doc(phone);
  const existing = await ref.get();
  if (existing.exists) {
    console.log(`[seed_admin] authorized_users/${phone} already exists, leaving it unchanged.`);
    return;
  }
  await ref.set({
    phone,
    name,
    role,
    active: true,
    department: department || '',
    semester: '',
    division: '',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    seededBy: 'scripts/seed_admin.js',
  });
  console.log(`[seed_admin] authorized_users/${phone} created as ${role}.`);
}

async function writeTeacherAssignments({uid, teacherPhone, teacherName, assignments}) {
  if (!assignments.length) return;
  const db = admin.firestore();
  const batch = db.batch();
  for (const a of assignments) {
    const id = `${uid}_${a.subjectId}_${a.department}_${a.semester}_${a.division}`;
    const ref = db.collection('teacher_assignments').doc(id);
    batch.set(
      ref,
      {
        teacherUid: uid,
        teacherPhone,
        teacherName,
        subjectId: a.subjectId,
        department: a.department,
        semester: a.semester,
        division: a.division,
        active: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        seededBy: 'scripts/seed_admin.js',
      },
      {merge: true},
    );
  }
  await batch.commit();
  console.log(`[seed_admin] ${assignments.length} teacher_assignments documents written for ${teacherPhone}.`);
}

async function main() {
  const args = parseArgs(process.argv);
  const phone = (args.phone || '').trim();
  const name = (args.name || '').trim();
  const role = (args.role || 'admin').trim().toLowerCase();
  const department = (args.department || '').trim();
  const assignments = parseAssignments(args.assignments);

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
    die('Provide --name="Full name".');
  }
  if (!['admin', 'teacher'].includes(role)) {
    die('--role must be "admin" or "teacher".');
  }
  if (role === 'admin' && assignments.length) {
    die('--assignments is only valid when --role=teacher.');
  }
  if (role === 'teacher' && !assignments.length) {
    console.warn(
      '[seed_admin] WARNING: no --assignments provided. The teacher will be authorized but will not be able to mark attendance for any class until teacher_assignments rows exist.',
    );
  }

  admin.initializeApp({credential: admin.credential.applicationDefault()});

  await writeAuthorizedUser({phone, name, role, department});

  if (role === 'teacher') {
    const uid = await resolveTeacherUid(phone);
    await writeTeacherAssignments({
      uid,
      teacherPhone: phone,
      teacherName: name,
      assignments,
    });
  }

  console.log('\n[seed_admin] Done. Delete the service-account JSON when you are finished.\n');
}

main().catch((err) => {
  console.error('\n[seed_admin] Unexpected error:', err);
  process.exit(1);
});
