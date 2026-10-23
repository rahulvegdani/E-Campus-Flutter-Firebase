import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Admin-only setup, generation, review and publication for the weekly timetable.
/// Generation is deterministic and constraint-based; it does not guess missing inputs.
class TimetableAdminScreen extends StatefulWidget {
  const TimetableAdminScreen({super.key});

  @override
  State<TimetableAdminScreen> createState() => _TimetableAdminScreenState();
}

class _TimetableAdminScreenState extends State<TimetableAdminScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _working = false;
  String _message = '';

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('timetable_groups');
  CollectionReference<Map<String, dynamic>> get _requirements =>
      _db.collection('timetable_requirements');
  CollectionReference<Map<String, dynamic>> get _entries =>
      _db.collection('timetable');

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _notice(String text) {
    if (!mounted) return;
    setState(() => _message = text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    if (_working) const LinearProgressIndicator(),
    if (_message.isNotEmpty)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Align(alignment: Alignment.centerLeft, child: Text(_message)),
      ),
    Expanded(
      child: DefaultTabController(
        length: 4,
        child: Column(children: [
          const TabBar(isScrollable: true, tabs: [
            Tab(icon: Icon(Icons.groups_outlined), text: 'Class groups'),
            Tab(icon: Icon(Icons.menu_book_outlined), text: 'Subject needs'),
            Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Draft / publish'),
            Tab(icon: Icon(Icons.edit_calendar_outlined), text: 'Published timetable'),
          ]),
          Expanded(child: TabBarView(children: [
            _groupsTab(),
            _requirementsTab(),
            _draftsTab(),
            _publishedTab(),
          ])),
        ]),
      ),
    ),
  ]);

  Widget _groupsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _groups.orderBy('department').snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error('Could not load class groups. Check Firestore rules.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snapshot.data!.docs;
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Create a class group for a course and semester. Division is optional; create A/B/C as separate groups when needed.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _working ? null : _addGroup,
            icon: const Icon(Icons.add), label: const Text('Create class group')),
        const SizedBox(height: 12),
        if (docs.isEmpty) const _EmptyHint('No class groups yet.'),
        ...docs.map((doc) {
          final d = doc.data();
          final div = (d['division'] as String? ?? '').trim();
          return Card(child: ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text('${d['department'] ?? ''} · Semester ${d['semester'] ?? ''}'),
            subtitle: Text('${d['groupName'] ?? 'Class group'}${div.isEmpty ? ' · All students in this course/semester' : ' · Division $div'}'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete group', onPressed: _working ? null : () => _deleteGroup(doc.id)),
          ));
        }),
      ]);
    },
  );

  Widget _requirementsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _requirements.orderBy('department').snapshots(),
    builder: (context, reqSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groups.orderBy('department').snapshots(),
      builder: (context, groupSnapshot) {
        if (reqSnapshot.hasError || groupSnapshot.hasError) return _error('Could not load timetable setup. Check Firestore rules.');
        if (!reqSnapshot.hasData || !groupSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final groups = groupSnapshot.data!.docs;
        final requirements = reqSnapshot.data!.docs;
        return ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Each requirement states how many lectures a subject needs per week, its duration, assigned teacher and room. The generator schedules these requirements.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: groups.isEmpty || _working ? null : () => _addRequirement(groups),
              icon: const Icon(Icons.add), label: const Text('Add subject requirement')),
          const SizedBox(height: 12),
          if (requirements.isEmpty) const _EmptyHint('No subject requirements yet.'),
          ...requirements.map((doc) {
            final d = doc.data();
            final matchingGroups = groups.where((g) => g.id == d['groupId']);
            final group = matchingGroups.isEmpty ? null : matchingGroups.first.data();
            final division = (group?['division'] as String? ?? '').trim();
            return Card(child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text('${d['subjectName'] ?? 'Subject'} · ${d['weeklySessions'] ?? 0} / week'),
              subtitle: Text('${d['department'] ?? ''} · Sem ${d['semester'] ?? ''}${division.isEmpty ? '' : ' · Div $division'}\n${d['teacherName'] ?? 'Teacher missing'} · ${d['durationMinutes'] ?? '?'} min · Room ${d['room'] ?? 'TBA'}'),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete requirement', onPressed: _working ? null : () => _deleteRequirement(doc.id)),
            ));
          }),
        ]);
      },
    ),
  );

  Widget _draftsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _entries.orderBy('createdAt', descending: true).limit(200).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _error('Could not load timetable entries. Check Firestore rules.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snapshot.data!.docs.where((doc) => (doc.data()['status'] as String? ?? 'published') == 'draft').toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Generate creates a draft only. Review every row, resolve any reported unscheduled requirements, then publish the selected draft batch.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _working ? null : _generateDraft,
            icon: const Icon(Icons.auto_awesome), label: const Text('Generate draft timetable')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _working || docs.isEmpty || docs.any((d) => d.data()['generationComplete'] == false) ? null : () => _publishDrafts(docs),
            icon: const Icon(Icons.publish_outlined), label: Text('Publish ${docs.length} draft entries')),
        const SizedBox(height: 12),
        if (docs.isEmpty) const _EmptyHint('There are no draft entries. Generate a draft after configuring groups and subject needs.'),
        ...docs.map((doc) {
          final d = doc.data();
          return Card(child: ListTile(
            title: Text('${d['subjectName'] ?? 'Subject'} · ${d['dayOfWeek'] ?? ''} ${d['startTime'] ?? ''}–${d['endTime'] ?? ''}'),
            subtitle: Text('${d['department'] ?? ''} · Sem ${d['semester'] ?? ''} · ${((d['division'] as String?) ?? '').isEmpty ? 'Course group' : 'Div ${d['division']}'}\n${d['teacherName'] ?? ''} · Room ${d['room'] ?? 'TBA'}'),
            isThreeLine: true,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit draft lecture', onPressed: _working ? null : () => _editEntry(doc)),
              IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove draft', onPressed: _working ? null : () => _deleteEntry(doc.id)),
            ]),
          ));
        }),
      ]);
    },
  );

  Widget _publishedTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _entries.where('status', isEqualTo: 'published')
        .orderBy('createdAt', descending: true).limit(300).snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _error(
          'Published timetable error: ${snapshot.error}',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final docs = [...snapshot.data!.docs]..sort((a, b) {
        final ad = a.data();
        final bd = b.data();
        final dayOrder = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        final day = dayOrder.indexOf(ad['dayOfWeek'] as String? ?? '')
            .compareTo(dayOrder.indexOf(bd['dayOfWeek'] as String? ?? ''));
        if (day != 0) return day;
        return _minutes(ad['startMinutes'], ad['startTime'] as String? ?? '')
            .compareTo(_minutes(bd['startMinutes'], bd['startTime'] as String? ?? ''));
      });
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Manage the timetable students and teachers can currently see. '
                'Editing a lecture updates the published timetable immediately. '
                'Removing a lecture or subject does not delete attendance records.',
          ),
          const SizedBox(height: 12),
          if (docs.isEmpty)
            const _EmptyHint('There are no published timetable entries yet.'),
          ...docs.map((doc) {
            final d = doc.data();
            final division = (d['division'] as String? ?? '').trim();
            final group = '${d['department'] ?? ''} · Sem ${d['semester'] ?? ''}'
                '${division.isEmpty ? ' · Course group' : ' · Div $division'}';
            return Card(
              child: ListTile(
                isThreeLine: true,
                leading: const Icon(Icons.event_available_outlined),
                title: Text(
                  '${d['subjectName'] ?? 'Subject'} · ${d['dayOfWeek'] ?? ''} '
                      '${d['startTime'] ?? ''}–${d['endTime'] ?? ''}',
                ),
                subtitle: Text(
                  '$group\n${d['teacherName'] ?? 'Teacher'} · Room ${d['room'] ?? 'TBA'}',
                ),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit published lecture',
                      onPressed: _working ? null : () => _editEntry(doc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove this lecture session',
                      onPressed: _working ? null : () => _deletePublishedSession(doc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.playlist_remove_outlined),
                      tooltip: 'Remove this subject from this class timetable',
                      onPressed: _working ? null : () => _deletePublishedSubject(doc),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );
    },
  );

  Widget _error(String text) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)));

  Future<void> _addGroup() async {
    final form = await _showGroupDialog();
    if (form == null) return;
    await _run(() async {
      final dept = form['department']!.trim();
      final sem = form['semester']!.trim();
      final division = form['division']!.trim();
      final existing = await _groups.get();
      if (existing.docs.where((d) => d.data()['department'] == dept && d.data()['semester'] == sem).any((d) => (d.data()['division'] as String? ?? '').trim().toLowerCase() == division.toLowerCase())) {
        throw StateError('A group already exists for this course, semester and division.');
      }
      await _groups.add({
        'department': dept, 'semester': sem, 'division': division,
        'groupName': form['groupName']!.trim(), 'groupType': division.isEmpty ? 'course' : 'division',
        'createdBy': _uid, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      });
      _notice('Class group created.');
    });
  }

  Future<Map<String, String>?> _showGroupDialog() {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ClassGroupDialog(),
    );
  }

  Future<void> _addRequirement(List<QueryDocumentSnapshot<Map<String, dynamic>>> groups) async {
    final teachersSnap = await _db.collection('users').where('role', isEqualTo: 'teacher').get();
    final teachers = teachersSnap.docs.where((d) => (d.data()['isActive'] as bool? ?? d.data()['active'] as bool? ?? false)).map((d) => {'uid': d.id, 'name': d.data()['name'] as String? ?? 'Teacher'}).toList();
    if (teachers.isEmpty) { _notice('Add an active teacher account before adding subject requirements.'); return; }
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => _RequirementDialog(groups: groups, teachers: teachers));
    if (result == null) return;
    await _run(() async {
      final groupId = result['groupId'] as String;
      final groupDoc = groups.firstWhere((g) => g.id == groupId);
      final g = groupDoc.data();
      await _requirements.add({
        ...result,
        'department': g['department'], 'semester': g['semester'], 'division': g['division'] ?? '',
        'createdBy': _uid, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
      });
      _notice('Subject requirement saved.');
    });
  }

  Future<void> _generateDraft() async => _run(() async {
    final groupSnap = await _groups.get();
    final reqSnap = await _requirements.get();
    if (groupSnap.docs.isEmpty || reqSnap.docs.isEmpty) throw StateError('Create at least one class group and one subject requirement first.');
    final groups = {for (final d in groupSnap.docs) d.id: d.data()};
    final requirements = <Map<String, dynamic>>[];
    for (final doc in reqSnap.docs) {
      final r = doc.data();
      final group = groups[r['groupId']];
      if (group == null) continue;
      final sessions = (r['weeklySessions'] as num?)?.toInt() ?? 0;
      final duration = (r['durationMinutes'] as num?)?.toInt() ?? 0;
      if (sessions < 1 || sessions > 10 || duration < 15 || duration > 240 || (r['teacherUid'] as String? ?? '').isEmpty || (r['room'] as String? ?? '').trim().isEmpty) {
        throw StateError('Invalid requirement for ${r['subjectName'] ?? 'a subject'}. Weekly sessions must be 1–10, duration 15–240 minutes, and teacher/room are required.');
      }
      for (var i = 0; i < sessions; i++) requirements.add({...r, 'requirementId': doc.id, 'group': group, 'occurrence': i});
    }
    if (requirements.isEmpty) throw StateError('No valid weekly lecture requirements were found.');

    // Hardest requirements first reduces avoidable dead ends. Longer lectures
    // and teachers with more assigned hours are scheduled before easier ones.
    final teacherLoad = <String, int>{};
    for (final r in requirements) { final t = r['teacherUid'] as String; teacherLoad[t] = (teacherLoad[t] ?? 0) + 1; }
    requirements.sort((a, b) {
      final dur = ((b['durationMinutes'] as num).toInt()).compareTo((a['durationMinutes'] as num).toInt());
      if (dur != 0) return dur;
      return (teacherLoad[b['teacherUid']] ?? 0).compareTo(teacherLoad[a['teacherUid']] ?? 0);
    });

    // A 15-minute search grid allows flexible start/end times. Intervals are
    // half-open [start,end), so a class ending at 10:00 may be followed at 10:00.
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const opening = 8 * 60; const closing = 17 * 60;
    final placed = <Map<String, dynamic>>[]; final unplaced = <String>[];
    // Published and legacy entries are fixed constraints: a new draft must not
    // collide with a schedule that students/teachers can already see.
    final fixedSnapshot = await _entries.get();
    final fixedEntries = <Map<String, dynamic>>[];
    for (final doc in fixedSnapshot.docs) {
      final d = doc.data();
      if (d['status'] == 'draft') continue;
      final start = _minutes(d['startMinutes'], d['startTime'] as String? ?? '');
      final end = _minutes(d['endMinutes'], d['endTime'] as String? ?? '');
      if (end <= start || (d['dayOfWeek'] as String? ?? '').isEmpty) continue;
      fixedEntries.add({...d, '_start': start, '_end': end});
    }
    bool sameClassScope(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aGroup = (a['groupId'] as String? ?? '').trim();
      final bGroup = (b['groupId'] as String? ?? '').trim();
      if (aGroup.isNotEmpty && bGroup.isNotEmpty && aGroup == bGroup) return true;
      if (a['department'] != b['department'] || a['semester'] != b['semester']) return false;
      final aDivision = (a['division'] as String? ?? '').trim();
      final bDivision = (b['division'] as String? ?? '').trim();
      // An un-divided course-level lecture overlaps every division of that course.
      return aDivision.isEmpty || bDivision.isEmpty || aDivision == bDivision;
    }
    bool conflicts(Map<String, dynamic> candidate) {
      final start = candidate['_start'] as int; final end = candidate['_end'] as int;
      for (final old in [...fixedEntries, ...placed]) {
        if (old['dayOfWeek'] != candidate['dayOfWeek']) continue;
        final oldStart = old['_start'] as int; final oldEnd = old['_end'] as int;
        if (start >= oldEnd || oldStart >= end) continue;
        final sameGroup = sameClassScope(old, candidate);
        final sameTeacher = old['teacherUid'] == candidate['teacherUid'];
        final sameRoom = (old['room'] as String? ?? '').trim().toLowerCase() == (candidate['room'] as String).trim().toLowerCase();
        if (sameGroup || sameTeacher || sameRoom) return true;
      }
      return false;
    }
    for (final req in requirements) {
      final duration = (req['durationMinutes'] as num).toInt();
      final g = req['group'] as Map<String, dynamic>;
      final candidates = <Map<String, dynamic>>[];
      for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
        for (var start = opening; start + duration <= closing; start += 15) {
          candidates.add({'dayOfWeek': days[dayIndex], '_start': start, '_end': start + duration, '_dayIndex': dayIndex});
        }
      }
      // Stable distribution preference: use the least-loaded day first, then earlier times.
      candidates.sort((a, b) {
        int dayCount(Map<String, dynamic> x) => placed.where((p) => p['dayOfWeek'] == x['dayOfWeek'] && p['groupId'] == req['groupId']).length;
        final load = dayCount(a).compareTo(dayCount(b)); if (load != 0) return load;
        final day = (a['_dayIndex'] as int).compareTo(b['_dayIndex'] as int); if (day != 0) return day;
        return (a['_start'] as int).compareTo(b['_start'] as int);
      });
      Map<String, dynamic>? selected;
      for (final slot in candidates) {
        final candidate = <String, dynamic>{
          ...slot, 'groupId': req['groupId'], 'department': g['department'], 'semester': g['semester'],
          'division': g['division'] ?? '', 'groupType': g['groupType'] ?? 'division',
          'subjectName': req['subjectName'], 'subjectId': req['subjectId'] ?? req['requirementId'],
          'teacherUid': req['teacherUid'], 'teacherName': req['teacherName'], 'room': req['room'],
        };
        if (!conflicts(candidate)) { selected = candidate; break; }
      }
      if (selected == null) { unplaced.add('${req['subjectName']} (${g['groupName'] ?? g['department']})'); continue; }
      placed.add(selected);
    }

    // Keep existing published entries untouched; replace only unpublished drafts
    // created by this generator. Batch writes are chunked below Firestore's 500 limit.
    final allDrafts = await _entries.where('status', isEqualTo: 'draft').get();
    final oldDrafts = allDrafts.docs.where((doc) => doc.data()['generatorVersion'] == 1).toList();
    for (var i = 0; i < oldDrafts.length; i += 400) {
      final batch = _db.batch();
      for (final doc in oldDrafts.skip(i).take(400)) batch.delete(doc.reference);
      await batch.commit();
    }
    for (var i = 0; i < placed.length; i += 400) {
      final batch = _db.batch();
      for (final p in placed.skip(i).take(400)) {
        final start = p['_start'] as int; final end = p['_end'] as int;
        batch.set(_entries.doc(), {
          'subjectName': p['subjectName'], 'subjectId': p['subjectId'],
          'teacherUid': p['teacherUid'], 'teacherName': p['teacherName'],
          'dayOfWeek': p['dayOfWeek'], 'startTime': _clock(start), 'endTime': _clock(end),
          'startMinutes': start, 'endMinutes': end, 'room': p['room'],
          'department': p['department'], 'semester': p['semester'], 'division': p['division'],
          'groupId': p['groupId'], 'groupType': p['groupType'], 'status': 'draft',
          'generatorVersion': 1, 'generationComplete': unplaced.isEmpty, 'createdBy': _uid, 'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    final resultText = 'Generated ${placed.length} draft lectures.' + (unplaced.isEmpty ? ' All requirements were placed.' : ' Could not place ${unplaced.length}: ${unplaced.take(8).join(', ')}${unplaced.length > 8 ? '…' : ''}. Adjust teacher/room availability, hours, or requirements and regenerate.');
    _notice(resultText);
  });

  Future<void> _editEntry(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final original = doc.data();
    final room = TextEditingController(text: original['room'] as String? ?? '');
    final days = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    String day = days.contains(original['dayOfWeek']) ? original['dayOfWeek'] as String : 'Monday';
    TimeOfDay start = _parseTime(original['startTime'] as String? ?? '') ?? const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end = _parseTime(original['endTime'] as String? ?? '') ?? const TimeOfDay(hour: 9, minute: 0);
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text((original['status'] as String? ?? 'draft') == 'published' ? 'Edit published lecture' : 'Edit draft lecture'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: day, decoration: const InputDecoration(labelText: 'Day'), items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(), onChanged: (v) { if (v != null) setDialog(() => day = v); }),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Start time'), subtitle: Text(start.format(ctx)), trailing: const Icon(Icons.schedule), onTap: () async { final picked = await showTimePicker(context: ctx, initialTime: start); if (picked != null) setDialog(() => start = picked); }),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('End time'), subtitle: Text(end.format(ctx)), trailing: const Icon(Icons.schedule), onTap: () async { final picked = await showTimePicker(context: ctx, initialTime: end); if (picked != null) setDialog(() => end = picked); }),
        TextField(controller: room, decoration: const InputDecoration(labelText: 'Room / lab')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, {'dayOfWeek': day, 'startTime': _timeText(start), 'endTime': _timeText(end), 'room': room.text.trim()}), child: const Text('Save changes'))],
    )));
    room.dispose();
    if (result == null) return;
    await _run(() async {
      final startMinutes = (start.hour * 60) + start.minute;
      final endMinutes = (end.hour * 60) + end.minute;
      if (endMinutes <= startMinutes) throw StateError('End time must be after start time.');
      if (result['room'].toString().trim().isEmpty) throw StateError('Room is required.');
      final all = await _entries.get();
      for (final other in all.docs) {
        if (other.id == doc.id) continue;
        final d = other.data();
        if (d['dayOfWeek'] != result['dayOfWeek']) continue;
        final otherStart = _minutes(d['startMinutes'], d['startTime'] as String? ?? '');
        final otherEnd = _minutes(d['endMinutes'], d['endTime'] as String? ?? '');
        if (startMinutes >= otherEnd || otherStart >= endMinutes) continue;
        final idsMatch = (d['groupId'] as String? ?? '').isNotEmpty && d['groupId'] == original['groupId'];
        final sameCourse = d['department'] == original['department'] && d['semester'] == original['semester'];
        final otherDivision = (d['division'] as String? ?? '').trim();
        final thisDivision = (original['division'] as String? ?? '').trim();
        final sameGroup = idsMatch || (sameCourse && (otherDivision.isEmpty || thisDivision.isEmpty || otherDivision == thisDivision));
        final sameTeacher = d['teacherUid'] == original['teacherUid'];
        final sameRoom = (d['room'] as String? ?? '').trim().toLowerCase() == (result['room'] as String).trim().toLowerCase();
        if (sameGroup) throw StateError('This class group already has a lecture at that time.');
        if (sameTeacher) throw StateError('This teacher is already assigned at that time.');
        if (sameRoom) throw StateError('This room is already booked at that time.');
      }
      await doc.reference.update({...result, 'startMinutes': startMinutes, 'endMinutes': endMinutes, 'updatedAt': FieldValue.serverTimestamp(), 'updatedBy': _uid});
      _notice((original['status'] as String? ?? 'draft') == 'published' ? 'Published lecture updated. Changes are now visible.' : 'Draft lecture updated.');
    });
  }

  TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]); final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }
  String _timeText(TimeOfDay value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  int _minutes(Object? stored, String text) {
    if (stored is num) return stored.toInt();
    final parsed = _parseTime(text);
    return parsed == null ? 0 : parsed.hour * 60 + parsed.minute;
  }

  Future<void> _publishDrafts(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async => _run(() async {
    // Publish only after the administrator explicitly presses this action.
    for (var i = 0; i < docs.length; i += 400) {
      final batch = _db.batch();
      for (final doc in docs.skip(i).take(400)) batch.update(doc.reference, {'status': 'published', 'publishedBy': _uid, 'publishedAt': FieldValue.serverTimestamp()});
      await batch.commit();
    }
    _notice('Published ${docs.length} timetable entries.');
  });

  Future<void> _deletePublishedSession(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data();
    final title = '${d['subjectName'] ?? 'Lecture'} · ${d['dayOfWeek'] ?? ''} '
        '${d['startTime'] ?? ''}–${d['endTime'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove lecture session?'),
        content: Text(
          'Remove "$title" from the published timetable? '
              'Attendance records already saved for this lecture will be kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove session')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await doc.reference.delete();
      _notice('Lecture session removed from the published timetable.');
    });
  }

  Future<void> _deletePublishedSubject(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final selected = doc.data();
    final subject = (selected['subjectName'] as String? ?? 'Subject').trim();
    final groupId = (selected['groupId'] as String? ?? '').trim();
    final subjectId = (selected['subjectId'] as String? ?? '').trim();
    final division = (selected['division'] as String? ?? '').trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove subject from timetable?'),
        content: Text(
          'Remove every published lecture session for "$subject" from '
              '${selected['department'] ?? ''}, semester ${selected['semester'] ?? ''}'
              '${division.isEmpty ? '' : ', division $division'}? '
              'This will not delete the subject requirement or existing attendance records.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove subject')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final all = await _entries.where('status', isEqualTo: 'published').get();
      final matches = all.docs.where((candidate) {
        final d = candidate.data();
        final sameSubject = subjectId.isNotEmpty
            ? (d['subjectId'] as String? ?? '').trim() == subjectId
            : (d['subjectName'] as String? ?? '').trim() == subject;
        if (!sameSubject) return false;
        if (groupId.isNotEmpty && (d['groupId'] as String? ?? '').trim().isNotEmpty) {
          return (d['groupId'] as String? ?? '').trim() == groupId;
        }
        return d['department'] == selected['department'] &&
            d['semester'] == selected['semester'] &&
            (d['division'] as String? ?? '').trim() == division;
      }).toList();
      if (matches.isEmpty) {
        throw StateError('No matching published sessions were found.');
      }
      for (var i = 0; i < matches.length; i += 400) {
        final batch = _db.batch();
        for (final item in matches.skip(i).take(400)) {
          batch.delete(item.reference);
        }
        await batch.commit();
      }
      _notice('Removed $subject and ${matches.length} published session(s) from this class timetable.');
    });
  }

  Future<void> _deleteGroup(String id) async => _confirmDelete('Delete this class group?', () => _groups.doc(id).delete());
  Future<void> _deleteRequirement(String id) async => _confirmDelete('Delete this subject requirement?', () => _requirements.doc(id).delete());
  Future<void> _deleteEntry(String id) async => _confirmDelete('Delete this draft entry?', () => _entries.doc(id).delete());
  Future<void> _confirmDelete(String title, Future<void> Function() action) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: const Text('This action cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
    if (ok == true) await _run(action);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() { _working = true; _message = ''; });
    try { await action(); } catch (e) { _notice(e.toString().replaceFirst('Bad state: ', '')); }
    if (mounted) setState(() => _working = false);
  }

  String _clock(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
}

