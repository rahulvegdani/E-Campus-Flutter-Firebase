import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class DataRepository {
  DataRepository(this.db);
  final FirebaseFirestore db;

  Stream<UserProfile?> profile(String uid) => db.collection('users').doc(uid).snapshots().map((doc) => doc.exists ? UserProfile.fromMap(uid, doc.data() ?? {}) : null);
  Stream<List<Notice>> notices() => db.collection('notices').where('published', isEqualTo: true).orderBy('publishedAt', descending: true).limit(30).snapshots().map((s) => s.docs.map(Notice.fromDoc).toList());
  Stream<List<TimetableEntry>> timetable(UserProfile p) => db.collection('timetable').where('department', isEqualTo: p.department).where('semester', isEqualTo: p.semester).where('division', isEqualTo: p.division).snapshots().map((s) => s.docs.map(TimetableEntry.fromDoc).toList());
  Stream<List<TimetableEntry>> teacherTimetable(String uid) => db.collection('timetable').where('teacherUid', isEqualTo: uid).snapshots().map((s) => s.docs.map(TimetableEntry.fromDoc).toList());
  Stream<List<AttendanceSession>> teacherSessions(String uid) => db.collection('attendance_sessions').where('teacherUid', isEqualTo: uid).orderBy('dateKey', descending: true).limit(50).snapshots().map((s) => s.docs.map(AttendanceSession.fromDoc).toList());
  Stream<List<Map<String, dynamic>>> roster(UserProfile teacher, String department, String semester, String division) => db.collection('users').where('role', isEqualTo: 'student').where('active', isEqualTo: true).where('department', isEqualTo: department).where('semester', isEqualTo: semester).where('division', isEqualTo: division).orderBy('name').snapshots().map((s) => s.docs.map((d) => {'uid': d.id, ...d.data()}).toList());
  Stream<List<Map<String, dynamic>>> studentRecords(String uid) => db.collection('attendance_records').where('studentUid', isEqualTo: uid).orderBy('sessionDate', descending: true).limit(100).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Future<List<Map<String, dynamic>>> sessionRecords(String sessionId) async {
    final snap = await db.collection('attendance_records').where('sessionId', isEqualTo: sessionId).get();
    final records = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final uids = records.map((r) => r['studentUid'] as String? ?? '').where((u) => u.isNotEmpty).toSet().toList();
    final nameLookup = <String, String>{};
    for (var i = 0; i < uids.length; i += 10) {
      final chunk = uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10);
      final users = await db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
      for (final u in users.docs) {
        nameLookup[u.id] = (u.data()['name'] as String?) ?? '';
      }
    }
    for (final r in records) {
      r['studentName'] = nameLookup[r['studentUid']] ?? r['studentName'] ?? r['studentUid'] ?? '';
    }
    records.sort((a, b) => (a['studentName'] as String).compareTo(b['studentName'] as String));
    return records;
  }

  Future<Map<String, dynamic>?> findMentor(UserProfile student) async {
    if (student.mentorUid.isNotEmpty) {
      final doc = await db.collection('users').doc(student.mentorUid).get();
      if (doc.exists) return {'uid': doc.id, ...doc.data()!};
    }
    if (student.department.isEmpty) return null;
    final fallback = await db.collection('users').where('role', isEqualTo: 'teacher').where('active', isEqualTo: true).where('department', isEqualTo: student.department).limit(1).get();
    if (fallback.docs.isEmpty) return null;
    return {'uid': fallback.docs.first.id, ...fallback.docs.first.data()};
  }
  Stream<List<LibraryResource>> library() => db.collection('library').orderBy('title').snapshots().map((s) => s.docs.map(LibraryResource.fromDoc).toList());
  Stream<List<BusRoute>> buses() => db.collection('buses').orderBy('name').snapshots().map((s) => s.docs.map(BusRoute.fromDoc).toList());
  Stream<List<Map<String, dynamic>>> contacts(String uid) => db.collection('users').where('active', isEqualTo: true).limit(100).snapshots().map((s) => s.docs.where((d) => d.id != uid).map((d) => {'uid': d.id, ...d.data()}).toList());
  Stream<List<Map<String, dynamic>>> conversations(String uid) => db.collection('chat_conversations').where('participantUids', arrayContains: uid).orderBy('lastMessageAt', descending: true).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  Stream<List<Map<String, dynamic>>> messages(String conversationId) => db.collection('chat_conversations').doc(conversationId).collection('messages').orderBy('sentAt').snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Future<void> publishNotice({required UserProfile author, required String title, required String description, required String category}) async => db.collection('notices').add({'title': title.trim(), 'description': description.trim(), 'category': category, 'authorUid': author.uid, 'authorName': author.name, 'published': true, 'publishedAt': FieldValue.serverTimestamp()});

  Future<void> submitAttendance({required UserProfile teacher, required String department, required String semester, required String division, required String subjectId, required String subjectName, required List<Map<String, dynamic>> roster, required Map<String, bool> statuses}) async {
    final sessionRef = db.collection('attendance_sessions').doc('${teacher.uid}_${dateKey(DateTime.now())}_${subjectId}_$department$semester$division');
    final batch = db.batch();
    final present = statuses.values.where((v) => v).length;
    batch.set(sessionRef, {'teacherUid': teacher.uid, 'department': department, 'semester': semester, 'division': division, 'subjectId': subjectId, 'subjectName': subjectName, 'date': Timestamp.now(), 'dateKey': dateKey(DateTime.now()), 'startTime': '', 'endTime': '', 'presentCount': present, 'absentCount': statuses.length - present, 'status': 'submitted', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    for (final student in roster) { final uid = student['uid'] as String; final record = db.collection('attendance_records').doc('${sessionRef.id}_$uid'); batch.set(record, {'recordId': '${sessionRef.id}_$uid', 'sessionId': sessionRef.id, 'studentUid': uid, 'teacherUid': teacher.uid, 'department': department, 'semester': semester, 'division': division, 'sessionDate': dateKey(DateTime.now()), 'subjectId': subjectId, 'subjectName': subjectName, 'status': statuses[uid] == true ? 'present' : 'absent', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)); }
    await batch.commit();
  }

  Future<String> getOrCreateConversation(String uid, String otherUid) async { final existing = await db.collection('chat_conversations').where('participantUids', arrayContains: uid).get(); for (final d in existing.docs) { final p = List<String>.from(d.data()['participantUids'] as List? ?? []); if (p.contains(otherUid)) return d.id; } final doc = await db.collection('chat_conversations').add({'participantUids': [uid, otherUid], 'lastMessage': '', 'lastMessageAt': FieldValue.serverTimestamp()}); return doc.id; }
  Future<void> sendMessage(String conversationId, String uid, String text) async { final now = FieldValue.serverTimestamp(); final batch = db.batch(); final message = db.collection('chat_conversations').doc(conversationId).collection('messages').doc(); batch.set(message, {'senderUid': uid, 'text': text.trim(), 'sentAt': now, 'readBy': [uid]}); batch.update(db.collection('chat_conversations').doc(conversationId), {'lastMessage': text.trim(), 'lastMessageAt': now}); await batch.commit(); }
}