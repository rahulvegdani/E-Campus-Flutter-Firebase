import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import 'admin_screen.dart';
import 'attendance_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfx/pdfx.dart';

export 'attendance_chart.dart';

// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key, required this.profile});
  final UserProfile profile;

  static const List<String> _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  static String _normaliseDay(String value) {
    final day = value.trim().toLowerCase();
    for (final full in _days) {
      if (full.toLowerCase() == day ||
          full.toLowerCase().startsWith(day) ||
          day.startsWith(full.toLowerCase().substring(0, 3))) {
        return full;
      }
    }
    return value;
  }

  static int _timeMinutes(String value) {
    final text = value.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(text);
    if (match == null) return 0;
    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final meridiem = match.group(3);
    if (meridiem == 'PM' && hour < 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(dataRepositoryProvider);
    final role = profile.role.toLowerCase();
    final Stream<List<TimetableEntry>> timetableStream = role == 'teacher'
        ? repo.teacherTimetable(profile.uid)
        : role == 'admin'
        ? repo.adminTimetable()
        : repo.timetable(profile);

    return _Page(
      title: 'Schedule',
      child: StreamBuilder<List<TimetableEntry>>(
        stream: timetableStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _StateCard(text: 'Could not load timetable.');
          }
          if (!snapshot.hasData) return const _Loading();

          final entries = [...snapshot.data!]..sort((a, b) {
            final dayCompare = _days.indexOf(_normaliseDay(a.dayOfWeek))
                .compareTo(_days.indexOf(_normaliseDay(b.dayOfWeek)));
            if (dayCompare != 0) return dayCompare;
            return _timeMinutes(a.startTime).compareTo(_timeMinutes(b.startTime));
          });

          if (entries.isEmpty) {
            return _StateCard(
              text: role == 'admin'
                  ? 'No published timetable entries yet.'
                  : role == 'teacher'
                  ? 'No published classes are assigned to you.'
                  : 'No classes scheduled for your current class.',
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.brandTertiary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.calendar_month_outlined,
                              color: AppColors.brand),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                role == 'admin'
                                    ? 'Published weekly timetable'
                                    : role == 'teacher'
                                    ? 'My teaching timetable'
                                    : 'My class timetable',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${entries.length} classes · arranged by day and start time',
                                style: const TextStyle(
                                    color: AppColors.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStatePropertyAll(
                        AppColors.brandTertiary,
                      ),
                      columnSpacing: 22,
                      horizontalMargin: 16,
                      dataRowMinHeight: 58,
                      dataRowMaxHeight: 84,
                      columns: [
                        const DataColumn(label: Text('DAY')),
                        const DataColumn(label: Text('TIME')),
                        const DataColumn(label: Text('SUBJECT')),
                        if (role != 'teacher')
                          const DataColumn(label: Text('TEACHER')),
                        const DataColumn(label: Text('ROOM')),
                        if (role != 'student')
                          const DataColumn(label: Text('CLASS')),
                      ],
                      rows: entries.map((item) {
                        final className = [
                          item.department,
                          if (item.semester.isNotEmpty) 'Sem ${item.semester}',
                          if (item.division.isNotEmpty) 'Div ${item.division}',
                        ].join(' · ');
                        return DataRow(
                          cells: [
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.brandTertiary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _normaliseDay(item.dayOfWeek),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 112,
                                child: Text(
                                  '${item.startTime}\n– ${item.endTime}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 180,
                                child: Text(item.subject,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                            if (role != 'teacher')
                              DataCell(SizedBox(
                                width: 145,
                                child: Text(item.teacherName.isEmpty
                                    ? 'Not assigned'
                                    : item.teacherName),
                              )),
                            DataCell(Text(item.room.isEmpty
                                ? 'Not specified'
                                : item.room)),
                            if (role != 'student')
                              DataCell(SizedBox(
                                width: 150,
                                child: Text(className.isEmpty
                                    ? 'Class not specified'
                                    : className),
                              )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.swipe_outlined,
                        size: 16, color: AppColors.muted),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'On a phone, swipe the table horizontally to see all columns.',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Teacher / Admin attendance
// ---------------------------------------------------------------------------

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  final _deptCtrl = TextEditingController();
  final _semCtrl = TextEditingController();
  final _divCtrl = TextEditingController();
  final _subjCtrl = TextEditingController();
  String _subjectId = '';
  TimetableEntry? _selectedEntry;
  Map<String, bool> statuses = {};
  List<Map<String, dynamic>> roster = [];
  bool busy = false;

  @override
  void dispose() {
    _deptCtrl.dispose();
    _semCtrl.dispose();
    _divCtrl.dispose();
    _subjCtrl.dispose();
    super.dispose();
  }

  void _applyTimetableEntry(TimetableEntry entry) {
    setState(() {
      _selectedEntry = entry;
      _deptCtrl.text = entry.department;
      _semCtrl.text = entry.semester;
      _divCtrl.text = entry.division;
      _subjCtrl.text = entry.subject;
      _subjectId = entry.subjectId.isNotEmpty
          ? entry.subjectId
          : entry.subject.toLowerCase().replaceAll(' ', '_');
      roster = [];
      statuses = {};
    });
    _toast('Prefilled from timetable. Load the roster to continue.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(dataRepositoryProvider);
    return _Page(
      title: 'Attendance',
      actions: [
        IconButton(
          onPressed: () => _showNoticeComposer(context),
          icon: const Icon(Icons.campaign_outlined),
        ),
      ],
      child: ListView(
        children: [
          StreamBuilder<List<AttendanceSession>>(
            stream: repo.teacherSessions(widget.profile.uid),
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? const <AttendanceSession>[];
              return WeeklyAttendanceTrend(sessions: sessions);
            },
          ),
          const SizedBox(height: 24),
          StreamBuilder<List<TimetableEntry>>(
            stream: repo.teacherTimetable(widget.profile.uid),
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const <TimetableEntry>[];
              if (entries.isEmpty) return const SizedBox.shrink();
              return _TimetablePrefillCard(
                entries: entries,
                onApply: _applyTimetableEntry,
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Start a verified lecture session',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick an assigned class below, load its active roster, and submit one auditable session.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          _controllerField(_deptCtrl, 'Department'),
          _controllerField(_semCtrl, 'Semester'),
          _controllerField(_divCtrl, 'Division'),
          _controllerField(_subjCtrl, 'Subject ID / name'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : _loadRoster,
            icon: const Icon(Icons.people_outline),
            label: const Text('Load active roster'),
          ),
          if (roster.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${roster.length} students',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    statuses = {
                      for (final student in roster)
                        student['uid'] as String: true
                    };
                  }),
                  child: const Text('Mark all present'),
                ),
              ],
            ),
            ...roster.map((student) {
              final uid = student['uid'] as String;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: SwitchListTile(
                  value: statuses[uid] ?? false,
                  onChanged: (value) => setState(() => statuses[uid] = value),
                  title: Text(student['name'] as String? ?? 'Student'),
                  subtitle: Text(student['phone'] as String? ?? uid),
                ),
              );
            }),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
              busy || statuses.length != roster.length ? null : _submit,
              child: const Text('Submit attendance'),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Recent sessions',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AttendanceSession>>(
            stream: repo.teacherSessions(widget.profile.uid),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const _Loading();
              if (snapshot.data!.isEmpty) {
                return const _StateCard(
                    text: 'No attendance sessions submitted yet.');
              }
              return Column(
                children: snapshot.data!.take(10).map((session) {
                  return Card(
                    child: ListTile(
                      title: Text(session.subjectName),
                      subtitle: Text(
                        '${session.department} ${session.semester}-${session.division} · '
                            '${session.date == null ? 'Date pending' : DateFormat.yMMMd().format(session.date!)}',
                      ),
                      trailing:
                      Text('${session.percentage.toStringAsFixed(0)}%'),
                      onTap: () => _showSessionSheet(context, session),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _controllerField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.tune_outlined),
        ),
      ),
    );
  }

  Future<void> _loadRoster() async {
    final department = _deptCtrl.text.trim();
    final semester = _semCtrl.text.trim();
    final division = _divCtrl.text.trim();
    final subject = _subjCtrl.text.trim();
    if ([department, semester, division, subject].any((e) => e.isEmpty)) {
      _toast('Complete all class fields first.');
      return;
    }
    setState(() => busy = true);
    try {
      final stream = ref.read(dataRepositoryProvider).roster(
        widget.profile,
        department,
        semester,
        division,
      );
      final result = await stream.first;
      setState(() {
        roster = result;
        statuses = {};
        busy = false;
      });
      if (result.isEmpty) _toast('No active students found for this class.');
    } catch (e) {
      setState(() => busy = false);
      _toast('Roster could not be loaded: $e');
    }
  }

  DateTime _lectureDateTime(TimetableEntry entry, String time) {
    final parts = time.split(':');
    if (parts.length != 2) throw StateError('Invalid timetable time: $time');
    final days = const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final target = days.indexOf(entry.dayOfWeek);
    if (target < 0) throw StateError('Invalid timetable day: ${entry.dayOfWeek}');
    final now = DateTime.now();
    final ahead = (target - (now.weekday - 1) + 7) % 7;
    final date = DateTime(now.year, now.month, now.day).add(Duration(days: ahead));
    return DateTime(date.year, date.month, date.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  Future<void> _submit() async {
    final entry = _selectedEntry;
    if (entry == null) { _toast('Select your assigned lecture from the timetable first.'); return; }
    if (_deptCtrl.text.trim() != entry.department || _semCtrl.text.trim() != entry.semester ||
        _divCtrl.text.trim() != entry.division || _subjCtrl.text.trim() != entry.subject) {
      _toast('Class details must match the selected timetable entry.'); return;
    }
    late final DateTime startAt;
    late final DateTime endAt;
    try {
      startAt = _lectureDateTime(entry, entry.startTime);
      endAt = _lectureDateTime(entry, entry.endTime);
    } catch (e) { _toast('$e'); return; }
    final now = DateTime.now();
    if (now.isBefore(startAt) || !now.isBefore(endAt)) {
      _toast('Attendance opens at ${entry.startTime} and closes at ${entry.endTime} on ${entry.dayOfWeek}.');
      return;
    }
    setState(() => busy = true);
    try {
      final subject = _subjCtrl.text.trim();
      final subjectId = _subjectId.isNotEmpty
          ? _subjectId
          : subject.toLowerCase().replaceAll(' ', '_');
      await ref.read(dataRepositoryProvider).submitAttendance(
        teacher: widget.profile,
        department: _deptCtrl.text.trim(),
        semester: _semCtrl.text.trim(),
        division: _divCtrl.text.trim(),
        subjectId: subjectId,
        subjectName: subject,
        timetableEntryId: entry.id,
        startAt: startAt,
        endAt: endAt,
        roster: roster,
        statuses: statuses,
      );
      if (mounted) {
        setState(() {
          busy = false;
          roster = [];
          statuses = {};
        });
        _toast('Attendance submitted with an audit-safe session ID.');
      }
    } catch (e) {
      setState(() => busy = false);
      _toast('Submission failed: $e');
    }
  }

  Future<void> _showNoticeComposer(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NoticeComposerDialog(author: widget.profile),
    );
  }

  void _toast(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSessionSheet(
      BuildContext context, AttendanceSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) =>
          _SessionDetailSheet(session: session, teacher: widget.profile),
    );
  }
}

class _SessionDetailSheet extends ConsumerStatefulWidget {
  const _SessionDetailSheet({required this.session, required this.teacher});
  final AttendanceSession session;
  final UserProfile teacher;

  @override
  ConsumerState<_SessionDetailSheet> createState() =>
      _SessionDetailSheetState();
}

class _SessionDetailSheetState extends ConsumerState<_SessionDetailSheet> {
  List<Map<String, dynamic>>? _records;
  bool _loading = true;
  String? _error;
  bool _editing = false;
  bool _saving = false;
  final Map<String, bool> _draft = {}; // recordId -> isPresent after edit

  bool get _canEdit => widget.session.teacherUid == widget.teacher.uid;
  bool get _lectureEnded {
    final start = widget.session.date; final parts = widget.session.endTime.split(':');
    if (start == null || parts.length != 2) return false;
    final end = DateTime(start.year, start.month, start.day,
        int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
    return !DateTime.now().isBefore(end);
  }
  bool get _windowOpen {
    final start = widget.session.date; final endParts = widget.session.endTime.split(':');
    if (start == null || endParts.length != 2) return false;
    final end = DateTime(start.year, start.month, start.day,
        int.tryParse(endParts[0]) ?? 0, int.tryParse(endParts[1]) ?? 0);
    final startParts = widget.session.startTime.split(':');
    final lectureStart = startParts.length == 2
        ? DateTime(start.year, start.month, start.day,
        int.tryParse(startParts[0]) ?? 0, int.tryParse(startParts[1]) ?? 0)
        : start;
    final reopened = widget.session.reopenedUntil;
    return (!DateTime.now().isBefore(lectureStart) && DateTime.now().isBefore(end)) ||
        (reopened != null && DateTime.now().isBefore(reopened));
  }
  bool get _hasChanges => _draft.entries.any((e) {
    final record =
    _records!.firstWhere((r) => r['id'] == e.key, orElse: () => {});
    final original = record['status'] == 'present';
    return original != e.value;
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(dataRepositoryProvider)
          .sessionRecords(widget.session.id);
      if (!mounted) return;
      setState(() {
        _records = data;
        _draft
          ..clear()
          ..addEntries(data.map(
                  (r) => MapEntry(r['id'] as String, r['status'] == 'present')));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _requestReopen() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request attendance reopening'),
        content: TextField(controller: reason, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Reason for reopening',
                hintText: 'Explain why attendance needs correction')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Submit request')),
        ],
      ),
    );
    if (confirmed != true) { reason.dispose(); return; }
    try {
      await ref.read(dataRepositoryProvider).requestAttendanceReopen(
          session: widget.session, teacher: widget.teacher, reason: reason.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reopening request sent to the administrator.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request failed: $e')));
    } finally { reason.dispose(); }
  }

  Future<void> _saveChanges() async {
    if (_saving || !_hasChanges) return;
    setState(() => _saving = true);
    final repo = ref.read(dataRepositoryProvider);
    final changed = <Map<String, dynamic>>[];
    for (final r in _records!) {
      final id = r['id'] as String;
      final newIsPresent = _draft[id] ?? (r['status'] == 'present');
      final originalIsPresent = r['status'] == 'present';
      if (newIsPresent != originalIsPresent) changed.add(r);
    }
    try {
      for (final r in changed) {
        final id = r['id'] as String;
        final from = r['status'] as String? ?? 'absent';
        final to = (_draft[id] ?? false) ? 'present' : 'absent';
        await repo.updateAttendanceRecord(
          recordId: id,
          newStatus: to,
          fromStatus: from,
          teacherUid: widget.teacher.uid,
        );
        r['status'] = to;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${changed.length} record${changed.length == 1 ? '' : 's'} updated. Audit trail saved.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  String _escapeCsv(String value) {
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  String _buildCsv(List<Map<String, dynamic>> records) {
    final s = widget.session;
    final dateString =
    s.date == null ? '' : s.date!.toIso8601String().substring(0, 10);
    final buffer = StringBuffer(
      'Student Name,Phone,Status,Session Date,Subject,Department,Semester,Division\n',
    );
    for (final r in records) {
      final row = [
        _escapeCsv((r['studentName'] as String?) ?? ''),
        _escapeCsv((r['studentPhone'] as String?) ?? ''),
        _escapeCsv(((r['status'] as String?) ?? '').toUpperCase()),
        _escapeCsv(dateString),
        _escapeCsv(s.subjectName),
        _escapeCsv(s.department),
        _escapeCsv(s.semester),
        _escapeCsv(s.division),
      ].join(',');
      buffer.writeln(row);
    }
    return buffer.toString();
  }

  Future<void> _copyCsv() async {
    if (_records == null || _records!.isEmpty) return;
    final csv = _buildCsv(_records!);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Session CSV copied. Paste into Excel, Numbers, or Sheets.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding:
        EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + insets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.subjectName,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${s.department} · Sem ${s.semester} · Div ${s.division}',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13),
                      ),
                      if (s.date != null)
                        Text(
                          DateFormat.yMMMd().format(s.date!),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 13),
                        ),
                    ],
                  ),
                ),
                if (_canEdit && !_windowOpen && _lectureEnded)
                  TextButton.icon(
                    onPressed: _saving ? null : _requestReopen,
                    icon: const Icon(Icons.lock_open_outlined, size: 18),
                    label: const Text('Request reopening'),
                  ),
                if (_canEdit &&
                    _windowOpen &&
                    !_loading &&
                    _error == null &&
                    (_records ?? const []).isNotEmpty)
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _editing = !_editing),
                    icon: Icon(
                        _editing
                            ? Icons.lock_open_outlined
                            : Icons.edit_outlined,
                        size: 18),
                    label: Text(_editing ? 'Cancel' : 'Edit'),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _SessionStat(
                  label: 'Present',
                  value: s.presentCount.toString(),
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                _SessionStat(
                  label: 'Absent',
                  value: s.absentCount.toString(),
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                _SessionStat(
                  label: 'Rate',
                  value: '${s.percentage.toStringAsFixed(0)}%',
                  color: AppColors.brand,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Could not load records: $_error',
                  style: const TextStyle(color: AppColors.error),
                ),
              )
            else if ((_records ?? const []).isEmpty)
                const _StateCard(text: 'No records found for this session.')
              else ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _records!.length,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (_, i) {
                        final r = _records![i];
                        final id = r['id'] as String;
                        final originalIsPresent = r['status'] == 'present';
                        final draftIsPresent = _draft[id] ?? originalIsPresent;
                        final editsCount = (r['editCount'] as int?) ?? 0;
                        final name = (r['studentName'] as String?) ?? 'Student';
                        if (_editing) {
                          final isDirty = draftIsPresent != originalIsPresent;
                          return SwitchListTile(
                            dense: true,
                            value: draftIsPresent,
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _draft[id] = value),
                            title: Text(name),
                            subtitle: Text(
                              isDirty
                                  ? 'Changing to ${draftIsPresent ? "present" : "absent"}'
                                  : editsCount > 0
                                  ? 'Previously edited $editsCount time${editsCount == 1 ? '' : 's'}'
                                  : '',
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                isDirty ? AppColors.warning : AppColors.muted,
                              ),
                            ),
                          );
                        }
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            originalIsPresent
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                            color: originalIsPresent
                                ? AppColors.success
                                : AppColors.error,
                            size: 20,
                          ),
                          title: Text(name),
                          subtitle: editsCount > 0
                              ? Text(
                            'Edited $editsCount time${editsCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted),
                          )
                              : null,
                          trailing: Text(
                            ((r['status'] as String?) ?? '').toUpperCase(),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_editing) ...[
                    FilledButton.icon(
                      onPressed: _hasChanges && !_saving ? _saveChanges : null,
                      icon: _saving
                          ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Every edit is logged with your UID, timestamp, and before→after values on the attendance_records document.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _copyCsv,
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Copy CSV'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'CSV columns: Student Name, Phone, Status, Session Date, Subject, Department, Semester, Division.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ],
          ],
        ),
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  const _SessionStat(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: color),
            ),
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _TimetablePrefillCard extends StatefulWidget {
  const _TimetablePrefillCard({required this.entries, required this.onApply});

  final List<TimetableEntry> entries;
  final void Function(TimetableEntry) onApply;

  @override
  State<_TimetablePrefillCard> createState() => _TimetablePrefillCardState();
}

class _TimetablePrefillCardState extends State<_TimetablePrefillCard> {
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String _filterBy = 'day';
  String? _selectedDay;
  String? _selectedSubject;
  String? _selectedEntryId;

  String _normaliseDay(String value) {
    final day = value.trim().toLowerCase();
    for (final full in _days) {
      if (full.toLowerCase() == day ||
          full.toLowerCase().startsWith(day) ||
          day.startsWith(full.toLowerCase().substring(0, 3))) {
        return full;
      }
    }
    return value.trim();
  }

  int _timeMinutes(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return 0;
    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final meridiem = match.group(3)?.toUpperCase();
    if (meridiem == 'PM' && hour < 12) hour += 12;
    if (meridiem == 'AM' && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  List<TimetableEntry> get _sortedEntries {
    final result = [...widget.entries];
    result.sort((a, b) {
      final aDay = _days.indexOf(_normaliseDay(a.dayOfWeek));
      final bDay = _days.indexOf(_normaliseDay(b.dayOfWeek));
      final dayCompare = (aDay < 0 ? 99 : aDay)
          .compareTo(bDay < 0 ? 99 : bDay);
      if (dayCompare != 0) return dayCompare;
      final timeCompare = _timeMinutes(a.startTime)
          .compareTo(_timeMinutes(b.startTime));
      if (timeCompare != 0) return timeCompare;
      return a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
    });
    return result;
  }

  List<String> get _availableDays {
    final values = widget.entries
        .map((e) => _normaliseDay(e.dayOfWeek))
        .toSet()
        .toList();
    values.sort((a, b) {
      final ai = _days.indexOf(a);
      final bi = _days.indexOf(b);
      return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
    });
    return values;
  }

  List<String> get _availableSubjects {
    final values = widget.entries
        .map((e) => e.subject.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<TimetableEntry> get _filteredEntries {
    final entries = _sortedEntries;
    if (_filterBy == 'day' && _selectedDay != null) {
      return entries
          .where((e) => _normaliseDay(e.dayOfWeek) == _selectedDay)
          .toList();
    }
    if (_filterBy == 'subject' && _selectedSubject != null) {
      return entries.where((e) => e.subject.trim() == _selectedSubject).toList();
    }
    return entries;
  }

  @override
  void initState() {
    super.initState();
    _syncSelections();
  }

  @override
  void didUpdateWidget(covariant _TimetablePrefillCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSelections();
  }

  void _syncSelections() {
    final days = _availableDays;
    final subjects = _availableSubjects;
    if (!days.contains(_selectedDay)) {
      _selectedDay = days.isEmpty ? null : days.first;
    }
    if (!subjects.contains(_selectedSubject)) {
      _selectedSubject = subjects.isEmpty ? null : subjects.first;
    }
    final filtered = _filteredEntries;
    if (!filtered.any((e) => e.id == _selectedEntryId)) {
      _selectedEntryId = filtered.isEmpty ? null : filtered.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;
    final selected = filtered.where((e) => e.id == _selectedEntryId);
    final selectedEntry = selected.isEmpty ? null : selected.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available_outlined,
                    color: AppColors.brand),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Choose an assigned lecture',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Text(
                  '${widget.entries.length} total',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Filter your timetable by day or subject, then choose the exact lecture.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _filterBy,
              decoration: const InputDecoration(
                labelText: 'Filter lectures by',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'day', child: Text('Day')),
                DropdownMenuItem(value: 'subject', child: Text('Subject')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _filterBy = value;
                  _syncSelections();
                });
              },
            ),
            const SizedBox(height: 12),
            if (_filterBy == 'day')
              DropdownButtonFormField<String>(
                value: _selectedDay,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select day',
                  border: OutlineInputBorder(),
                ),
                items: _availableDays
                    .map((day) => DropdownMenuItem(
                  value: day,
                  child: Text(day),
                ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDay = value;
                    _syncSelections();
                  });
                },
              )
            else
              DropdownButtonFormField<String>(
                value: _selectedSubject,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select subject',
                  border: OutlineInputBorder(),
                ),
                items: _availableSubjects
                    .map((subject) => DropdownMenuItem(
                  value: subject,
                  child: Text(subject, overflow: TextOverflow.ellipsis),
                ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSubject = value;
                    _syncSelections();
                  });
                },
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedEntryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Select lecture (${filtered.length} found)',
                border: const OutlineInputBorder(),
              ),
              items: filtered.map((entry) {
                final className =
                    '${entry.department} · Sem ${entry.semester} · Div ${entry.division}';
                return DropdownMenuItem<String>(
                  value: entry.id,
                  child: Text(
                    '${_normaliseDay(entry.dayOfWeek)} · ${entry.startTime}-${entry.endTime} · ${entry.subject} · $className',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: filtered.isEmpty
                  ? null
                  : (value) => setState(() => _selectedEntryId = value),
            ),
            if (selectedEntry != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brandTertiary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selectedEntry.subject,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '${selectedEntry.department} · Sem ${selectedEntry.semester} · Div ${selectedEntry.division}',
                    ),
                    Text(
                      '${_normaliseDay(selectedEntry.dayOfWeek)} · ${selectedEntry.startTime}–${selectedEntry.endTime}',
                    ),
                    if (selectedEntry.subjectId.isNotEmpty)
                      Text('Subject ID: ${selectedEntry.subjectId}'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: selectedEntry == null
                    ? null
                    : () => widget.onApply(selectedEntry),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Use selected lecture'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Student attendance
// ---------------------------------------------------------------------------

class StudentAttendanceScreen extends ConsumerWidget {
  const StudentAttendanceScreen({super.key, required this.profile});
  final UserProfile profile;

  static const double _threshold = 75;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'Attendance',
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: ref.read(dataRepositoryProvider).studentRecords(profile.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const _StateCard(
                text: 'Unable to verify attendance records.');
          if (!snapshot.hasData) return const _Loading();
          final records = snapshot.data!;
          final present = records.where((r) => r['status'] == 'present').length;
          final percent =
          records.isEmpty ? 0.0 : present * 100 / records.length;

          final subjectTotals = <String, int>{};
          final subjectPresent = <String, int>{};
          for (final r in records) {
            final name = (r['subjectName'] as String?)?.trim();
            if (name == null || name.isEmpty) continue;
            subjectTotals.update(name, (v) => v + 1, ifAbsent: () => 1);
            if (r['status'] == 'present') {
              subjectPresent.update(name, (v) => v + 1, ifAbsent: () => 1);
            }
          }
          final atRiskSubjects = subjectTotals.entries
              .map((e) =>
              MapEntry(e.key, (subjectPresent[e.key] ?? 0) * 100 / e.value))
              .where((e) => e.value < _threshold)
              .toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          final overallAtRisk = records.isNotEmpty && percent < _threshold;

          return ListView(
            children: [
              Card(
                color: AppColors.brand,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Overall attendance',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text(
                        '${percent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$present present of ${records.length} sessions',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              if (overallAtRisk || atRiskSubjects.isNotEmpty) ...[
                const SizedBox(height: 16),
                _LowAttendanceBanner(
                  student: profile,
                  overallAtRisk: overallAtRisk,
                  overallPercent: percent,
                  atRiskSubjects: atRiskSubjects,
                  threshold: _threshold,
                ),
              ],
              const SizedBox(height: 24),
              if (records.isEmpty)
                const _StateCard(text: 'No attendance sessions recorded yet.')
              else
                ...records.map((record) {
                  final isPresent = record['status'] == 'present';
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isPresent
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        color: isPresent ? AppColors.success : AppColors.error,
                      ),
                      title:
                      Text(record['subjectName'] as String? ?? 'Subject'),
                      subtitle: Text(record['sessionDate'] as String? ?? ''),
                      trailing: Text(
                        (record['status'] as String? ?? '').toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _LowAttendanceBanner extends ConsumerStatefulWidget {
  const _LowAttendanceBanner({
    required this.student,
    required this.overallAtRisk,
    required this.overallPercent,
    required this.atRiskSubjects,
    required this.threshold,
  });
  final UserProfile student;
  final bool overallAtRisk;
  final double overallPercent;
  final List<MapEntry<String, double>> atRiskSubjects;
  final double threshold;

  @override
  ConsumerState<_LowAttendanceBanner> createState() =>
      _LowAttendanceBannerState();
}

class _LowAttendanceBannerState extends ConsumerState<_LowAttendanceBanner> {
  bool _busy = false;

  Future<void> _openMentorChat() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final mentor =
      await ref.read(dataRepositoryProvider).findMentor(widget.student);
      if (!mounted) return;
      if (mentor == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No mentor is assigned yet. Please ask administration to set one.'),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConversationScreen(
            profile: widget.student,
            contact: mentor,
            initialDraft:
            'Hello sir/ma\'am, my overall attendance has dropped to ${widget.overallPercent.toStringAsFixed(1)}%. Could you please help me plan a recovery? Thank you.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach your mentor: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.overallAtRisk
        ? 'Overall attendance is below ${widget.threshold.toStringAsFixed(0)}%'
        : '${widget.atRiskSubjects.length} subject${widget.atRiskSubjects.length == 1 ? '' : 's'} below ${widget.threshold.toStringAsFixed(0)}%';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        border: Border.all(color: AppColors.error.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                        fontSize: 15,
                      ),
                    ),
                    if (widget.overallAtRisk)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'You are at ${widget.overallPercent.toStringAsFixed(1)}% overall. Please meet your mentor to plan a recovery.',
                          style: const TextStyle(color: AppColors.onSurface),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.atRiskSubjects.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Subjects to focus on',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.atRiskSubjects
                  .map(
                    (e) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border:
                    Border.all(color: AppColors.error.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${e.key} · ${e.value.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openMentorChat,
                  icon: _busy
                      ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message mentor'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tip: 75% is the usual minimum to appear in examinations. Your mentor can help you plan a recovery.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------


class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _search = TextEditingController();

  Set<String> _favourites = {};
  String _filter = 'All books';
  bool _loadingFavourites = true;

  bool get _canAddBooks =>
      widget.profile.role == 'teacher' ||
          widget.profile.role == 'admin';

  bool _canManageBook(Map<String, dynamic> data) {
    if (widget.profile.role == 'admin') return true;

    return widget.profile.role == 'teacher' &&
        data['createdBy'] == widget.profile.uid;
  }

  String get _favouriteKey =>
      'library_favourites_${widget.profile.uid}';

  @override
  void initState() {
    super.initState();
    _loadFavourites();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favourites = (prefs.getStringList(_favouriteKey) ?? []).toSet();
      _loadingFavourites = false;
    });
  }

  Future<void> _toggleFavourite(String id) async {
    final next = Set<String>.from(_favourites);
    if (!next.add(id)) next.remove(id);

    setState(() => _favourites = next);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favouriteKey, next.toList());
  }

  Future<void> _showBookForm({
    String? id,
    Map<String, dynamic>? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController(
        text: existing?['title'] as String? ?? '');
    final description = TextEditingController(
        text: existing?['description'] as String? ?? '');
    final category = TextEditingController(
        text: existing?['category'] as String? ?? 'Notes');
    final url = TextEditingController(
        text: existing?['downloadUrl'] as String? ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(id == null ? 'Add book' : 'Edit book'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Book title *',
                  ),
                  validator: (v) =>
                  v == null || v.trim().isEmpty
                      ? 'Enter a title'
                      : null,
                ),
                TextFormField(
                  controller: description,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                  ),
                  maxLines: 2,
                ),
                TextFormField(
                  controller: category,
                  decoration: const InputDecoration(
                    labelText: 'Category / Subject *',
                  ),
                  validator: (v) =>
                  v == null || v.trim().isEmpty
                      ? 'Enter a category'
                      : null,
                ),
                TextFormField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: 'Hosted PDF HTTPS URL *',
                    hintText: 'https://example.com/book.pdf',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    final uri = Uri.tryParse((v ?? '').trim());
                    if (uri == null ||
                        uri.scheme != 'https' ||
                        uri.host.isEmpty) {
                      return 'Enter a valid HTTPS link';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use an accessible PDF link. This form does not upload '
                      'the PDF file itself.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save book'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        final data = <String, dynamic>{
          'title': title.text.trim(),
          'description': description.text.trim(),
          'category': category.text.trim(),
          'downloadUrl': url.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (id == null) {
          data['createdBy'] = widget.profile.uid;
          data['createdByName'] = widget.profile.name;
          data['createdByRole'] = widget.profile.role;
          data['createdAt'] = FieldValue.serverTimestamp();
          data['likes'] = 0;
          data['dislikes'] = 0;
          await _db.collection('library').add(data);
        } else {
          await _db.collection('library').doc(id).update(data);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(id == null
                  ? 'Book added to the shared library'
                  : 'Book details updated'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save book: $e')),
          );
        }
      }
    }

    title.dispose();
    description.dispose();
    category.dispose();
    url.dispose();
  }

  Future<void> _deleteBook(
      String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove book?'),
        content: Text('Remove "$title" from the library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _db.collection('library').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove book: $e')),
        );
      }
    }
  }


  Future<void> _react(String id, String reaction) async {
    final reactionRef = _db
        .collection('library')
        .doc(id)
        .collection('reactions')
        .doc(widget.profile.uid);

    try {
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(reactionRef);
        final previous = snapshot.data()?['reaction'];

        if (previous == reaction) {
          transaction.delete(reactionRef);
        } else {
          transaction.set(reactionRef, {
            'reaction': reaction,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reaction: $e')),
        );
      }
    }
  }

  Future<void> _openPdf(
      String id, String title, String url) async {
    final uri = Uri.tryParse(url);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This book has an invalid PDF link')),
      );
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _LibraryPdfReader(
          title: title,
          url: url,
          progressKey: 'library_progress_${widget.profile.uid}_$id',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'E-Library',
      child: Column(
        children: [
          if (_canAddBooks)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showBookForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add book'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search books or subjects',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final label in [
                  'All books',
                  'Favourites',
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == label,
                    onSelected: (_) =>
                        setState(() => _filter = label),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('library')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Could not load the library. Check Firestore rules.',
                    ),
                  );
                }

                if (!snapshot.hasData || _loadingFavourites) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) =>
                      ((a.data()['title'] as String?) ?? '')
                          .toLowerCase()
                          .compareTo(
                        ((b.data()['title'] as String?) ?? '')
                            .toLowerCase(),
                      ));

                final query = _search.text.trim().toLowerCase();
                final books = docs.where((doc) {
                  final data = doc.data();
                  final title = (data['title'] as String? ?? '');
                  final category =
                  (data['category'] as String? ?? '');
                  final matchesSearch =
                  '$title $category'.toLowerCase().contains(query);
                  final matchesFavourite = _filter != 'Favourites' ||
                      _favourites.contains(doc.id);
                  return matchesSearch && matchesFavourite;
                }).toList();

                if (books.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _filter == 'Favourites'
                            ? 'No favourites yet. Tap the bookmark icon on a book.'
                            : query.isEmpty
                            ? 'No library resources found yet.'
                            : 'No books match your search.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.48,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, index) {
                    final doc = books[index];
                    final data = doc.data();
                    final title =
                        data['title'] as String? ?? 'Untitled';
                    final category =
                        data['category'] as String? ?? 'Notes';
                    final description =
                        data['description'] as String? ?? '';
                    final url =
                        data['downloadUrl'] as String? ?? '';
                    final canEditBook = _canManageBook(data);

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 64,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.brandTertiary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.menu_book_outlined,
                                size: 34,
                                color: AppColors.brand,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                            if (description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            const Spacer(),
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: doc.reference
                                  .collection('reactions')
                                  .snapshots(),
                              builder: (context, reactionsSnapshot) {
                                final reactions =
                                    reactionsSnapshot.data?.docs ?? [];

                                final likes = reactions
                                    .where((r) =>
                                r.data()['reaction'] == 'like')
                                    .length;

                                final dislikes = reactions
                                    .where((r) =>
                                r.data()['reaction'] == 'dislike')
                                    .length;

                                final mine = reactions.where(
                                      (r) => r.id == widget.profile.uid,
                                );
                                final myReaction = mine.isEmpty
                                    ? null
                                    : mine.first.data()['reaction'];

                                return Row(
                                  children: [
                                    Expanded(
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            _react(doc.id, 'like'),
                                        icon: Icon(
                                          myReaction == 'like'
                                              ? Icons.thumb_up
                                              : Icons.thumb_up_outlined,
                                          size: 20,
                                          color: myReaction == 'like'
                                              ? AppColors.brand
                                              : AppColors.onSurface,
                                        ),
                                        label: Text('$likes'),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          minimumSize: const Size(0, 40),
                                          foregroundColor: AppColors.onSurface,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            _react(doc.id, 'dislike'),
                                        icon: Icon(
                                          myReaction == 'dislike'
                                              ? Icons.thumb_down
                                              : Icons.thumb_down_outlined,
                                          size: 20,
                                          color: myReaction == 'dislike'
                                              ? AppColors.error
                                              : AppColors.onSurface,
                                        ),
                                        label: Text('$dislikes'),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          minimumSize: const Size(0, 40),
                                          foregroundColor: AppColors.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: url.isEmpty
                                        ? null
                                        : () => _openPdf(
                                      doc.id,
                                      title,
                                      url,
                                    ),
                                    child: const Text('Read'),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Favourite',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      _toggleFavourite(doc.id),
                                  icon: Icon(
                                    _favourites.contains(doc.id)
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                  ),
                                ),
                              ],
                            ),
                            if (canEditBook)
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () =>
                                          _showBookForm(
                                            id: doc.id,
                                            existing: data,
                                          ),
                                      child: const Text('Edit'),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove book',
                                    onPressed: () =>
                                        _deleteBook(doc.id, title),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryPdfReader extends StatefulWidget {
  const _LibraryPdfReader({
    required this.title,
    required this.url,
    required this.progressKey,
  });

  final String title;
  final String url;
  final String progressKey;

  @override
  State<_LibraryPdfReader> createState() => _LibraryPdfReaderState();
}

class _LibraryPdfReaderState extends State<_LibraryPdfReader> {
  PdfControllerPinch? _controller;
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _page = prefs.getInt(widget.progressKey) ?? 1;

      final response = await http
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('PDF server returned ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      if (bytes.length < 5 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw Exception('The link did not return a PDF file');
      }

      final document = await PdfDocument.openData(bytes);
      _pageCount = document.pagesCount;
      _page = _page.clamp(1, _pageCount).toInt();

      if (!mounted) {
        await document.close();
        return;
      }

      setState(() {
        _controller = PdfControllerPinch(
          document: Future.value(document),
          initialPage: _page,
        );
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to open this PDF. Check that the link is public and points directly to a PDF.\n$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _savePage(int page) async {
    _page = page;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(widget.progressKey, page);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_pageCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('$_page / $_pageCount'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
          ),
        ),
      )
          : PdfViewPinch(
        controller: _controller!,
        onPageChanged: _savePage,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// More
// ---------------------------------------------------------------------------

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'More',
      child: ListView(
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: AppColors.brandTertiary,
                child: Text(
                  profile.name.isEmpty ? '?' : profile.name[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.brand, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(profile.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${profile.role} · ${profile.phone}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProfileScreen(profile: profile)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (profile.role == 'admin')
            _Action(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Administrator tools',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AdminScreen(profile: profile)),
              ),
            ),
          _Action(
            icon: Icons.campaign_outlined,
            label: 'Notices',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NoticesScreen(profile: profile)),
            ),
          ),
          _Action(
            icon: Icons.directions_bus_outlined,
            label: 'Bus information',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BusScreen(profile: profile)),
            ),
          ),
          _Action(
            icon: Icons.chat_bubble_outline,
            label: 'Campus chat',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatScreen(profile: profile)),
            ),
          ),
          _Action(
            icon: Icons.auto_awesome_outlined,
            label: 'AI assistant',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AiScreen(profile: profile)),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                    'Your Firebase session will be ended on this device.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      FirebaseAuthScope.signOut(context);
                    },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class FirebaseAuthScope {
  static void signOut(BuildContext context) {
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(authProvider).signOut();
  }
}

// ---------------------------------------------------------------------------
// Notices
// ---------------------------------------------------------------------------

class NoticesScreen extends ConsumerWidget {
  const NoticesScreen({super.key, required this.profile});
  final UserProfile profile;

  bool get _canManage => profile.role == 'teacher' || profile.role == 'admin';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(dataRepositoryProvider);
    final stream = !_canManage
        ? repo.notices(profile)
        : profile.role == 'admin'
        ? repo.allStaffNotices()
        : repo.myNotices(profile.uid);

    return _Page(
      title: 'Notices',
      actions: [
        if (_canManage)
          IconButton(
            tooltip: 'Create notice',
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => NoticeComposerDialog(author: profile),
            ),
            icon: const Icon(Icons.add_rounded),
          ),
      ],
      child: StreamBuilder<List<Notice>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _StateCard(
              text: 'Notices could not be loaded. Check Firestore rules and indexes.',
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const _Loading();
          }
          final notices = snapshot.data ?? const <Notice>[];
          if (notices.isEmpty) {
            return _StateCard(
              text: _canManage
                  ? 'No notices yet. Tap + to create a notice or save a draft.'
                  : 'No notices for your class have been published yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: notices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final n = notices[i];
              final canEdit = _canManage &&
                  (profile.role == 'admin' || n.authorUid == profile.uid);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(label: Text(n.category)),
                          if (_canManage)
                            Chip(
                              avatar: Icon(n.published ? Icons.public : Icons.edit_note, size: 16),
                              label: Text(n.published ? 'Published' : 'Draft'),
                            ),
                          if (n.publishedAt != null)
                            Text(DateFormat.MMMd().format(n.publishedAt!),
                                style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(n.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(n.description),
                      if (n.libraryResourceTitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: n.libraryResourceUrl.trim().isEmpty
                              ? () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => LibraryScreen(profile: profile)))
                              : () async {
                            final uri = Uri.tryParse(n.libraryResourceUrl);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Library resource could not be opened.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text('Open Library resource: ${n.libraryResourceTitle}'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text('Published by ${n.authorName}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      if (canEdit) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!n.published)
                              FilledButton.tonalIcon(
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => NoticeComposerDialog(
                                    author: profile,
                                    existing: n,
                                  ),
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit draft'),
                              ),
                            if (!n.published)
                              FilledButton.icon(
                                onPressed: () async {
                                  try {
                                    await repo.publishSavedNotice(n.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Notice published.')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Could not publish notice: $e')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.publish),
                                label: const Text('Publish'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Delete notice?'),
                                    content: Text(
                                      '“${n.title}” will be permanently deleted. This action cannot be undone.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton.icon(
                                        onPressed: () => Navigator.pop(dialogContext, true),
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                try {
                                  await repo.deleteNotice(n.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Notice deleted.')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Could not delete notice: $e')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete notice'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NoticeComposerDialog extends ConsumerStatefulWidget {
  const NoticeComposerDialog({super.key, required this.author, this.existing});
  final UserProfile author;
  final Notice? existing;

  @override
  ConsumerState<NoticeComposerDialog> createState() => _NoticeComposerDialogState();
}

class _NoticeComposerDialogState extends ConsumerState<NoticeComposerDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late Future<List<Map<String, String>>> _groupsFuture;
  late Future<List<LibraryResource>> _libraryFuture;
  String _audience = 'allStudents';
  final Set<String> _selectedGroups = {};
  String? _libraryId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = widget.existing;
    _title = TextEditingController(text: n?.title ?? '');
    _description = TextEditingController(text: n?.description ?? '');
    _category = TextEditingController(text: n?.category ?? 'General');
    _audience = n?.audienceType == 'groups' ? 'groups' : 'allStudents';
    _selectedGroups.addAll(n?.targetGroupKeys ?? const []);
    _libraryId = n != null && n.libraryResourceId.isNotEmpty ? n.libraryResourceId : null;
    final repo = ref.read(dataRepositoryProvider);
    _groupsFuture = repo.noticeStudentGroups();
    _libraryFuture = repo.libraryOnce();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save(bool publishNow, List<LibraryResource> resources) async {
    if (_busy) return;
    if (_title.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Enter both a title and description.');
      return;
    }
    if (_audience == 'groups' && _selectedGroups.isEmpty) {
      setState(() => _error = 'Select at least one student group.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      LibraryResource? resource;
      for (final item in resources) {
        if (item.id == _libraryId) { resource = item; break; }
      }
      await ref.read(dataRepositoryProvider).saveNotice(
        author: widget.author,
        title: _title.text,
        description: _description.text,
        category: _category.text,
        publishNow: publishNow,
        audienceType: _audience,
        targetGroupKeys: _selectedGroups.toList(),
        libraryResource: resource,
        noticeId: widget.existing?.id,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = 'Could not save notice: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Create notice' : 'Edit draft'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _title, textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Title *')),
              const SizedBox(height: 8),
              TextField(controller: _description, minLines: 3, maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Description *')),
              const SizedBox(height: 8),
              TextField(controller: _category, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 16),
              const Text('Who should receive this notice?', style: TextStyle(fontWeight: FontWeight.w700)),
              RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'allStudents',
                  groupValue: _audience, title: const Text('All students'),
                  onChanged: _busy ? null : (v) => setState(() => _audience = v!)),
              RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'groups',
                  groupValue: _audience, title: const Text('Selected student groups'),
                  onChanged: _busy ? null : (v) => setState(() => _audience = v!)),
              if (_audience == 'groups')
                FutureBuilder<List<Map<String, String>>>(
                  future: _groupsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Text('Student groups could not be loaded. Check access to active student profiles.');
                    if (!snapshot.hasData) return const Padding(
                        padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                    final groups = snapshot.data!;
                    if (groups.isEmpty) return const Text('No complete active student groups were found.');
                    return Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(12)),
                      child: ListView(shrinkWrap: true, children: groups.map((group) {
                        final key = group['key']!;
                        return CheckboxListTile(
                            dense: true, value: _selectedGroups.contains(key),
                            title: Text(group['label']!), controlAffinity: ListTileControlAffinity.leading,
                            onChanged: _busy ? null : (checked) => setState(() {
                              if (checked == true) { _selectedGroups.add(key); } else { _selectedGroups.remove(key); }
                            }));
                      }).toList()),
                    );
                  },
                ),
              const SizedBox(height: 12),
              const Text('Optional Library resource', style: TextStyle(fontWeight: FontWeight.w700)),
              FutureBuilder<List<LibraryResource>>(
                future: _libraryFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Text('Library resources could not be loaded. You can still save without a link.');
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final resources = snapshot.data!;
                  final validId = resources.any((r) => r.id == _libraryId) ? _libraryId : null;
                  return DropdownButtonFormField<String>(
                    value: validId, isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Link an existing Library item'),
                    hint: const Text('No Library link'),
                    items: resources.map((r) => DropdownMenuItem<String>(
                        value: r.id, child: Text(r.title, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: _busy ? null : (value) => setState(() => _libraryId = value),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(
            onPressed: _busy ? null : () async {
              final resources = await _libraryFuture.then((v) => v, onError: (_) => <LibraryResource>[]);
              if (mounted) await _save(false, resources);
            },
            child: const Text('Save draft')),
        FilledButton(
            onPressed: _busy ? null : () async {
              final resources = await _libraryFuture.then((v) => v, onError: (_) => <LibraryResource>[]);
              if (mounted) await _save(true, resources);
            },
            child: Text(_busy ? 'Saving…' : 'Publish now')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bus
// ---------------------------------------------------------------------------

class BusScreen extends ConsumerWidget {
  const BusScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'Bus information',
      child: StreamBuilder<List<BusRoute>>(
        stream: ref.read(dataRepositoryProvider).buses(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const _StateCard(text: 'Bus service unavailable.');
          if (!snapshot.hasData) return const _Loading();
          final routes = snapshot.data!;
          if (routes.isEmpty) {
            return const _StateCard(
              text:
              'No bus routes published yet. Live GPS is unavailable until a tracking source is configured.',
            );
          }
          return ListView(
            children: routes
                .map(
                  (bus) => Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.directions_bus_outlined,
                      color: AppColors.brand),
                  title: Text(bus.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    bus.lastUpdated == null
                        ? 'Route schedule'
                        : 'Updated ${DateFormat.MMMd().add_jm().format(bus.lastUpdated!)}',
                  ),
                  children: [
                    ListTile(
                        title: const Text('Stops'),
                        subtitle: Text(bus.stops)),
                    ListTile(
                        title: const Text('Schedule'),
                        subtitle: Text(bus.schedule)),
                  ],
                ),
              ),
            )
                .toList(),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final searchController = TextEditingController();
  String searchText = '';

  String get _chatUid => FirebaseAuth.instance.currentUser?.uid ?? widget.profile.uid;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() {
      final value = searchController.text.trim().toLowerCase();
      if (value != searchText && mounted) setState(() => searchText = value);
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(dataRepositoryProvider);
    return _Page(
      title: 'Campus chat',
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repository.contacts(widget.profile),
        builder: (context, contactsSnapshot) {
          if (contactsSnapshot.hasError) {
            return const _StateCard(
              text: 'Could not load campus contacts. Check your connection and Firestore permissions.',
            );
          }
          if (!contactsSnapshot.hasData) return const _Loading();
          final contacts = contactsSnapshot.data!;
          final contactByUid = <String, Map<String, dynamic>>{
            for (final contact in contacts)
              if (contact['uid'] is String) contact['uid'] as String: contact,
          };

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: repository.conversations(_chatUid),
            builder: (context, conversationsSnapshot) {
              if (conversationsSnapshot.hasError) {
                debugPrint('[CampusChat] conversations stream failed: ${conversationsSnapshot.error}');
                return _StateCard(
                  text: 'Could not load conversations. Error: ${conversationsSnapshot.error}',
                );
              }
              if (!conversationsSnapshot.hasData) return const _Loading();
              final conversations = conversationsSnapshot.data!;
              final recentContactUids = <String>{};
              final recentTiles = <Widget>[];

              for (final conversation in conversations) {
                final participants = List<String>.from(
                  conversation['participantUids'] as List? ?? const [],
                );
                final otherUids = participants.where((uid) => uid != _chatUid).toList();
                if (otherUids.isEmpty) continue;
                final otherUid = otherUids.first;
                recentContactUids.add(otherUid);
                final contact = contactByUid[otherUid];
                final name = (contact?['name'] as String?)?.trim().isNotEmpty == true
                    ? (contact!['name'] as String).trim()
                    : 'Campus member';
                final role = contact?['role'] as String? ?? '';
                if (searchText.isNotEmpty &&
                    !name.toLowerCase().contains(searchText) &&
                    !role.toLowerCase().contains(searchText) &&
                    !(conversation['lastMessage'] as String? ?? '').toLowerCase().contains(searchText)) {
                  continue;
                }
                final conversationId = conversation['id'] as String? ?? '';
                recentTiles.add(
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: repository.messages(conversationId),
                    builder: (context, messagesSnapshot) {
                      final messages = messagesSnapshot.data ?? const <Map<String, dynamic>>[];
                      final unread = messages.where((message) {
                        final readBy = List<String>.from(message['readBy'] as List? ?? const []);
                        return message['senderUid'] != _chatUid &&
                            !readBy.contains(_chatUid);
                      }).length;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                          ),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            (conversation['lastMessage'] as String?)?.isNotEmpty == true
                                ? conversation['lastMessage'] as String
                                : (role.isNotEmpty ? role : 'Tap to open conversation'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: unread > 0
                              ? CircleAvatar(
                            radius: 12,
                            child: Text('$unread', style: const TextStyle(fontSize: 11)),
                          )
                              : const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ConversationScreen(
                                profile: widget.profile,
                                contact: contact ?? <String, dynamic>{'uid': otherUid, 'name': name, 'role': role},
                                existingConversationId: conversationId,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              }

              final filteredContacts = contacts.where((contact) {
                final uid = contact['uid'] as String? ?? '';
                final name = (contact['name'] as String? ?? '').toLowerCase();
                final role = (contact['role'] as String? ?? '').toLowerCase();
                return !recentContactUids.contains(uid) &&
                    (searchText.isEmpty || name.contains(searchText) || role.contains(searchText));
              }).toList()
                ..sort((a, b) =>
                    (a['name'] as String? ?? '').toLowerCase().compareTo(
                        (b['name'] as String? ?? '').toLowerCase()));

              return ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search people and messages',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchText.isEmpty
                          ? null
                          : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => searchController.clear(),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Recent conversations', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (recentTiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No conversations yet. Choose a campus contact below to start chatting.'),
                    )
                  else
                    ...recentTiles,
                  const SizedBox(height: 16),
                  Text(
                    widget.profile.role == 'student'
                        ? 'Teachers and administrators'
                        : widget.profile.role == 'teacher'
                        ? 'Students and administrators'
                        : 'Campus members',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (filteredContacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No matching contacts found.'),
                    ),
                  ...filteredContacts.map((contact) {
                    final name = contact['name'] as String? ?? 'Campus member';
                    final role = contact['role'] as String? ?? '';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                        ),
                        title: Text(name),
                        subtitle: Text(role.isEmpty ? 'Campus member' : role),
                        trailing: const Icon(Icons.chat_outlined),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConversationScreen(profile: widget.profile, contact: contact),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.profile,
    required this.contact,
    this.initialDraft = '',
    this.existingConversationId,
  });
  final UserProfile profile;
  final Map<String, dynamic> contact;
  final String initialDraft;
  final String? existingConversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final input = TextEditingController();
  String? conversationId;
  bool sending = false;

  String get _chatUid => FirebaseAuth.instance.currentUser?.uid ?? widget.profile.uid;

  @override
  void initState() {
    super.initState();
    conversationId = widget.existingConversationId;
    if (widget.initialDraft.isNotEmpty) input.text = widget.initialDraft;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    final otherUid = widget.contact['uid'] as String?;
    if (otherUid == null || otherUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This contact is unavailable.')),
      );
      return;
    }
    setState(() => sending = true);
    try {
      final repository = ref.read(dataRepositoryProvider);
      final id = conversationId ?? await repository.getOrCreateConversation(_chatUid, otherUid);
      await repository.sendMessage(id, _chatUid, text);
      if (!mounted) return;
      setState(() => conversationId = id);
      if (input.text.trim() == text) input.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message not sent. Please try again. (${error.runtimeType})')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.contact['name'] as String? ?? 'Conversation';
    final id = conversationId;
    return Scaffold(
      appBar: AppBar(title: Text(name), bottom: PreferredSize(
        preferredSize: const Size.fromHeight(22),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            (widget.contact['role'] as String? ?? '').toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      )),
      body: Column(
        children: [
          Expanded(
            child: id == null
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Send a message to start this conversation.', textAlign: TextAlign.center),
              ),
            )
                : StreamBuilder<List<Map<String, dynamic>>>(
              stream: ref.read(dataRepositoryProvider).messages(id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const _StateCard(text: 'Messages could not be loaded. Check your connection and access permissions.');
                }
                if (!snapshot.hasData) return const _Loading();
                final messages = snapshot.data!;
                // This method only updates messages that have not been read by this user.
                ref.read(dataRepositoryProvider).markMessagesRead(id, _chatUid, messages);
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hello!'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message['senderUid'] == _chatUid;
                    final readBy = List<String>.from(message['readBy'] as List? ?? const []);
                    final sentAt = message['sentAt'];
                    String time = '';
                    if (sentAt is Timestamp) time = DateFormat.jm().format(sentAt.toDate());
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.brand : AppColors.card,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(message['text'] as String? ?? '', style: TextStyle(color: isMe ? Colors.white : AppColors.onSurface)),
                            const SizedBox(height: 4),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : AppColors.muted)),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                Icon(readBy.length > 1 ? Icons.done_all : Icons.done, size: 14, color: readBy.length > 1 ? Colors.lightBlueAccent : Colors.white70),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => send(),
                    decoration: const InputDecoration(hintText: 'Write a message', counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : send,
                  tooltip: 'Send message',
                  icon: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// AI assistant
// ---------------------------------------------------------------------------

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final input = TextEditingController();
  final scrollController = ScrollController();

  final messages = <Map<String, String>>[];
  bool busy = false;

  String get _role => widget.profile.role.toLowerCase();

  @override
  void initState() {
    super.initState();

    messages.add({
      'role': 'assistant',
      'text': 'Hello, ${widget.profile.name}! 👋\n\n'
          'Welcome to E-Campus Assistant. How can I help you today?\n\n'
          'Tap one of the suggested options below or type your own question.',
    });
  }

  @override
  void dispose() {
    input.dispose();
    scrollController.dispose();
    super.dispose();
  }

  List<String> get _options {
    if (messages.length == 1) {
      return ref.read(aiServiceProvider).welcomeOptions(_role);
    }

    final lastUserMessage = messages.lastWhere(
          (m) => m['role'] == 'user',
      orElse: () => {'text': ''},
    );

    return ref
        .read(aiServiceProvider)
        .followUpOptions(lastUserMessage['text'] ?? '', _role);
  }

  Future<void> _send(String value) async {
    final text = value.trim();

    if (text.isEmpty || busy) return;

    if (text.toLowerCase() == 'back to main menu') {
      setState(() {
        messages.add({'role': 'user', 'text': text});
        messages.add({
          'role': 'assistant',
          'text': 'Here is the main menu. What would you like help with?',
        });
      });
      _scrollToBottom();
      return;
    }

    setState(() {
      messages.add({'role': 'user', 'text': text});
      input.clear();
      busy = true;
    });

    _scrollToBottom();

    try {
      final response = await ref.read(aiServiceProvider).ask(
        text,
        role: _role,
      );

      if (!mounted) return;

      setState(() {
        messages.add({'role': 'assistant', 'text': response});
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        messages.add({
          'role': 'assistant',
          'text': 'Sorry, I could not process that question right now. '
              'Please try again.',
        });
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Campus Assistant'),
        actions: [
          IconButton(
            tooltip: 'Main menu',
            onPressed: busy
                ? null
                : () {
              setState(() {
                messages.add({
                  'role': 'assistant',
                  'text': 'Here is the main menu. What would you like help with?',
                });
              });
              _scrollToBottom();
            },
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isUser = message['role'] == 'user';

                return Align(
                  alignment:
                  isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.86,
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.brandTertiary
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(message['text'] ?? ''),
                  ),
                );
              },
            ),
          ),

          if (busy) const LinearProgressIndicator(),

          if (!busy && options.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested questions',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((option) {
                      return ActionChip(
                        avatar: const Icon(
                          Icons.chat_bubble_outline,
                          size: 16,
                        ),
                        label: Text(option),
                        onPressed: () => _send(option),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: _send,
                      decoration: const InputDecoration(
                        hintText: 'Type your question...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: busy ? null : () => _send(input.text),
                    tooltip: 'Send question',
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _saving = false;

  Future<void> _editProfile() async {
    final name = TextEditingController(text: widget.profile.name);
    final email = TextEditingController(text: widget.profile.email);

    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit profile'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter your name'
                      : null),
              TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                  const InputDecoration(labelText: 'Email (optional)')),
              const SizedBox(height: 8),
              const Text(
                  'Course placement, role, and activation status are administrator-controlled.',
                  style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate())
                  Navigator.pop(dialogContext, true);
              },
              child: const Text('Save')),
        ],
      ),
    );
    if (save == true && mounted) {
      setState(() => _saving = true);
      try {
        await ref.read(dataRepositoryProvider).updateProfile(
          uid: widget.profile.uid,
          phone: widget.profile.phone,
          name: name.text.trim(),
          email: email.text.trim(),
        );
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not update profile: $e')));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    name.dispose();
    email.dispose();
  }

  Future<void> _uploadPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result == null) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception(
          'The selected image could not be read. Please choose it again.',
        );
      }

      const maxBytes = 5 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        throw Exception('Please choose an image smaller than 5 MB.');
      }

      final extension = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'jpg';
      const allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
      if (!allowedExtensions.contains(extension)) {
        throw Exception('Choose a JPG, PNG, or WebP image.');
      }

      setState(() => _saving = true);

      // Cloudinary unsigned upload. The cloud name and preset are public
      // identifiers; never put a Cloudinary API secret in a mobile app.
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://api.cloudinary.com/v1_1/gzs4tpcs/image/upload',
        ),
      )
        ..fields['upload_preset'] = 'ecampus_profile'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: file.name,
          ),
        );

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      final decoded = jsonDecode(responseBody);

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        final message = decoded is Map<String, dynamic>
            ? (decoded['error'] is Map<String, dynamic>
            ? decoded['error']['message']?.toString()
            : null)
            : null;
        throw Exception(message ?? 'Cloudinary upload failed. Please retry.');
      }

      if (decoded is! Map<String, dynamic> ||
          decoded['secure_url'] is! String) {
        throw Exception(
          'Cloudinary uploaded the image but did not return its URL.',
        );
      }

      final photoUrl = decoded['secure_url'] as String;
      await ref.read(firestoreProvider).collection('users')
          .doc(widget.profile.uid)
          .set({
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload photo: $message')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        ref.watch(userProfileProvider(widget.profile.uid)).valueOrNull ??
            widget.profile;
    return _Page(
      title: 'Profile',
      actions: [
        IconButton(
            tooltip: 'Edit profile',
            onPressed: _saving ? null : _editProfile,
            icon: const Icon(Icons.edit_outlined))
      ],
      child: ListView(children: [
        Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  CircleAvatar(
                      radius: 42,
                      backgroundColor: AppColors.brandTertiary,
                      backgroundImage: profile.photoUrl.isNotEmpty
                          ? NetworkImage(profile.photoUrl)
                          : null,
                      child: profile.photoUrl.isEmpty
                          ? const Icon(Icons.person_outline,
                          size: 38, color: AppColors.brand)
                          : null),
                  const SizedBox(height: 8),
                  TextButton.icon(
                      onPressed: _saving ? null : _uploadPhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Change photo')),
                  const SizedBox(height: 8),
                  Text(profile.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  Text(profile.role.toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.muted, letterSpacing: 1.2)),
                  if (_saving)
                    const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator()),
                ]))),
        const SizedBox(height: 16),
        _Info(label: 'Phone', value: profile.phone),
        _Info(
            label: 'Email',
            value: profile.email.isEmpty ? 'Not added' : profile.email),
        _Info(
            label: 'Department',
            value: profile.department.isEmpty
                ? 'Not assigned'
                : profile.department),
        _Info(
            label: 'Semester / division',
            value:
            '${profile.semester.isEmpty ? '—' : profile.semester} / ${profile.division.isEmpty ? '—' : profile.division}'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _saving ? null : _editProfile,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit profile details')),
        const SizedBox(height: 8),
        const Text('Role and activation status are administrator-controlled.',
            style: TextStyle(color: AppColors.muted)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.actions});
  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: child,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon, color: AppColors.brand),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        subtitle:
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}