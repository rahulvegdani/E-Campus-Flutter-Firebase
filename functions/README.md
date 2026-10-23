# E-Campus Cloud Functions

The assistant is intentionally server-side. The Flutter app only creates an authenticated `ai_requests` document; this function verifies the active user and calls Gemini with a Firebase Functions secret.

```powershell
cd functions
npm install
firebase functions:secrets:set GEMINI_API_KEY --project e-campus-f025f
cd ..
firebase deploy --only functions:processAiRequest --project e-campus-f025f
```

Do not put the Gemini key in Flutter, Firestore documents, or source control. If the function is not deployed, the app shows an unavailable response rather than a fabricated answer.