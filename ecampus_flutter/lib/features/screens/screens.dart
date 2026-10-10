import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import 'admin_screen.dart';
import 'attendance_chart.dart';

export 'attendance_chart.dart';

// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'Schedule',
      child: StreamBuilder<List<TimetableEntry>>(
        stream: ref.read(dataRepositoryProvider).timetable(profile),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _StateCard(text: 'Could not load timetable.');
          if (!snapshot.hasData) return const _Loading();
          final data = snapshot.data!;
          if (data.isEmpty) return const _StateCard(text: 'No classes scheduled for your current class.');
          return ListView.separated(
            itemCount: data.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final item = data[i];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.brandTertiary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.menu_book_outlined, color: AppColors.brand),
                  ),
                  title: Text(item.subject, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${item.dayOfWeek} · ${item.startTime}–${item.endTime}\n${item.teacherName} · ${item.room}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
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
                    statuses = {for (final student in roster) student['uid'] as String: true};
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
              onPressed: busy || statuses.length != roster.length ? null : _submit,
              child: const Text('Submit attendance'),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Recent sessions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AttendanceSession>>(
            stream: repo.teacherSessions(widget.profile.uid),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const _Loading();
              if (snapshot.data!.isEmpty) {
                return const _StateCard(text: 'No attendance sessions submitted yet.');
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
                      trailing: Text('${session.percentage.toStringAsFixed(0)}%'),
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

  Future<void> _submit() async {
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
    final title = TextEditingController();
    final description = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish notice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || description.text.trim().isEmpty) return;
              await ref.read(dataRepositoryProvider).publishNotice(
                    author: widget.profile,
                    title: title.text,
                    description: description.text,
                    category: 'Faculty',
                  );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    title.dispose();
    description.dispose();
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TimetablePrefillCard extends StatelessWidget {
  const _TimetablePrefillCard({required this.entries, required this.onApply});
  final List<TimetableEntry> entries;
  final void Function(TimetableEntry) onApply;

  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) {
        final day = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (day != 0) return day;
        return a.startTime.compareTo(b.startTime);
      });
    final visible = sorted.take(3).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your assigned lectures',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                Text(
                  '${entries.length} total',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "Use this class" to prefill the form below.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...visible.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.subject,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${e.department} ${e.semester}-${e.division} · ${e.dayOfWeek} ${e.startTime}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => onApply(e),
                      child: const Text('Use this class'),
                    ),
                  ],
                ),
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
          if (snapshot.hasError) return const _StateCard(text: 'Unable to verify attendance records.');
          if (!snapshot.hasData) return const _Loading();
          final records = snapshot.data!;
          final present = records.where((r) => r['status'] == 'present').length;
          final percent = records.isEmpty ? 0.0 : present * 100 / records.length;

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
              .map((e) => MapEntry(e.key, (subjectPresent[e.key] ?? 0) * 100 / e.value))
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
                      const Text('Overall attendance', style: TextStyle(color: Colors.white70)),
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
                        isPresent ? Icons.check_circle_outline : Icons.cancel_outlined,
                        color: isPresent ? AppColors.success : AppColors.error,
                      ),
                      title: Text(record['subjectName'] as String? ?? 'Subject'),
                      subtitle: Text(record['sessionDate'] as String? ?? ''),
                      trailing: Text(
                        (record['status'] as String? ?? '').toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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

class _LowAttendanceBanner extends StatelessWidget {
  const _LowAttendanceBanner({
    required this.overallAtRisk,
    required this.overallPercent,
    required this.atRiskSubjects,
    required this.threshold,
  });
  final bool overallAtRisk;
  final double overallPercent;
  final List<MapEntry<String, double>> atRiskSubjects;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final title = overallAtRisk
        ? 'Overall attendance is below ${threshold.toStringAsFixed(0)}%'
        : '${atRiskSubjects.length} subject${atRiskSubjects.length == 1 ? '' : 's'} below ${threshold.toStringAsFixed(0)}%';
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
                    if (overallAtRisk)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'You are at ${overallPercent.toStringAsFixed(1)}% overall. Please meet your mentor to plan a recovery.',
                          style: const TextStyle(color: AppColors.onSurface),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (atRiskSubjects.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Subjects to focus on',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: atRiskSubjects
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.error.withOpacity(0.5)),
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
          const Text(
            'Tip: 75% is the usual minimum to appear in examinations. Reach out to your mentor or class representative to catch up.',
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

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'E-Library',
      child: StreamBuilder<List<LibraryResource>>(
        stream: ref.read(dataRepositoryProvider).library(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _StateCard(text: 'Failed to fetch library catalog.');
          if (!snapshot.hasData) return const _Loading();
          final items = snapshot.data!;
          if (items.isEmpty) return const _StateCard(text: 'No library resources found yet.');
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 76,
                        decoration: BoxDecoration(
                          color: AppColors.brandTertiary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Icon(Icons.menu_book_outlined, size: 34, color: AppColors.brand),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.category,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      const Spacer(),
                      if (item.url.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(item.url),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open'),
                        ),
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
                  style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${profile.role} · ${profile.phone}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen(profile: profile)),
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
                MaterialPageRoute(builder: (_) => AdminScreen(profile: profile)),
              ),
            ),
          _Action(
            icon: Icons.campaign_outlined,
            label: 'Notices',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NoticesScreen(profile: profile)),
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
                content: const Text('Your Firebase session will be ended on this device.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'Notices',
      child: StreamBuilder<List<Notice>>(
        stream: ref.read(dataRepositoryProvider).notices(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _StateCard(text: 'Notices could not be loaded.');
          if (!snapshot.hasData) return const _Loading();
          return ListView.separated(
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final n = snapshot.data![i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Chip(label: Text(n.category)),
                          const Spacer(),
                          Text(
                            n.publishedAt == null ? '' : DateFormat.MMMd().format(n.publishedAt!),
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(n.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(n.description),
                      const SizedBox(height: 12),
                      Text(
                        'Published by ${n.authorName}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
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
          if (snapshot.hasError) return const _StateCard(text: 'Bus service unavailable.');
          if (!snapshot.hasData) return const _Loading();
          final routes = snapshot.data!;
          if (routes.isEmpty) {
            return const _StateCard(
              text: 'No bus routes published yet. Live GPS is unavailable until a tracking source is configured.',
            );
          }
          return ListView(
            children: routes
                .map(
                  (bus) => Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.directions_bus_outlined, color: AppColors.brand),
                      title: Text(bus.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        bus.lastUpdated == null
                            ? 'Route schedule'
                            : 'Updated ${DateFormat.MMMd().add_jm().format(bus.lastUpdated!)}',
                      ),
                      children: [
                        ListTile(title: const Text('Stops'), subtitle: Text(bus.stops)),
                        ListTile(title: const Text('Schedule'), subtitle: Text(bus.schedule)),
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

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'Campus chat',
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: ref.read(dataRepositoryProvider).contacts(profile.uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _Loading();
          final contacts = snapshot.data!;
          return ListView(
            children: [
              const Text('Authorized contacts', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ...contacts.map(
                (contact) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(contact['name'] as String? ?? 'Campus member'),
                    subtitle: Text(contact['role'] as String? ?? ''),
                    trailing: const Icon(Icons.chat_outlined),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConversationScreen(profile: profile, contact: contact),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.profile, required this.contact});
  final UserProfile profile;
  final Map<String, dynamic> contact;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final input = TextEditingController();
  String? conversationId;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (input.text.trim().isEmpty) return;
    conversationId ??= await ref
        .read(dataRepositoryProvider)
        .getOrCreateConversation(widget.profile.uid, widget.contact['uid'] as String);
    final text = input.text;
    input.clear();
    await ref.read(dataRepositoryProvider).sendMessage(conversationId!, widget.profile.uid, text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.contact['name'] as String? ?? 'Conversation')),
      body: Column(
        children: [
          Expanded(
            child: conversationId == null
                ? const _StateCard(text: 'Send a message to start this secure conversation.')
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ref.read(dataRepositoryProvider).messages(conversationId!),
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const <Map<String, dynamic>>[];
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: messages.map((m) {
                          final isMe = m['senderUid'] == widget.profile.uid;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe ? AppColors.brand : AppColors.card,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                m['text'] as String? ?? '',
                                style: TextStyle(
                                  color: isMe ? Colors.white : AppColors.onSurface,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Write a message'),
                  ),
                ),
                IconButton(
                  onPressed: send,
                  icon: const Icon(Icons.send, color: AppColors.brand),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
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
  final messages = <Map<String, String>>[];
  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;
    setState(() {
      messages.add({'role': 'user', 'text': text});
      input.clear();
      busy = true;
    });
    try {
      final response = await ref.read(aiServiceProvider).ask(text);
      setState(() => messages.add({'role': 'assistant', 'text': response}));
    } catch (_) {
      setState(() => messages.add({
            'role': 'assistant',
            'text': 'The AI assistant is not available yet. Complete the documented Cloud Function and provider-key setup.',
          }));
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI assistant')),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Ask about college procedures, study topics, or campus information.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => Card(
                      color: messages[i]['role'] == 'user'
                          ? AppColors.brandTertiary
                          : AppColors.card,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(messages[i]['text']!),
                      ),
                    ),
                  ),
          ),
          if (busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Ask E-Campus'),
                  ),
                ),
                IconButton(
                  onPressed: ask,
                  icon: const Icon(Icons.send, color: AppColors.brand),
                ),
              ],
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

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Page(
      title: 'Profile',
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.brandTertiary,
                    child: Icon(Icons.person_outline, size: 38, color: AppColors.brand),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    profile.role.toUpperCase(),
                    style: const TextStyle(color: AppColors.muted, letterSpacing: 1.2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Info(label: 'Phone', value: profile.phone),
          _Info(
            label: 'Department',
            value: profile.department.isEmpty ? 'Not assigned' : profile.department,
          ),
          _Info(
            label: 'Semester / division',
            value:
                '${profile.semester.isEmpty ? '—' : profile.semester} / ${profile.division.isEmpty ? '—' : profile.division}',
          ),
          const SizedBox(height: 12),
          const Text(
            'Role and activation status are administrator-controlled.',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
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
        title: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
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
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}