class _RequirementDialog extends StatefulWidget {
  const _RequirementDialog({required this.groups, required this.teachers});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> groups;
  final List<Map<String, String>> teachers;
  @override
  State<_RequirementDialog> createState() => _RequirementDialogState();
}

class _RequirementDialogState extends State<_RequirementDialog> {
  final _subject = TextEditingController(); final _room = TextEditingController(text: 'Room 101');
  final _sessions = TextEditingController(text: '3'); final _duration = TextEditingController(text: '60');
  String? _groupId; String? _teacherUid;
  final _formKey = GlobalKey<FormState>();
  @override
  void initState() { super.initState(); _groupId = widget.groups.first.id; _teacherUid = widget.teachers.first['uid']; }
  @override
  void dispose() { _subject.dispose(); _room.dispose(); _sessions.dispose(); _duration.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Subject weekly requirement'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(value: _groupId, isExpanded: true, decoration: const InputDecoration(labelText: 'Class group'), items: widget.groups.map((g) { final d = g.data(); final div = (d['division'] as String? ?? '').trim(); return DropdownMenuItem(value: g.id, child: Text('${d['groupName'] ?? d['department']} · Sem ${d['semester']}${div.isEmpty ? '' : ' · $div'}', overflow: TextOverflow.ellipsis)); }).toList(), onChanged: (v) => setState(() => _groupId = v)),
      TextFormField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject name *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      DropdownButtonFormField<String>(value: _teacherUid, isExpanded: true, decoration: const InputDecoration(labelText: 'Assigned teacher'), items: widget.teachers.map((t) => DropdownMenuItem(value: t['uid'], child: Text(t['name'] ?? 'Teacher'))).toList(), onChanged: (v) => setState(() => _teacherUid = v)),
      TextFormField(controller: _sessions, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Lectures per week (1–10)'), validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 1 || n > 10 ? 'Enter 1–10' : null; }),
      TextFormField(controller: _duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Lecture duration in minutes (15–240)'), validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 15 || n > 240 ? 'Enter 15–240' : null; }),
      TextFormField(controller: _room, decoration: const InputDecoration(labelText: 'Room / lab *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { if (!_formKey.currentState!.validate() || _groupId == null || _teacherUid == null) return; final teacher = widget.teachers.firstWhere((t) => t['uid'] == _teacherUid); Navigator.pop(context, {'groupId': _groupId, 'subjectName': _subject.text.trim(), 'subjectId': _subject.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'), 'teacherUid': _teacherUid, 'teacherName': teacher['name'], 'weeklySessions': int.parse(_sessions.text), 'durationMinutes': int.parse(_duration.text), 'room': _room.text.trim()}); }, child: const Text('Save requirement'))],
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text); final String text;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20), child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium));
}


