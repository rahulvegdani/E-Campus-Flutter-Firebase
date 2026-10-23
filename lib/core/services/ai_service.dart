import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AiService {
AiService(this.auth, this.db);

final FirebaseAuth auth;
final FirebaseFirestore db;

List<String> welcomeOptions(String role) {
switch (role.toLowerCase()) {
case 'teacher':
return [
'Attendance management',
'My timetable',
'Teaching and lesson planning',
'Student communication',
'Exam preparation',
'Notices and announcements',
'Campus Chat help',
'Other questions',
];
case 'admin':
return [
'Student and teacher accounts',
'Attendance management',
'Timetable management',
'Notices and announcements',
'Campus Chat help',
'App troubleshooting',
'College administration',
'Other questions',
];
default:
return [
'Check my attendance',
'View my timetable',
'Help with the library',
'Exam preparation tips',
'Study tips',
'Bus routes and transport',
'Notices and announcements',
'Campus Chat help',
'Profile and login help',
'Other questions',
];
}
}

List<String> followUpOptions(String prompt, String role) {
final q = prompt.toLowerCase();

if (_containsAny(q, ['attendance', 'present', 'absent', 'percentage'])) {
return role == 'student'
? [
'How do I improve my attendance?',
'What if my attendance is incorrect?',
'How do I contact my teacher?',
'Back to main menu',
]
    : [
'What if attendance records are incorrect?',
'How do I view my timetable?',
'How can I contact students?',
'Back to main menu',
];
}

if (_containsAny(q, ['timetable', 'schedule', 'lecture', 'class time'])) {
return [
'What if my timetable is incorrect?',
'How do I check attendance?',
'Back to main menu',
];
}

if (_containsAny(q, ['library', 'book', 'ebook', 'resource'])) {
return [
'How do I open library resources?',
'How can I prepare for exams?',
'Back to main menu',
];
}

if (_containsAny(q, ['exam', 'revision', 'prepare', 'study plan'])) {
return [
'Give me daily study tips',
'Help me make a revision plan',
'How do I improve concentration?',
'Back to main menu',
];
}

if (_containsAny(q, ['study', 'focus', 'concentrate', 'remember'])) {
return [
'Help me prepare for exams',
'Help me make a study plan',
'Back to main menu',
];
}

if (_containsAny(q, ['bus', 'transport', 'route', 'pickup'])) {
return [
'Where can I find bus stops?',
'What if route information is missing?',
'Back to main menu',
];
}

if (_containsAny(q, ['notice', 'announcement', 'circular', 'event'])) {
return [
'Where can I read college notices?',
'How do I contact the college?',
'Back to main menu',
];
}

if (_containsAny(q, ['chat', 'message', 'contact', 'communication'])) {
return [
'How do I start a conversation?',
'Who should I contact for academic help?',
'Back to main menu',
];
}

if (_containsAny(q, ['account', 'profile', 'login', 'password', 'otp'])) {
return [
'What if my profile details are incorrect?',
'How do I contact the administrator?',
'Back to main menu',
];
}

if (_containsAny(q, ['teacher', 'lesson', 'teaching', 'class plan'])) {
return [
'Give me lesson planning tips',
'How do I manage my timetable?',
'Back to main menu',
];
}

if (_containsAny(q, ['admin', 'administration', 'manage accounts'])) {
return [
'How do I publish a notice?',
'How do I manage timetable information?',
'Back to main menu',
];
}

return [
'Check attendance',
'View timetable',
'Exam preparation tips',
'Back to main menu',
];
}

Future<String> ask(String prompt, {String role = 'student'}) async {
if (auth.currentUser == null) {
throw StateError('Please sign in to use E-Campus Assistant.');
}

final question = prompt.trim().toLowerCase();
final userRole = role.toLowerCase();

if (question.isEmpty) {
return 'Please enter a question so I can help you.';
}

if (_containsAny(question, [
'back to main menu',
'main menu',
'show options',
'start again',
])) {
return 'Here are the topics I can help you with. Choose an option below.';
}

if (_containsAny(question, [
'hello', 'hi', 'hey', 'good morning', 'good afternoon',
'good evening',
])) {
return 'Hello! 👋 Welcome to E-Campus Assistant.\n\n'
'I can guide you with your ${userRole == 'admin' ? 'administrative' : userRole == 'teacher' ? 'teaching' : 'college'} tasks. '
'Choose a suggested question below or type your own.';
}

if (_containsAny(question, [
'thank', 'thanks', 'you are welcome',
])) {
return 'You are welcome! 😊 I am here to help you use E-Campus.\n\n'
'Would you like help with anything else?';
}

if (_containsAny(question, [
'who are you', 'what can you do', 'features', 'help',
'other questions',
])) {
return 'I am E-Campus Assistant. 👋\n\n'
'I provide guidance based on your account role. '
'Choose one of the suggested topics below to get started.';
}

if (_containsAny(question, [
'attendance', 'present', 'absent', 'percentage',
'attendance record',
])) {
if (userRole == 'student') {
return '📊 Attendance Help\n\n'
'Open the Attendance section in E-Campus to view the records available for your account.\n\n'
'Your percentage depends on the records saved by your college. '
'If a record is missing or incorrect, contact your teacher or college administrator.';
}
if (userRole == 'teacher') {
return '📊 Teacher Attendance Help\n\n'
'Open the Attendance section to access the attendance tools available to your account. '
'Depending on your assigned classes, you may be able to load a roster, mark attendance, '
'and review submitted sessions.\n\n'
'If a class or student is missing, contact your administrator.';
}
return '📊 Administrator Attendance Help\n\n'
'Use the attendance and administration tools available to your account to review college records. '
'If a record is incorrect, follow your college verification procedure.\n\n'
'This assistant does not directly edit attendance records.';
}

if (_containsAny(question, [
'timetable', 'time table', 'schedule', 'lecture',
'class time', 'period',
])) {
return '📅 Timetable Help\n\n'
'Open the Schedule or Timetable section to view the information available to your account.\n\n'
'If a class, lecture, or timing is missing or incorrect, contact your teacher or administrator.';
}

if (_containsAny(question, [
'library', 'book', 'books', 'ebook', 'e-book', 'resource',
])) {
return '📚 Library Help\n\n'
'Open the E-Library section to browse available resources. '
'Select Open when a resource has a link.\n\n'
'For borrowing rules or unavailable books, contact your college librarian.';
}

if (_containsAny(question, [
'exam', 'examination', 'test', 'revision', 'prepare',
'study plan',
])) {
return '📝 Exam Preparation Tips\n\n'
'1. Divide the syllabus into small topics.\n'
'2. Create a realistic daily study timetable.\n'
'3. Practise previous question papers.\n'
'4. Revise important concepts regularly.\n'
'5. Take short breaks and get enough sleep.\n\n'
'Choose a suggested follow-up below for more help.';
}

if (_containsAny(question, [
'study', 'concentrate', 'focus', 'remember', 'learn',
'learning', 'lesson plan', 'teaching',
])) {
return userRole == 'teacher'
? '🎓 Teaching and Lesson Planning\n\n'
'• Set clear learning objectives.\n'
'• Divide lessons into manageable sections.\n'
'• Include examples and short activities.\n'
'• Check understanding with questions.\n'
'• Keep lesson materials organised.'
    : '🎯 Study Tips\n\n'
'• Study in focused sessions of 25–30 minutes.\n'
'• Use active recall instead of only rereading notes.\n'
'• Explain difficult concepts in your own words.\n'
'• Review what you learned at the end of each day.\n'
'• Take short breaks and get enough sleep.';
}

if (_containsAny(question, [
'notice', 'announcement', 'circular', 'event',
])) {
return userRole == 'admin' || userRole == 'teacher'
? '📢 Notices and Announcements\n\n'
'Open the Notices section to view published college updates. '
'If your account has publishing access, use the available notice publishing option.\n\n'
'Always verify the notice details before publishing.'
    : '📢 Notices and Announcements\n\n'
'Open Notices in E-Campus to view published college announcements and updates. '
'For urgent information, confirm it with your college office.';
}

if (_containsAny(question, [
'bus', 'transport', 'route', 'pickup', 'pick up',
])) {
return '🚌 Campus Transport Help\n\n'
'Open Bus information in E-Campus to view published routes, stops, and schedules.\n\n'
'Live GPS tracking is only available if your college has configured a tracking source. '
'Confirm timings with the transport office.';
}

if (_containsAny(question, [
'chat', 'message', 'contact teacher', 'contact admin',
'communication', 'conversation',
])) {
return '💬 Campus Chat Help\n\n'
'Open Campus Chat to view available college contacts and conversations.\n\n'
'Students can contact teachers for academic questions and administrators for app or account issues. '
'Teachers and administrators can use the contacts available to their accounts.';
}

if (_containsAny(question, [
'profile', 'account', 'login', 'sign in', 'password', 'otp',
])) {
return '🔐 Account Help\n\n'
'Open your profile from the More section to view your account information. '
'Use the available profile editing options for permitted details.\n\n'
'Never share your OTP. For role, activation, or account access issues, contact your administrator.';
}

if (_containsAny(question, [
'manage accounts', 'student accounts', 'teacher accounts',
'college administration', 'administrator tools',
])) {
return '🛡️ Administration Help\n\n'
'Open Administrator tools from the More section if this option is available to your account. '
'Use only the actions permitted for your administrator role.\n\n'
'This assistant provides guidance; it does not create accounts or change permissions itself.';
}

return 'Thanks for your question! I may not have a specific answer for that yet.\n\n'
'Choose one of the suggested topics below, or try asking in a different way. '
'For account-specific issues, contact your college teacher or administrator.';
}

bool _containsAny(String text, List<String> keywords) {
return keywords.any(text.contains);
}
}
