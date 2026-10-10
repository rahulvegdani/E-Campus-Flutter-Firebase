import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../screens/screens.dart';

class AppShell extends StatefulWidget { const AppShell({super.key, required this.profile}); final UserProfile profile; @override State<AppShell> createState() => _AppShellState(); }
class _AppShellState extends State<AppShell> {
  int index = 0;
  @override Widget build(BuildContext context) { final pages = [HomeScreen(profile: widget.profile), TimetableScreen(profile: widget.profile), widget.profile.role == 'teacher' || widget.profile.role == 'admin' ? AttendanceScreen(profile: widget.profile) : StudentAttendanceScreen(profile: widget.profile), LibraryScreen(profile: widget.profile), MoreScreen(profile: widget.profile)]; final labels = ['Home', 'Schedule', 'Attendance', 'Library', 'More']; final icons = [Icons.home_outlined, Icons.calendar_month_outlined, Icons.fact_check_outlined, Icons.local_library_outlined, Icons.more_horiz]; return Scaffold(body: IndexedStack(index: index, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (value) => setState(() => index = value), destinations: List.generate(labels.length, (i) => NavigationDestination(icon: Icon(icons[i]), label: labels[i])))); }
}