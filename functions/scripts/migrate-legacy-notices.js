const admin = require('firebase-admin');

/*
 * E-Campus legacy notice migration
 *
 * Default mode:
 *   Preview changes only. Firestore is not modified.
 *
 * Apply mode:
 *   node scripts/migrate-legacy-notices.js --apply
 *
 * Safety:
 *   - Never changes published from false/missing to true.
 *   - Never deletes notices.
 *   - Never changes titles, descriptions, authors or categories.
 *   - Does not create or send notifications.
 *   - Adds only missing metadata fields.
 */

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const APPLY_CHANGES = process.argv.includes('--apply');

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value)
  );
}

/*
 * Converts supported Firestore timestamp/date values into a Firestore
 * Timestamp. Returns null when no valid date can be determined.
 */
function toFirestoreTimestamp(value) {
  if (!value) return null;

  if (
    typeof value.toDate === 'function' &&
    typeof value.seconds === 'number'
  ) {
    return value;
  }

  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return admin.firestore.Timestamp.fromDate(value);
  }

  if (typeof value === 'string' || typeof value === 'number') {
    const date = new Date(value);

    if (!Number.isNaN(date.getTime())) {
      return admin.firestore.Timestamp.fromDate(date);
    }
  }

  return null;
}

/*
 * Select an existing timestamp without inventing a publication date.
 */
function findExistingTimestamp(data) {
  const possibleFields = [
    'publishedAt',
    'createdAt',
    'updatedAt',
    'timestamp',
  ];

  for (const field of possibleFields) {
    const timestamp = toFirestoreTimestamp(data[field]);

    if (timestamp) {
      return timestamp;
    }
  }

  return null;
}

function buildMigration(data) {
  const updates = {};

  /*
   * Do not assume an unpublished or legacy notice should be published.
   * The teacher/admin must review and publish it through the app.
   */

  /*
   * Existing published notices without an audience are treated as
   * all-student notices for metadata compatibility.
   *
   * This does not cause a push notification because the Cloud Function
   * should ignore updates to documents that were already published.
   */
  if (
    data.published === true &&
    (
      typeof data.audienceType !== 'string' ||
      !data.audienceType.trim()
    )
  ) {
    updates.audienceType = 'allStudents';
  }

  /*
   * Add a publication timestamp only to notices already marked
   * published, and only when an existing timestamp is available.
   */
  if (
    data.published === true &&
    !toFirestoreTimestamp(data.publishedAt)
  ) {
    const timestamp = findExistingTimestamp(data);

    if (timestamp) {
      updates.publishedAt = timestamp;
    }
  }

  /*
   * Validate existing group-audience metadata instead of silently
   * converting a group notice into an all-student notice.
   */
  if (
    data.audienceType === 'groups' &&
    !Array.isArray(data.targetGroupKeys)
  ) {
    console.warn(
      'Review required: group notice has no targetGroupKeys.',
    );
  }

  return updates;
}

async function main() {
  console.log('E-Campus legacy notice migration');
  console.log(`Mode: ${APPLY_CHANGES ? 'APPLY CHANGES' : 'DRY RUN'}`);
  console.log('');

  const snapshot = await db.collection('notices').get();

  if (snapshot.empty) {
    console.log('No notices found. Nothing to migrate.');
    return;
  }

  let documentsWithChanges = 0;
  let totalFieldsToUpdate = 0;
  let skippedDocuments = 0;

  const operations = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();

    if (!isPlainObject(data)) {
      console.warn(`Skipping ${doc.id}: invalid document data.`);
      skippedDocuments++;
      continue;
    }

    const updates = buildMigration(data);
    const fields = Object.keys(updates);

    if (fields.length === 0) {
      console.log(`No changes needed: ${doc.id}`);
      continue;
    }

    documentsWithChanges++;
    totalFieldsToUpdate += fields.length;

    console.log(`Notice: ${doc.id}`);
    console.log(`  Fields to add/update: ${fields.join(', ')}`);

    for (const field of fields) {
      if (field === 'publishedAt') {
        console.log(
          `  ${field}: derived from an existing timestamp`,
        );
      } else {
        console.log(`  ${field}: ${updates[field]}`);
      }
    }

    operations.push({
      ref: doc.ref,
      updates,
    });
  }

  console.log('');
  console.log(`Notices scanned: ${snapshot.size}`);
  console.log(`Notices requiring changes: ${documentsWithChanges}`);
  console.log(`Fields requiring changes: ${totalFieldsToUpdate}`);
  console.log(`Skipped documents: ${skippedDocuments}`);

  if (!APPLY_CHANGES) {
    console.log('');
    console.log('DRY RUN ONLY: no Firestore documents were changed.');
    console.log(
      'Review the output before running the script with --apply.',
    );
    return;
  }

  if (operations.length === 0) {
    console.log('');
    console.log('No changes are required.');
    return;
  }

  /*
   * Firestore batched writes are limited to 500 operations per batch.
   * Process in smaller batches to leave room for future changes.
   */
  const batchSize = 400;
  let updatedDocuments = 0;

  for (let i = 0; i < operations.length; i += batchSize) {
    const batch = db.batch();
    const chunk = operations.slice(i, i + batchSize);

    for (const operation of chunk) {
      batch.update(operation.ref, operation.updates);
    }

    await batch.commit();
    updatedDocuments += chunk.length;

    console.log(
      `Applied migration to ${updatedDocuments}/${operations.length} notices.`,
    );
  }

  console.log('');
  console.log('Migration completed successfully.');
  console.log('Existing notice content was preserved.');
  console.log(
    'Legacy notices that are not published remain unpublished.',
  );
}

main().catch((error) => {
  console.error('Notice migration failed:', error);
  process.exitCode = 1;
});