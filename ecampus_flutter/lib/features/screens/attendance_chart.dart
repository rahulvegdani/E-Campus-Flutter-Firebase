import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

/// Lightweight 7-day attendance trend chart.
/// No external chart dependency — uses layout-only widgets so the project
/// stays on the dependencies already listed in pubspec.yaml.
///
/// For every one of the last 7 days we compute the teacher's average
/// attendance percentage across sessions submitted that day. A per-subject
/// summary is shown below the bar strip.
class WeeklyAttendanceTrend extends StatelessWidget {
  const WeeklyAttendanceTrend({super.key, required this.sessions});

  final List<AttendanceSession> sessions;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List<DateTime>.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i)),
    );
    final dayLabel = DateFormat('EEE');

    final dayAverages = <DateTime, double>{};
    final dayCounts = <DateTime, int>{};
    final subjectAverages = <String, List<double>>{};

    for (final s in sessions) {
      if (s.date == null) continue;
      final total = s.presentCount + s.absentCount;
      if (total == 0) continue;
      final dayKey = DateTime(s.date!.year, s.date!.month, s.date!.day);
      if (!days.contains(dayKey)) continue;
      dayAverages.update(dayKey, (v) => v + s.percentage, ifAbsent: () => s.percentage);
      dayCounts.update(dayKey, (v) => v + 1, ifAbsent: () => 1);
      subjectAverages.putIfAbsent(s.subjectName, () => []).add(s.percentage);
    }

    final bars = days.map((d) {
      final count = dayCounts[d] ?? 0;
      final avg = count == 0 ? 0.0 : (dayAverages[d] ?? 0) / count;
      return _DayBar(label: dayLabel.format(d), percent: avg, hasData: count > 0);
    }).toList();

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
                  'Weekly attendance trend',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                Text(
                  'Last 7 days',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: bars.map((b) => Expanded(child: b)).toList(),
              ),
            ),
            const SizedBox(height: 16),
            if (subjectAverages.isEmpty)
              const Text(
                'Submit a session to see weekly trends.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              )
            else ...[
              const Text(
                'By subject (7-day avg)',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subjectAverages.entries.map((e) {
                  final avg = e.value.reduce((a, b) => a + b) / e.value.length;
                  return Chip(
                    backgroundColor: AppColors.brandTertiary,
                    label: Text(
                      '${e.key} · ${avg.toStringAsFixed(0)}%',
                      style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.label, required this.percent, required this.hasData});

  final String label;
  final double percent;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0.0, 100.0);
    final color = !hasData
        ? AppColors.brandTertiary
        : clamped >= 75
            ? AppColors.success
            : clamped >= 50
                ? AppColors.warning
                : AppColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            hasData ? '${clamped.toStringAsFixed(0)}%' : '—',
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: hasData ? (clamped / 100).clamp(0.05, 1.0) : 0.05,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }
}
