import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AiService {
  AiService(this.auth, this.db);
  final FirebaseAuth auth;
  final FirebaseFirestore db;

  Future<String> ask(String prompt) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('You must be signed in to use the assistant.');
    final callable = db.collection('ai_requests').doc();
    await callable.set({'uid': user.uid, 'prompt': prompt.trim(), 'status': 'queued', 'createdAt': FieldValue.serverTimestamp()});
    // A deployed Cloud Function watches this queue and writes a protected response.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await callable.get();
      final data = snapshot.data() ?? {};
      if (data['status'] == 'complete') return data['response'] as String? ?? '';
      if (data['status'] == 'error') throw StateError(data['error'] as String? ?? 'AI service unavailable.');
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    throw StateError('The AI assistant timed out. Please try again.');
  }
}