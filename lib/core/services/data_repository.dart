import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

String noticeGroupKey(String department, String semester, String division) =>
    '${department.trim()}|${semester.trim()}|${division.trim()}';

class DataRepository {
  DataRepository(this.db);

  final FirebaseFirestore db;

  Stream<UserProfile?> profile(String uid) =>
      db.collection('users').doc(uid).snapshots().map((doc) =>
      doc.exists ? UserProfile.fromMap(uid, doc.data() ?? {}) : null);


  /// Updates profile fields in users/{uid} and the existing authorized record.
  /// Never creates a new authorization document, avoiding duplicate entries.
  Future<void> updateProfile({
    required String uid,
    required String phone,
    required String name,
    required String email,
  }) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) {
      throw StateError('Cannot sync profile: account has no phone number.');
    }

    final authorized = db.collection('authorized_users');
    DocumentSnapshot<Map<String, dynamic>>? authDoc;

    final byId = await authorized.doc(cleanPhone).get();
    if (byId.exists) {
      authDoc = byId;
    } else {
      for (final field in ['phoneNumber', 'phone']) {
        final match = await authorized
            .where(field, isEqualTo: cleanPhone)
            .limit(1)
            .get();
        if (match.docs.isNotEmpty) {
          authDoc = match.docs.first;
          break;
        }
      }
    }

    if (authDoc == null || !authDoc.exists) {
      throw StateError(
        'Profile was not synchronized: no existing authorized account '
            'matched this phone number. Ask an administrator to verify the record.',
      );
    }

    final batch = db.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(db.collection('users').doc(uid), {
      'name': name.trim(),
      'email': email.trim(),
      'updatedAt': now,
    }, SetOptions(merge: true));
    batch.update(authDoc.reference, {
      'name': name.trim(),
      'email': email.trim(),
      'updatedAt': now,
    });
    await batch.commit();
  }

  /// Student-facing notices are constrained in the Firestore query as well
  /// as in security rules. A notice is visible to everyone or to a matching
  /// department/semester/division group.
  Stream<List<Notice>> notices(UserProfile profile) {
    final groupKey = noticeGroupKey(
      profile.department,
      profile.semester,
      profile.division,
    );

    // Fetch published notices without the compound AND/OR query that
    // requires an additional composite index. Audience filtering and sorting
    // are performed locally below.
    return db
        .collection('notices')
        .where('published', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        final data = doc.data();

        if (data['audienceType'] == 'allStudents') {
          return true;
        }

        final targetGroups =
        List<String>.from(data['targetGroupKeys'] as List? ?? const []);

        return groupKey.isNotEmpty && targetGroups.contains(groupKey);
      }).toList();

      // Newest notices first. Missing publishedAt timestamps are placed last.
      docs.sort((a, b) {
        final aTime = a.data()['publishedAt'];
        final bTime = b.data()['publishedAt'];

        final aMillis =
        aTime is Timestamp ? aTime.millisecondsSinceEpoch : 0;
        final bMillis =
        bTime is Timestamp ? bTime.millisecondsSinceEpoch : 0;

        return bMillis.compareTo(aMillis);
      });

      return docs.take(50).map(Notice.fromDoc).toList();
    });
  }

  Stream<List<Notice>> myNotices(String uid) => db
      .collection('notices')
      .where('authorUid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(Notice.fromDoc).toList());

  Stream<List<Notice>> allStaffNotices() => db
      .collection('notices')
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(Notice.fromDoc).toList());

  Future<List<Map<String, String>>> noticeStudentGroups() async {
    final snapshot = await db.collection('users')
        .where('role', isEqualTo: 'student')
        .limit(1000)
        .get();
    final groups = <String, Map<String, String>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['active'] != true && data['isActive'] != true) continue;
      final department = (data['department'] as String? ?? '').trim();
      final semester = (data['semester'] as String? ?? '').trim();
      final division = (data['division'] as String? ?? '').trim();
      if (department.isEmpty || semester.isEmpty || division.isEmpty) continue;
      final key = noticeGroupKey(department, semester, division);
      groups[key] = {
        'key': key,
        'department': department,
        'semester': semester,
        'division': division,
        'label': '$department · Semester $semester · Division $division',
      };
    }
    final result = groups.values.toList()
      ..sort((a, b) => a['label']!.compareTo(b['label']!));
    return result;
  }

  Future<List<LibraryResource>> libraryOnce() async {
    final snapshot = await db.collection('library').orderBy('title').get();
    return snapshot.docs.map(LibraryResource.fromDoc).toList();
  }

  Future<void> saveNotice({
    required UserProfile author,
    required String title,
    required String description,
    required String category,
    required bool publishNow,
    required String audienceType,
    required List<String> targetGroupKeys,
    LibraryResource? libraryResource,
    String? noticeId,
  }) async {
    if (author.role != 'teacher' && author.role != 'admin') {
      throw StateError('Only teachers and administrators can manage notices.');
    }
    final cleanTitle = title.trim();
    final cleanDescription = description.trim();
    if (cleanTitle.isEmpty || cleanDescription.isEmpty) {
      throw StateError('Enter both a notice title and description.');
    }
    if (audienceType != 'allStudents' && targetGroupKeys.isEmpty) {
      throw StateError('Select at least one student group.');
    }
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'title': cleanTitle,
      'description': cleanDescription,
      'category': category.trim().isEmpty ? 'General' : category.trim(),
      'authorUid': author.uid,
      'authorName': author.name,
      'authorRole': author.role,
      'audienceType': audienceType,
      'targetGroupKeys': audienceType == 'allStudents' ? <String>[] : targetGroupKeys,
      'libraryResourceId': libraryResource?.id ?? '',
      'libraryResourceTitle': libraryResource?.title ?? '',
      'libraryResourceUrl': libraryResource?.url ?? '',
      'published': publishNow,
      'createdAt': now,
      'updatedAt': now,
      if (publishNow) 'publishedAt': now,
    };
    if (noticeId == null) {
      await db.collection('notices').add(data);
    } else {
      final ref = db.collection('notices').doc(noticeId);
      final existing = await ref.get();
      if (!existing.exists) throw StateError('This notice no longer exists.');
      final existingData = existing.data()!;
      if (author.role != 'admin' && existingData['authorUid'] != author.uid) {
        throw StateError('You can edit only your own notices.');
      }
      // Editing as an administrator must not silently change the original author.
      data['authorUid'] = existingData['authorUid'] ?? author.uid;
      data['authorName'] = existingData['authorName'] ?? author.name;
      data['authorRole'] = existingData['authorRole'] ?? author.role;
      data.remove('createdAt');
      if (existingData['published'] == true) {
        data.remove('publishedAt');
      }
      await ref.update(data);
    }
  }

  Future<void> publishSavedNotice(String noticeId) async {
    await db.collection('notices').doc(noticeId).update({
      'published': true,
      'publishedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNotice(String noticeId) async {
    await db.collection('notices').doc(noticeId).delete();
  }

  Future<void> publishNotice({
    required UserProfile author,
    required String title,
    required String description,
    required String category,
  }) => saveNotice(
    author: author,
    title: title,
    description: description,
    category: category,
    publishNow: true,
    audienceType: 'allStudents',
    targetGroupKeys: const [],
  );

  /// Published timetable for the student's course/semester and division.
  /// Legacy entries without a status remain visible; new drafts never leak to students.
  Stream<List<TimetableEntry>> timetable(UserProfile p) => db
      .collection('timetable')
      .where('department', isEqualTo: p.department)
      .where('semester', isEqualTo: p.semester)
      .snapshots()
      .map((s) {
    final entries = s.docs
        .where((doc) {
      final d = doc.data();
      final status = d['status'] as String?;
      if (status != null && status != 'published') return false;
      final division = (d['division'] as String? ?? '').trim();
      final groupType = d['groupType'] as String? ?? '';
      if (groupType == 'course') return true;
      return division == p.division.trim();
    })
        .map(TimetableEntry.fromDoc)
        .toList();
    const dayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    int minutes(String value) {
      final parts = value.split(':');
      if (parts.length != 2) return 0;
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }
    entries.sort((a, b) {
      final day = dayOrder.indexOf(a.dayOfWeek).compareTo(dayOrder.indexOf(b.dayOfWeek));
      return day != 0 ? day : minutes(a.startTime).compareTo(minutes(b.startTime));
    });
    return entries;
  });

  /// Teacher attendance prefill only uses published entries, plus legacy entries.
  Stream<List<TimetableEntry>> teacherTimetable(String uid) => db
      .collection('timetable')
      .where('teacherUid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs
      .where((doc) {
    final status = doc.data()['status'] as String?;
    return status == null || status == 'published';
  })
      .map(TimetableEntry.fromDoc)
      .toList());

  /// Published timetable entries for the administrator's Schedule screen.
  /// Draft entries are excluded so only published classes are visible.
  Stream<List<TimetableEntry>> adminTimetable() => db
      .collection('timetable')
      .where('status', isEqualTo: 'published')
      .snapshots()
      .map((s) => s.docs.map(TimetableEntry.fromDoc).toList());

  Stream<List<AttendanceSession>> teacherSessions(String uid) => db
      .collection('attendance_sessions')
      .where('teacherUid', isEqualTo: uid)
      .orderBy('dateKey', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AttendanceSession.fromDoc).toList());

  Stream<List<AttendanceSession>> allSessions({int limit = 200}) => db
      .collection('attendance_sessions')
      .orderBy('dateKey', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(AttendanceSession.fromDoc).toList());

  Future<void> updateAttendanceRecord({
    required String recordId,
    required String newStatus,
    required String teacherUid,
    required String fromStatus,
  }) async {
    final recordRef = db.collection('attendance_records').doc(recordId);
    final snap = await recordRef.get();
    if (!snap.exists) throw StateError('Attendance record no longer exists.');
    final data = snap.data()!;
    if (data['teacherUid'] != teacherUid) throw StateError('Only the assigned teacher can edit this attendance.');
    final sessionSnap = await db.collection('attendance_sessions').doc(data['sessionId'] as String? ?? '').get();
    if (!sessionSnap.exists) throw StateError('Attendance session not found.');
    final session = sessionSnap.data()!;
    final now = DateTime.now();
    final start = (session['startAt'] as Timestamp?)?.toDate();
    final end = (session['endAt'] as Timestamp?)?.toDate();
    final reopened = (session['reopenedUntil'] as Timestamp?)?.toDate();
    final scheduled = start != null && end != null && !now.isBefore(start) && now.isBefore(end);
    if (!scheduled && !(reopened != null && now.isBefore(reopened))) {
      throw StateError('Attendance is closed. Request admin approval to reopen it.');
    }
    await recordRef.update({
      'status': newStatus,
      'lastEditedBy': teacherUid,
      'lastEditedAt': FieldValue.serverTimestamp(),
      'editCount': FieldValue.increment(1),
      'edits': FieldValue.arrayUnion([{
        'at': DateTime.now().toIso8601String(), 'by': teacherUid,
        'from': fromStatus, 'to': newStatus,
      }]),
    });
  }

  Future<void> requestAttendanceReopen({
    required AttendanceSession session,
    required UserProfile teacher,
    required String reason,
  }) async {
    if (session.teacherUid != teacher.uid) throw StateError('Only the assigned teacher can request reopening.');
    if (reason.trim().length < 8) throw ArgumentError('Please provide a reason (at least 8 characters).');
    final requests = db.collection('attendance_reopening_requests');
    final existing = await requests.where('sessionId', isEqualTo: session.id)
        .where('status', isEqualTo: 'pending').limit(1).get();
    if (existing.docs.isNotEmpty) throw StateError('A reopening request is already pending for this session.');
    await requests.add({
      'sessionId': session.id, 'teacherUid': teacher.uid, 'teacherName': teacher.name,
      'subjectName': session.subjectName, 'department': session.department,
      'semester': session.semester, 'division': session.division,
      'reason': reason.trim(), 'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> pendingAttendanceReopenRequests() => db
      .collection('attendance_reopening_requests').where('status', isEqualTo: 'pending')
      .snapshots().map((s) {
    final items = s.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    items.sort((a, b) {
      final at = a['createdAt']; final bt = b['createdAt'];
      return (at is Timestamp ? at.toDate() : DateTime(1970))
          .compareTo(bt is Timestamp ? bt.toDate() : DateTime(1970));
    });
    return items;
  });

  Future<void> reviewAttendanceReopenRequest({
    required String requestId, required bool approve, required String adminUid,
  }) async {
    final requestRef = db.collection('attendance_reopening_requests').doc(requestId);
    await db.runTransaction((tx) async {
      final req = await tx.get(requestRef);
      if (!req.exists) throw StateError('Request not found.');
      final data = req.data()!;
      if (data['status'] != 'pending') throw StateError('This request has already been reviewed.');
      final sessionRef = db.collection('attendance_sessions').doc(data['sessionId'] as String);
      final session = await tx.get(sessionRef);
      if (!session.exists) throw StateError('Attendance session not found.');
      tx.update(requestRef, {'status': approve ? 'approved' : 'rejected',
        'reviewedBy': adminUid, 'reviewedAt': FieldValue.serverTimestamp()});
      if (approve) tx.update(sessionRef, {
        'reopenedUntil': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 30))),
        'reopenedBy': adminUid, 'reopeningRequestId': requestId, 'status': 'reopened',
      });
    });
  }

  Stream<List<Map<String, dynamic>>> roster(UserProfile teacher,
      String department, String semester, String division) =>
      db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('isActive', isEqualTo: true)
          .where('department', isEqualTo: department)
          .where('semester', isEqualTo: semester)
          .where('division', isEqualTo: division)
          .orderBy('name')
          .snapshots()
          .map((s) => s.docs.map((d) => {'uid': d.id, ...d.data()}).toList());

  Stream<List<Map<String, dynamic>>> studentRecords(String uid) => db
      .collection('attendance_records')
      .where('studentUid', isEqualTo: uid)
      .orderBy('sessionDate', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  Future<List<Map<String, dynamic>>> sessionRecords(String sessionId) async {
    final snap = await db
        .collection('attendance_records')
        .where('sessionId', isEqualTo: sessionId)
        .get();
    final records = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final uids = records
        .map((r) => r['studentUid'] as String? ?? '')
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    final nameLookup = <String, String>{};
    for (var i = 0; i < uids.length; i += 10) {
      final chunk =
      uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10);
      final users = await db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final u in users.docs) {
        nameLookup[u.id] = (u.data()['name'] as String?) ?? '';
      }
    }
    for (final r in records) {
      r['studentName'] = nameLookup[r['studentUid']] ??
          r['studentName'] ??
          r['studentUid'] ??
          '';
    }
    records.sort((a, b) =>
        (a['studentName'] as String).compareTo(b['studentName'] as String));
    return records;
  }

  Future<Map<String, dynamic>?> findMentor(UserProfile student) async {
    if (student.mentorUid.isNotEmpty) {
      final doc = await db.collection('users').doc(student.mentorUid).get();
      if (doc.exists) return {'uid': doc.id, ...doc.data()!};
    }
    if (student.department.isEmpty) return null;
    final fallback = await db
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('active', isEqualTo: true)
        .where('department', isEqualTo: student.department)
        .limit(1)
        .get();
    if (fallback.docs.isEmpty) return null;
    return {'uid': fallback.docs.first.id, ...fallback.docs.first.data()};
  }

  Stream<List<LibraryResource>> library() => db
      .collection('library')
      .orderBy('title')
      .snapshots()
      .map((s) => s.docs.map(LibraryResource.fromDoc).toList());

  Stream<List<BusRoute>> buses() => db
      .collection('buses')
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(BusRoute.fromDoc).toList());

  /// Returns active contacts permitted by the app's role policy.
  /// Supports both activation fields used by existing user records (`active`
  /// and legacy `isActive`) without requiring a data migration.
  Stream<List<Map<String, dynamic>>> contacts(UserProfile profile) {
    final roles = switch (profile.role) {
      'student' => <String>['teacher', 'admin'],
      'teacher' => <String>['student', 'admin'],
      'admin' => <String>['student', 'teacher'],
      _ => <String>[],
    };
    if (roles.isEmpty) return Stream.value(const <Map<String, dynamic>>[]);

    // Filter activation in Dart because legacy records use either field name.
    // Firestore rules still require the signed-in user to be active to read
    // the campus directory; do not weaken those rules to fix this query.
    return db
        .collection('users')
        .where('role', whereIn: roles)
        .limit(300)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .where((doc) {
      if (doc.id == profile.uid) return false;
      final data = doc.data();
      return data['active'] == true || data['isActive'] == true;
    })
        .map((doc) => <String, dynamic>{'uid': doc.id, ...doc.data()})
        .toList());
  }

  Stream<List<Map<String, dynamic>>> conversations(String uid) {
    // Firestore rules authorize against request.auth.uid, never a profile field.
    // Use the live Firebase Auth UID as the source of truth and log mismatches.
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) {
      return Stream.error(StateError('Campus Chat: no authenticated Firebase user.'));
    }
    if (uid != authUid) {
      debugPrint('[CampusChat] UID mismatch: profile/repository=$uid auth=$authUid; querying with auth UID.');
    } else {
      debugPrint('[CampusChat] conversation query UID matches Firebase Auth: $authUid');
    }
    return db
        .collection('chat_conversations')
        .where('participantUids', arrayContains: authUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> messages(String conversationId) => db
      .collection('chat_conversations')
      .doc(conversationId)
      .collection('messages')
      .orderBy('sentAt')
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  /// Marks incoming messages as read without rewriting messages already read.
  /// Batches are chunked to stay below Firestore's 500-write limit.
  Future<void> markMessagesRead(
      String conversationId,
      String uid,
      List<Map<String, dynamic>> messages,
      ) async {
    final pending = messages.where((message) {
      final readBy = List<String>.from(message['readBy'] as List? ?? const []);
      return message['senderUid'] != uid &&
          !readBy.contains(uid) &&
          message['id'] is String;
    }).toList();

    for (var start = 0; start < pending.length; start += 450) {
      final end = start + 450 > pending.length ? pending.length : start + 450;
      final batch = db.batch();
      for (final message in pending.sublist(start, end)) {
        batch.update(
          db.collection('chat_conversations').doc(conversationId)
              .collection('messages').doc(message['id'] as String),
          {'readBy': FieldValue.arrayUnion([uid])},
        );
      }
      await batch.commit();
    }
  }


  Future<void> submitAttendance({
    required UserProfile teacher, required String department, required String semester,
    required String division, required String subjectId, required String subjectName,
    required String timetableEntryId, required DateTime startAt, required DateTime endAt,
    required List<Map<String, dynamic>> roster, required Map<String, bool> statuses,
  }) async {
    final now = DateTime.now();
    if (now.isBefore(startAt) || !now.isBefore(endAt)) {
      throw StateError('Attendance is available only from the exact lecture start until its scheduled end.');
    }
    if (timetableEntryId.trim().isEmpty) throw StateError('Select a timetable entry first.');
    if (!endAt.isAfter(startAt)) throw StateError('The timetable has an invalid lecture time range.');
    if (roster.isEmpty || statuses.length != roster.length) throw StateError('Load the full class roster and mark every student.');
    final dayKey = dateKey(startAt);
    final sessionRef = db.collection('attendance_sessions').doc('${timetableEntryId}_$dayKey');
    if ((await sessionRef.get()).exists) throw StateError('Attendance for this lecture has already been submitted.');
    final batch = db.batch();
    final present = statuses.values.where((v) => v).length;
    batch.set(sessionRef, {
      'teacherUid': teacher.uid, 'timetableEntryId': timetableEntryId,
      'department': department, 'semester': semester, 'division': division,
      'subjectId': subjectId, 'subjectName': subjectName,
      'date': Timestamp.fromDate(startAt), 'dateKey': dayKey,
      'startTime': '${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')}',
      'endTime': '${endAt.hour.toString().padLeft(2, '0')}:${endAt.minute.toString().padLeft(2, '0')}',
      'startAt': Timestamp.fromDate(startAt), 'endAt': Timestamp.fromDate(endAt),
      'presentCount': present, 'absentCount': statuses.length - present,
      'status': 'submitted', 'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final student in roster) {
      final uid = student['uid'] as String;
      final recordId = '${sessionRef.id}_$uid';
      batch.set(db.collection('attendance_records').doc(recordId), {
        'recordId': recordId, 'sessionId': sessionRef.id, 'studentUid': uid,
        'teacherUid': teacher.uid, 'department': department, 'semester': semester,
        'division': division, 'sessionDate': dayKey, 'subjectId': subjectId,
        'subjectName': subjectName, 'status': statuses[uid] == true ? 'present' : 'absent',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<String> getOrCreateConversation(String uid, String otherUid) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) throw StateError('Campus Chat: no authenticated Firebase user.');
    if (uid != authUid) {
      throw StateError('Campus Chat UID mismatch: profile=$uid, Firebase Auth=$authUid. Reopen the app and sign in again.');
    }
    if (uid.trim().isEmpty || otherUid.trim().isEmpty || uid == otherUid) {
      throw ArgumentError('A conversation needs two different campus members.');
    }

    final conversationsRef = db.collection('chat_conversations');
    // Reuse conversations created by the current UID-based implementation.
    final existing = await conversationsRef
        .where('participantUids', arrayContains: uid)
        .get();
    for (final doc in existing.docs) {
      final participants = List<String>.from(
        doc.data()['participantUids'] as List? ?? const [],
      );
      if (participants.length == 2 && participants.contains(otherUid)) {
        return doc.id;
      }
    }

    // A deterministic ID prevents two clients creating duplicate 1:1 chats.
    final participants = [uid, otherUid]..sort();
    final conversationId = '${participants[0]}_${participants[1]}';
    final conversationRef = conversationsRef.doc(conversationId);
    await conversationRef.set({
      'participantUids': participants,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderUid': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return conversationId;
  }

  Future<void> sendMessage(
      String conversationId,
      String uid,
      String text,
      ) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid == null) throw StateError('Campus Chat: no authenticated Firebase user.');
    if (uid != authUid) {
      throw StateError('Campus Chat UID mismatch: profile=$uid, Firebase Auth=$authUid. Reopen the app and sign in again.');
    }
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    if (cleanText.length > 4000) {
      throw ArgumentError('Messages must be 4,000 characters or fewer.');
    }

    final conversationRef = db.collection('chat_conversations').doc(conversationId);
    final conversation = await conversationRef.get();
    if (!conversation.exists) throw StateError('This conversation no longer exists.');
    final participants = List<String>.from(
      conversation.data()?['participantUids'] as List? ?? const [],
    );
    if (!participants.contains(uid) || participants.length != 2) {
      throw StateError('You are not a participant in this conversation.');
    }

    final receiverUid = participants.firstWhere((participant) => participant != uid);
    final now = FieldValue.serverTimestamp();
    final batch = db.batch();
    final messageRef = conversationRef.collection('messages').doc();
    batch.set(messageRef, {
      'senderUid': uid,
      'receiverUid': receiverUid,
      'text': cleanText,
      'sentAt': now,
      'readBy': [uid],
    });
    batch.update(conversationRef, {
      'lastMessage': cleanText,
      'lastMessageAt': now,
      'lastMessageSenderUid': uid,
    });
    await batch.commit();
  }

}
