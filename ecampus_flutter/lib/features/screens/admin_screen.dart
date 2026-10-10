import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../app.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administrator tools'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              Tab(icon: Icon(Icons.insights_outlined), text: 'Weekly rollup'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AuthorizedUsersTab(),
            _WeeklyRollupTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Authorized users
// ---------------------------------------------------------------------------

class _AuthorizedUsersTab extends ConsumerWidget {
  const _AuthorizedUsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref
          .read(firestoreProvider)
          .collection('authorized_users')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Authorized user records could not be loaded.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${snapshot.data!.docs.length} authorized users',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                FilledButton.icon(
                  onPressed: () => _addUser(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...snapshot.data!.docs.map((doc) {
              final data = doc.data();
              final active = data['active'] as bool? ?? false;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: SwitchListTile(
                  value: active,
                  onChanged: (value) => ref
                      .read(firestoreProvider)
                      .collection('authorized_users')
                      .doc(doc.id)
                      .update({'active': value, 'updatedAt': FieldValue.serverTimestamp()}),
                  title: Text(
                    data['name'] as String? ?? doc.id,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${data['role'] ?? 'student'} · ${doc.id}'),
                  secondary: Icon(
                    active ? Icons.verified_outlined : Icons.pause_circle_outline,
                    color: active ? AppColors.success : AppColors.warning,
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _addUser(BuildContext context, WidgetRef ref) async {
    final phone = TextEditingController();
    final name = TextEditingController();
    String role = 'student';
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Authorize account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'E.164 phone number'),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              DropdownButtonFormField<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                  DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                ],
                onChanged: (value) => setDialog(() => role = value ?? role),
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (phone.text.trim().isEmpty || name.text.trim().isEmpty) return;
                await ref
                    .read(firestoreProvider)
                    .collection('authorized_users')
                    .doc(phone.text.trim())
                    .set({
                  'phone': phone.text.trim(),
                  'name': name.text.trim(),
                  'role': role,
                  'active': true,
                  'department': '',
                  'semester': '',
                  'division': '',
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Authorize'),
            ),
          ],
        ),
      ),
    );
    phone.dispose();
    name.dispose();
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Weekly rollup
// ---------------------------------------------------------------------------

class _WeeklyRollupTab extends ConsumerWidget {
  const _WeeklyRollupTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<AttendanceSession>>(
      stream: ref.read(dataRepositoryProvider).allSessions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Attendance sessions could not be loaded.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = DateTime.now();
        final sevenDaysAgo = DateTime(today.year, today.month, today.day)
            .subtract(const Duration(days: 6));
        final recent = snapshot.data!.where((s) {
          if (s.date == null) return false;
          final d = DateTime(s.date!.year, s.date!.month, s.date!.day);
          return !d.isBefore(sevenDaysAgo);
        }).toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalsCard(sessions: recent),
              const SizedBox(height: 16),
              _DailyBreakdown(sessions: recent),
              const SizedBox(height: 16),
              _DepartmentBreakdown(sessions: recent),
              const SizedBox(height: 16),
              _ClassesNeedingHelp(sessions: recent),
            ],
          ),
        );
      },
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.sessions});
  final List<AttendanceSession> sessions;

  @override
  Widget build(BuildContext context) {
    final totalSessions = sessions.length;
    final totalPresent = sessions.fold<int>(0, (a, s) => a + s.presentCount);
    final totalAbsent = sessions.fold<int>(0, (a, s) => a + s.absentCount);
    final totalMarks = totalPresent + totalAbsent;
    final avg = totalMarks == 0 ? 0.0 : totalPresent * 100 / totalMarks;
    return Card(
      color: AppColors.brand,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Last 7 days across the whole college',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetricTile(label: 'Sessions', value: '$totalSessions'),
                const SizedBox(width: 12),
                _MetricTile(label: 'Marks recorded', value: '$totalMarks'),
                const SizedBox(width: 12),
                _MetricTile(label: 'Avg rate', value: '${avg.toStringAsFixed(1)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _DailyBreakdown extends StatelessWidget {
  const _DailyBreakdown({required this.sessions});
  final List<AttendanceSession> sessions;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List<DateTime>.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i)),
    );
    final sessionsByDay = <DateTime, int>{};
    final rateSumByDay = <DateTime, double>{};
    final rateCountByDay = <DateTime, int>{};
    for (final s in sessions) {
      if (s.date == null) continue;
      final d = DateTime(s.date!.year, s.date!.month, s.date!.day);
      sessionsByDay.update(d, (v) => v + 1, ifAbsent: () => 1);
      if (s.presentCount + s.absentCount > 0) {
        rateSumByDay.update(d, (v) => v + s.percentage, ifAbsent: () => s.percentage);
        rateCountByDay.update(d, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final maxCount = sessionsByDay.values.fold<int>(0, (a, b) => b > a ? b : a);
    final dayLabel = DateFormat('EEE');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sessions per day',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: days.map((d) {
                  final count = sessionsByDay[d] ?? 0;
                  final rateCount = rateCountByDay[d] ?? 0;
                  final avg = rateCount == 0 ? 0.0 : (rateSumByDay[d] ?? 0) / rateCount;
                  final heightFactor =
                      maxCount == 0 ? 0.05 : (count / maxCount).clamp(0.05, 1.0);
                  final color = count == 0
                      ? AppColors.brandTertiary
                      : avg >= 75
                          ? AppColors.success
                          : avg >= 50
                              ? AppColors.warning
                              : AppColors.error;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            count == 0 ? '—' : '$count',
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: FractionallySizedBox(
                              heightFactor: heightFactor,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius:
                                      const BorderRadius.vertical(top: Radius.circular(6)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dayLabel.format(d),
                            style: const TextStyle(fontSize: 11, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bar height = sessions submitted. Colour = that day\'s average rate (green ≥ 75%, amber ≥ 50%, red otherwise).',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentBreakdown extends StatelessWidget {
  const _DepartmentBreakdown({required this.sessions});
  final List<AttendanceSession> sessions;

  @override
  Widget build(BuildContext context) {
    final byDept = <String, List<AttendanceSession>>{};
    for (final s in sessions) {
      final key = s.department.isEmpty ? 'Unassigned' : s.department;
      byDept.putIfAbsent(key, () => []).add(s);
    }
    if (byDept.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const Text(
            'No sessions submitted in the last 7 days.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    final entries = byDept.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'By department',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...entries.map((entry) {
              final list = entry.value;
              final totalMarks = list.fold<int>(0, (a, s) => a + s.presentCount + s.absentCount);
              final presentMarks = list.fold<int>(0, (a, s) => a + s.presentCount);
              final avg = totalMarks == 0 ? 0.0 : presentMarks * 100 / totalMarks;
              final color = avg >= 75
                  ? AppColors.success
                  : avg >= 50
                      ? AppColors.warning
                      : AppColors.error;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${list.length} session${list.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${avg.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ClassesNeedingHelp extends StatelessWidget {
  const _ClassesNeedingHelp({required this.sessions});
  final List<AttendanceSession> sessions;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<AttendanceSession>>{};
    for (final s in sessions) {
      final key =
          '${s.department.isEmpty ? "—" : s.department} · Sem ${s.semester.isEmpty ? "—" : s.semester} · Div ${s.division.isEmpty ? "—" : s.division} · ${s.subjectName}';
      grouped.putIfAbsent(key, () => []).add(s);
    }
    final struggling = grouped.entries.map((e) {
      final totalMarks = e.value.fold<int>(0, (a, s) => a + s.presentCount + s.absentCount);
      final presentMarks = e.value.fold<int>(0, (a, s) => a + s.presentCount);
      final avg = totalMarks == 0 ? 0.0 : presentMarks * 100 / totalMarks;
      return MapEntry(e.key, avg);
    }).where((entry) => entry.value < 75).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_outlined, color: AppColors.error),
                const SizedBox(width: 8),
                const Text(
                  'Classes needing help',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${struggling.length}',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (struggling.isEmpty)
              const Text(
                'Every class in this window is above 75%. Nicely done.',
                style: TextStyle(color: AppColors.muted),
              )
            else
              ...struggling.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${e.value.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
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
