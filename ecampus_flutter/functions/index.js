const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const geminiApiKey = defineSecret('GEMINI_API_KEY');

exports.processAiRequest = onDocumentCreated({ document: 'ai_requests/{requestId}', secrets: [geminiApiKey], region: 'us-central1' }, async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const data = snapshot.data();
  if (!data || typeof data.uid !== 'string' || typeof data.prompt !== 'string') {
    await snapshot.ref.update({ status: 'error', error: 'Invalid assistant request.' });
    return;
  }
  const user = await admin.firestore().collection('users').doc(data.uid).get();
  if (!user.exists || user.data().active !== true) {
    await snapshot.ref.update({ status: 'error', error: 'Account is not active.' });
    return;
  }
  try {
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiApiKey.value()}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: `You are the E-Campus college assistant. Give concise, safe, helpful answers. Do not invent private college records. If uncertain, say so.\n\nQuestion: ${data.prompt}` }] }] }),
    });
    if (!response.ok) throw new Error(`Provider returned ${response.status}`);
    const result = await response.json();
    const answer = result.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!answer) throw new Error('Provider returned no text.');
    await snapshot.ref.update({ status: 'complete', response: answer, completedAt: admin.firestore.FieldValue.serverTimestamp() });
  } catch (error) {
    await snapshot.ref.update({ status: 'error', error: 'AI provider is temporarily unavailable.' });
    console.error('AI request failed', error.message);
  }
});