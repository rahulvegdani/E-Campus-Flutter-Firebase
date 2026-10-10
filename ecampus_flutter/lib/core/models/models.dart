import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? readDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class UserProfile {
  const UserProfile({required this.uid, required this.name, required this.phone, required this.role, required this.active, this.email = '', this.department = '', this.semester = '', this.division = '', this.photoUrl = '', this.mentorUid = ''});
  final String uid, name, phone, role, email, department, semester, division, photoUrl, mentorUid;
  final bool active;
  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) => UserProfile(uid: uid, name: data['name'] as String? ?? 'Campus member', phone: data['phone'] as String? ?? '', role: data['role'] as String? ?? 'student', active: data['active'] as bool? ?? false, email: data['email'] as String? ?? '', department: data['department'] as String? ?? '', semester: data['semester'] as String? ?? '', division: data['division'] as String? ?? '', photoUrl: data['photoUrl'] as String? ?? '', mentorUid: data['mentorUid'] as String? ?? '');
}

class Notice {
  const Notice({required this.id, required this.title, required this.description, required this.authorName, required this.publishedAt, this.category = 'General', this.published = true});
  final String id, title, description, authorName, category;
  final DateTime? publishedAt;
  final bool published;
  factory Notice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) { final d = doc.data() ?? {}; return Notice(id: doc.id, title: d['title'] as String? ?? '', description: d['description'] as String? ?? '', authorName: d['authorName'] as String? ?? 'E-Campus', publishedAt: readDate(d['publishedAt']), category: d['category'] as String? ?? 'General', published: d['published'] as bool? ?? false); }
}

class TimetableEntry {
  const TimetableEntry({required this.id, required this.subject, required this.teacherName, required this.teacherUid, required this.dayOfWeek, required this.startTime, required this.endTime, required this.room, this.subjectId = '', this.department = '', this.semester = '', this.division = ''});
  final String id, subject, teacherName, teacherUid, dayOfWeek, startTime, endTime, room, subjectId, department, semester, division;
  factory TimetableEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) { final d = doc.data() ?? {}; return TimetableEntry(id: doc.id, subject: d['subjectName'] as String? ?? 'Class', teacherName: d['teacherName'] as String? ?? 'Faculty', teacherUid: d['teacherUid'] as String? ?? '', dayOfWeek: d['dayOfWeek'] as String? ?? 'Monday', startTime: d['startTime'] as String? ?? '', endTime: d['endTime'] as String? ?? '', room: d['room'] as String? ?? 'TBA', subjectId: d['subjectId'] as String? ?? '', department: d['department'] as String? ?? '', semester: d['semester'] as String? ?? '', division: d['division'] as String? ?? ''); }
}

class AttendanceSession {
  const AttendanceSession({required this.id, required this.subjectName, required this.date, required this.presentCount, required this.absentCount, required this.department, required this.semester, required this.division, this.startTime = '', this.endTime = ''});
  final String id, subjectName, department, semester, division, startTime, endTime;
  final DateTime? date;
  final int presentCount, absentCount;
  double get percentage => presentCount + absentCount == 0 ? 0 : presentCount * 100 / (presentCount + absentCount);
  factory AttendanceSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) { final d = doc.data() ?? {}; return AttendanceSession(id: doc.id, subjectName: d['subjectName'] as String? ?? 'Subject', date: readDate(d['date']), presentCount: d['presentCount'] as int? ?? 0, absentCount: d['absentCount'] as int? ?? 0, department: d['department'] as String? ?? '', semester: d['semester'] as String? ?? '', division: d['division'] as String? ?? '', startTime: d['startTime'] as String? ?? '', endTime: d['endTime'] as String? ?? ''); }
}

class LibraryResource { const LibraryResource({required this.id, required this.title, required this.description, required this.category, required this.url}); final String id, title, description, category, url; factory LibraryResource.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) { final d = doc.data() ?? {}; return LibraryResource(id: doc.id, title: d['title'] as String? ?? '', description: d['description'] as String? ?? '', category: d['category'] as String? ?? 'Notes', url: d['downloadUrl'] as String? ?? ''); } }
class BusRoute { const BusRoute({required this.id, required this.name, required this.stops, required this.schedule, this.lastUpdated}); final String id, name, stops, schedule; final DateTime? lastUpdated; factory BusRoute.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) { final d = doc.data() ?? {}; return BusRoute(id: doc.id, name: d['name'] as String? ?? 'Campus route', stops: d['stops'] as String? ?? 'Stops not published', schedule: d['schedule'] as String? ?? 'Schedule unavailable', lastUpdated: readDate(d['lastUpdated'])); } }