/// Owns its controllers for the lifetime of the dialog route. This avoids
/// disposing text controllers immediately while the dialog is transitioning out.
class _ClassGroupDialog extends StatefulWidget {
  const _ClassGroupDialog();

  @override
  State<_ClassGroupDialog> createState() => _ClassGroupDialogState();
}

class _ClassGroupDialogState extends State<_ClassGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _department = TextEditingController();
  final _semester = TextEditingController();
  final _division = TextEditingController();
  final _groupName = TextEditingController();

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(<String, String>{
      'department': _department.text.trim(),
      'semester': _semester.text.trim(),
      'division': _division.text.trim(),
      'groupName': _groupName.text.trim(),
    });
  }

  @override
  void dispose() {
    _department.dispose();
    _semester.dispose();
    _division.dispose();
    _groupName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create class group'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _department,
                decoration: const InputDecoration(
                  labelText: 'Course / department *',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _semester,
                decoration: const InputDecoration(labelText: 'Semester *'),
                validator: _required,
              ),
              TextFormField(
                controller: _groupName,
                decoration: const InputDecoration(
                  labelText: 'Group label *',
                  hintText: 'MCA Sem 1 / MCA Sem 1 - A',
                ),
                validator: _required,
              ),
              TextFormField(
                controller: _division,
                decoration: const InputDecoration(
                  labelText: 'Division (optional)',
                  hintText: 'Leave empty if no divisions',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
