const {
  onDocumentCreated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();

const geminiApiKey = defineSecret('GEMINI_API_KEY');

/*
 * E-Campus AI Assistant
 * Preserved from the existing Cloud Functions implementation.
 */
exports.processAiRequest = onDocumentCreated(
  {
    document: 'ai_requests/{requestId}',
    secrets: [geminiApiKey],
    region: 'us-central1',
  },
  async (event) => {
    const snapshot = event.data;

    if (!snapshot) return;

    const data = snapshot.data();

    if (
      !data ||
      typeof data.uid !== 'string' ||
      typeof data.prompt !== 'string'
    ) {
      await snapshot.ref.update({
        status: 'error',
        error: 'Invalid assistant request.',
      });
      return;
    }

    try {
      const userSnapshot = await admin
        .firestore()
        .collection('users')
        .doc(data.uid)
        .get();

      const userData = userSnapshot.exists
        ? userSnapshot.data()
        : null;

      if (
        !userData ||
        (userData.active !== true && userData.isActive !== true)
      ) {
        await snapshot.ref.update({
          status: 'error',
          error: 'Account is not active.',
        });
        return;
      }

      const response = await fetch(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=' +
          encodeURIComponent(geminiApiKey.value()),
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            contents: [
              {
                role: 'user',
                parts: [
                  {
                    text:
                      'You are the E-Campus college assistant. ' +
                      'Give concise, safe, helpful answers. ' +
                      'Do not invent private college records. ' +
                      'If uncertain, say so.\n\nQuestion: ' +
                      data.prompt,
                  },
                ],
              },
            ],
          }),
        },
      );

      if (!response.ok) {
        throw new Error(`AI provider returned HTTP ${response.status}`);
      }

      const result = await response.json();
      const answer =
        result.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!answer) {
        throw new Error('AI provider returned no answer.');
      }

      await snapshot.ref.update({
        status: 'complete',
        response: answer,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error('AI request failed:', error.message);

      await snapshot.ref.update({
        status: 'error',
        error: 'AI assistant is temporarily unavailable.',
      });
    }
  },
);

/*
 * Notice audience helpers.
 *
 * Group keys use the same field names and formatting as the
 * student documents in Firestore:
 * department, semester and division.
 */
function normalizeGroupValue(value) {
  return String(value ?? '').trim().toLowerCase();
}

function noticeGroupKey(data) {
  return [
    normalizeGroupValue(data.department),
    normalizeGroupValue(data.semester),
    normalizeGroupValue(data.division),
  ].join('|');
}

/*
 * Send push notifications when a notice is published.
 *
 * Expected notice fields:
 *   published: boolean
 *   title: string
 *   description: string
 *   audienceType: 'allStudents' or 'groups'
 *   targetGroupKeys: string[]
 *
 * Expected device token structure:
 *   device_tokens/{userId}
 *   { token: 'FCM_DEVICE_TOKEN' }
 */
exports.notifyPublishedNotice = onDocumentWritten(
  {
    document: 'notices/{noticeId}',
    region: 'us-central1',
  },
  async (event) => {
    const beforeSnapshot = event.data?.before;
    const afterSnapshot = event.data?.after;

    const before =
      beforeSnapshot?.exists ? beforeSnapshot.data() : null;

    const after =
      afterSnapshot?.exists ? afterSnapshot.data() : null;

    // Ignore deleted documents and documents that are not published.
    if (!after || after.published !== true) {
      return;
    }

    // Send only on the transition to published.
    // Draft creation and edits to already-published notices are ignored.
    if (before?.published === true) {
      return;
    }

    const audienceType = after.audienceType || 'allStudents';

    if (!['allStudents', 'groups'].includes(audienceType)) {
      console.warn(
        'Unsupported notice audience:',
        event.params.noticeId,
        audienceType,
      );
      return;
    }

    const targetGroupKeys = Array.isArray(after.targetGroupKeys)
      ? after.targetGroupKeys
      : [];

    if (
      audienceType === 'groups' &&
      targetGroupKeys.length === 0
    ) {
      console.warn(
        'Group notice has no target groups:',
        event.params.noticeId,
      );
      return;
    }

    const db = admin.firestore();

    const studentsSnapshot = await db
      .collection('users')
      .where('role', '==', 'student')
      .get();

    const eligibleUids = new Set();

    for (const studentDoc of studentsSnapshot.docs) {
      const student = studentDoc.data();

      // Only notify active student accounts.
      if (
        student.active !== true &&
        student.isActive !== true
      ) {
        continue;
      }

      if (audienceType === 'allStudents') {
        eligibleUids.add(studentDoc.id);
        continue;
      }

      const studentKey = noticeGroupKey(student);

      const normalizedTargetKeys = targetGroupKeys.map(
        (key) => String(key).trim().toLowerCase(),
      );

      if (normalizedTargetKeys.includes(studentKey)) {
        eligibleUids.add(studentDoc.id);
      }
    }

    if (eligibleUids.size === 0) {
      console.info(
        'No active students matched notice:',
        event.params.noticeId,
      );
      return;
    }

    const tokenSnapshot = await db
      .collection('device_tokens')
      .get();

    const eligibleTokens = tokenSnapshot.docs.filter((tokenDoc) => {
      const tokenData = tokenDoc.data();

      return (
        eligibleUids.has(tokenDoc.id) &&
        typeof tokenData.token === 'string' &&
        tokenData.token.trim().length > 0
      );
    });

    if (eligibleTokens.length === 0) {
      console.info(
        'No device tokens found for eligible students:',
        event.params.noticeId,
      );
      return;
    }

    const title =
      typeof after.title === 'string' && after.title.trim()
        ? after.title.trim()
        : 'New campus notice';

    const description =
      typeof after.description === 'string'
        ? after.description.trim()
        : '';

    const body =
      description.length > 160
        ? `${description.slice(0, 157)}...`
        : description || 'A new notice has been published.';

    let successCount = 0;
    let failureCount = 0;

    // FCM multicast requests support up to 500 tokens per batch.
    for (let i = 0; i < eligibleTokens.length; i += 500) {
      const batch = eligibleTokens.slice(i, i + 500);

      try {
        const response = await admin.messaging().sendEachForMulticast({
          tokens: batch.map((doc) => doc.data().token),

          notification: {
            title,
            body,
          },

          data: {
            type: 'notice',
            noticeId: event.params.noticeId,
          },

          android: {
            priority: 'high',
            notification: {
              channelId: 'campus_notices',
            },
          },
        });

        successCount += response.successCount;
        failureCount += response.failureCount;

        // Remove invalid or expired tokens.
        const deletions = [];

        response.responses.forEach((result, index) => {
          const code = result.error?.code || '';

          if (
            !result.success &&
            (
              code.includes('registration-token-not-registered') ||
              code.includes('invalid-registration-token')
            )
          ) {
            deletions.push(batch[index].ref.delete());
          }
        });

        if (deletions.length > 0) {
          await Promise.all(deletions);
        }
      } catch (error) {
        failureCount += batch.length;

        console.error(
          'Notice push batch failed:',
          event.params.noticeId,
          error.message,
        );
      }
    }

    console.info('Notice push delivery completed:', {
      noticeId: event.params.noticeId,
      audienceType,
      eligibleStudents: eligibleUids.size,
      eligibleTokens: eligibleTokens.length,
      successCount,
      failureCount,
    });
  },
);