import 'package:flutter_test/flutter_test.dart';
import 'package:e_campus/core/models/models.dart';

void main() {
  test('attendance percentage is calculated from present and absent records', () {
    const session = AttendanceSession(id: 's', subjectName: 'Math', date: null, presentCount: 3, absentCount: 1, department: 'MCA', semester: '1', division: 'A');
    expect(session.percentage, 75);
  });

  test('date keys are stable and zero padded', () {
    expect(dateKey(DateTime(2026, 1, 4)), '2026-01-04');
  });
}