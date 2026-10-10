import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:e_campus/core/models/models.dart';
import 'package:e_campus/features/screens/attendance_chart.dart';

void main() {
  testWidgets('WeeklyAttendanceTrend renders empty state when no sessions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WeeklyAttendanceTrend(sessions: []))),
    );
    expect(find.text('Weekly attendance trend'), findsOneWidget);
    expect(find.text('Submit a session to see weekly trends.'), findsOneWidget);
  });

  testWidgets('WeeklyAttendanceTrend shows subject chip for recent session', (tester) async {
    final now = DateTime.now();
    final session = AttendanceSession(
      id: 's1',
      subjectName: 'Big Data',
      date: now,
      presentCount: 8,
      absentCount: 2,
      department: 'MCA',
      semester: '2',
      division: 'A',
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: WeeklyAttendanceTrend(sessions: [session]))),
    );
    expect(find.textContaining('Big Data'), findsOneWidget);
  });
}
