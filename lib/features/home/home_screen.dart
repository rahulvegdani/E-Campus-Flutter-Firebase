import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/models/models.dart';
import '../../core/services/data_repository.dart';
import '../../core/theme/app_theme.dart';
import '../screens/attendance_chart.dart';
import '../screens/screens.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(dataRepositoryProvider);
    final isStaff = profile.role == 'teacher' || profile.role == 'admin';

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()}, ${profile.name.trim().isEmpty ? 'there' : profile.name.trim().split(RegExp(r'\s+')).first}',
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              Text(
                profile.role.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () => showSearch(
                context: context,
                delegate: NoticeSearchDelegate(repo, profile),
              ),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.brandSecondary,
                      child: Icon(Icons.school_outlined,
                          color: AppColors.onSurface),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your campus, in one place',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            profile.department.isEmpty
                                ? 'Stay connected to college life.'
                                : '${profile.department} · Semester ${profile.semester}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (isStaff) ...[
                StreamBuilder<List<AttendanceSession>>(
                  stream: repo.teacherSessions(profile.uid),
                  builder: (context, snapshot) {
                    final sessions =
                        snapshot.data ?? const <AttendanceSession>[];
                    return WeeklyAttendanceTrend(sessions: sessions);
                  },
                ),
                const SizedBox(height: 28),
              ],
              Text(
                'Latest notices',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<Notice>>(
                stream: repo.notices(profile),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _MessageCard(
                        message: 'Notices could not be loaded.');
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return const _MessageCard(
                        message: 'No announcements published yet.');
                  }
                  // Keep the Home screen focused on the newest eligible,
                  // published notice. The repository stream updates live when
                  // a teacher or admin publishes a newer notice.
                  final latestNotice = items.first;
                  return _NoticeCard(notice: latestNotice);
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Quick access',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
                children: [
                  _QuickTile(
                    icon: Icons.directions_bus_outlined,
                    label: 'Bus routes',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => BusScreen(profile: profile))),
                  ),
                  _QuickTile(
                    icon: Icons.chat_bubble_outline,
                    label: 'Campus chat',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(profile: profile))),
                  ),
                  _QuickTile(
                    icon: Icons.auto_awesome_outlined,
                    label: 'AI assistant',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AiScreen(profile: profile))),
                  ),
                  _QuickTile(
                    icon: Icons.notifications_none,
                    label: 'Notices',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => NoticesScreen(profile: profile))),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final Notice notice;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(
          backgroundColor: AppColors.brandTertiary,
          child: Icon(Icons.campaign_outlined, color: AppColors.brand),
        ),
        title: Text(
          notice.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${notice.category} · ${notice.authorName}'),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: AppColors.brand),
              Row(children: [
                Expanded(
                    child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                const Icon(Icons.arrow_forward, size: 16)
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message, style: const TextStyle(color: AppColors.muted)),
      ),
    );
  }
}

class NoticeSearchDelegate extends SearchDelegate<Notice?> {
  NoticeSearchDelegate(this.repository, this.profile);
  final DataRepository repository;
  final UserProfile profile;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) {
    return StreamBuilder<List<Notice>>(
      stream: repository.notices(profile),
      builder: (context, snapshot) {
        final q = query.toLowerCase();
        final results = (snapshot.data ?? []).where((n) {
          return n.title.toLowerCase().contains(q) ||
              n.description.toLowerCase().contains(q);
        }).toList();
        return ListView(
          children: results
              .map((n) => ListTile(
              title: Text(n.title),
              subtitle: Text(n.description, maxLines: 2)))
              .toList(),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);
}
