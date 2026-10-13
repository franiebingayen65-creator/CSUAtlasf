import 'package:flutter/material.dart';
import 'package:csuatlasf/utils/app_utils.dart';
import 'package:csuatlasf/widgets/admin_ui_kit.dart';


const Map<String, String> kPageTitles = {
  'Dashboard': 'Dashboard',
  'Manage Organization': 'Organizations',
  'Manage GPOA': 'Activity Plan Reviews',
  'Manage Events': 'Event Dates',
  'Manage Users': 'User Accounts',
  'Manage Re-Accreditation': 'Re-Accreditation',
  'Manage Scores': 'Evaluation Scores',
  'Add Scores': 'Evaluation Scores',
  'View Ranks': 'Rankings',
  'GPOA Reports': 'Activity Plan Reports',
  'Accomplishment Reports': 'Accomplishment Reports',
  'Archives': 'Archives',
  'Profile': 'My Profile',
};

class _Nav {
  final String page, label;
  final IconData icon;
  const _Nav(this.page, this.label, this.icon);
}

class _NavGroup {
  final String? title;
  final List<_Nav> items;
  const _NavGroup(this.title, this.items);
}

const _navGroups = <_NavGroup>[
  _NavGroup(null, [_Nav('Dashboard', 'Dashboard', Icons.space_dashboard_rounded)]),
  _NavGroup('Organizations', [
    _Nav('Manage Organization', 'Organizations', Icons.groups_rounded),
    _Nav('Manage GPOA', 'Activity Plan Reviews', Icons.fact_check_rounded),
    _Nav('Manage Events', 'Event Dates', Icons.event_rounded),
    _Nav('Manage Users', 'User Accounts', Icons.manage_accounts_rounded),
    _Nav('Manage Re-Accreditation', 'Re-Accreditation', Icons.sync_rounded),
  ]),
  _NavGroup('Evaluation', [
    _Nav('Manage Scores', 'Evaluation Scores', Icons.rate_review_rounded),
    _Nav('View Ranks', 'Rankings', Icons.emoji_events_rounded),
  ]),
  _NavGroup('Reports', [
    _Nav('GPOA Reports', 'Activity Plan Reports', Icons.print_rounded),
    _Nav('Accomplishment Reports', 'Accomplishment Reports', Icons.assignment_turned_in_rounded),
    _Nav('Archives', 'Archives', Icons.inventory_2_rounded),
  ]),
];

class AdminSidebar extends StatelessWidget {
  final bool isCollapsed;
  final String activePage;
  final ValueChanged<String> onPageSelected;
  final VoidCallback onToggleCollapse;


  final Map<String, int> badges;

  const AdminSidebar({
    super.key,
    required this.isCollapsed,
    required this.activePage,
    required this.onPageSelected,
    required this.onToggleCollapse,
    this.badges = const {},
  });

  bool _isActive(String page) =>
      activePage == page || (page == 'Manage Scores' && activePage == 'Add Scores');

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isCollapsed ? 76 : 264,
      decoration: const BoxDecoration(
        color: UiColors.surface,
        border: Border(right: BorderSide(color: UiColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Row(
              mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Image.asset('assets/images/csulogo.png',
                    width: 36,
                    height: 36,
                    errorBuilder: (c, e, s) => const Icon(Icons.school, color: UiColors.primary, size: 36)),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ATLAS',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: UiColors.text)),
                        Text('Admin Portal', style: TextStyle(fontSize: 12, color: UiColors.muted)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: UiColors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final g in _navGroups) ...[
                  if (g.title != null && !isCollapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
                      child: Text(g.title!.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: UiColors.muted, letterSpacing: 1)),
                    )
                  else if (g.title != null)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
                  for (final n in g.items)
                    _NavTile(
                      nav: n,
                      selected: _isActive(n.page),
                      collapsed: isCollapsed,
                      badge: badges[n.page] ?? 0,
                      onTap: () => onPageSelected(n.page),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: UiColors.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Tooltip(
              message: isCollapsed ? 'Expand menu' : '',
              child: InkWell(
                onTap: onToggleCollapse,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      Icon(isCollapsed ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded,
                          size: 20, color: UiColors.muted),
                      if (!isCollapsed) ...[
                        const SizedBox(width: 12),
                        const Text('Hide menu', style: TextStyle(fontSize: 13, color: UiColors.muted)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _Nav nav;
  final bool selected, collapsed;
  final int badge;
  final VoidCallback onTap;
  const _NavTile({
    required this.nav,
    required this.selected,
    required this.collapsed,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? UiColors.primary : UiColors.muted;
    return Tooltip(
      message: collapsed ? nav.label : '',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? UiColors.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Badge(
                    isLabelVisible: badge > 0 && collapsed,
                    smallSize: 8,
                    child: Icon(nav.icon, size: 20, color: fg),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(nav.label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? UiColors.primary : UiColors.text)),
                    ),
                    if (badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration:
                        BoxDecoration(color: UiColors.warning, borderRadius: BorderRadius.circular(999)),
                        child: Text('$badge',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class AdminTopBar extends StatelessWidget {
  final String activePage;
  final String userName;
  final VoidCallback onLogout, onProfile;
  final Widget notificationButton;

  const AdminTopBar({
    super.key,
    required this.activePage,
    required this.userName,
    required this.onLogout,
    required this.onProfile,
    required this.notificationButton,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: UiColors.surface,
        border: Border(bottom: BorderSide(color: UiColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kPageTitles[activePage] ?? activePage,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: UiColors.text)),
                const Text('Cagayan State University · Student Development & Welfare',
                    style: TextStyle(fontSize: 12, color: UiColors.muted)),
              ],
            ),
          ),
          notificationButton,
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) => v == 'logout' ? onLogout() : onProfile(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'profile',
                  child: Row(children: [Icon(Icons.person_outline_rounded, size: 18), SizedBox(width: 10), Text('My profile')])),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout_rounded, size: 18, color: UiColors.danger),
                    SizedBox(width: 10),
                    Text('Log out', style: TextStyle(color: UiColors.danger)),
                  ])),
            ],
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFFEEF2FF),
                  child: Icon(Icons.person_rounded, size: 20, color: UiColors.primary),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: UiColors.text)),
                    const Text('Administrator', style: TextStyle(fontSize: 11, color: UiColors.muted)),
                  ],
                ),
                const Icon(Icons.expand_more_rounded, color: UiColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class DashboardOverview extends StatelessWidget {
  final ValueChanged<String> onNavigate;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  const DashboardOverview({
    super.key,
    required this.onNavigate,
    required this.activities,
    required this.organizations,
  });

  String _orgName(dynamic id) {
    final m = organizations.firstWhere(
          (o) => o['id']?.toString() == id?.toString(),
      orElse: () => <String, dynamic>{},
    );
    return (m['name'] ?? 'Unknown organization').toString();
  }

  @override
  Widget build(BuildContext context) {
    final active = activities.where((a) => a['is_archived'] != true).toList();
    final now = DateTime.now();

    final today = active.where((a) {
      final raw = a['proposed_date']?.toString() ?? '';
      if (raw.trim().isEmpty) return false;
      try {
        final d = DateTime.parse(raw).toLocal();
        return d.year == now.year && d.month == now.month && d.day == now.day;
      } catch (_) {
        return false;
      }
    }).toList();

    final planReviews = active.where((a) => a['status'] == 'Endorsed').toList();
    final dateReviews = active.where((a) => a['status'] == 'Awaiting Date Approval').toList();
    final needsAction = [...planReviews, ...dateReviews];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1000;

      final stats = [
        StatTile(
          label: 'Organizations',
          value: '${organizations.length}',
          hint: 'Registered in the system',
          icon: Icons.groups_rounded,
          color: UiColors.primary,
          onTap: () => onNavigate('Manage Organization'),
        ),
        StatTile(
          label: 'Waiting for you',
          value: '${needsAction.length}',
          hint: needsAction.isEmpty ? 'You are all caught up' : 'Plans and dates to review',
          icon: Icons.pending_actions_rounded,
          color: UiColors.warning,
          onTap: () => onNavigate(planReviews.isNotEmpty || dateReviews.isEmpty ? 'Manage GPOA' : 'Manage Events'),
        ),
        StatTile(
          label: 'Events today',
          value: '${today.length}',
          hint: today.isEmpty ? 'No events scheduled' : 'Happening on campus',
          icon: Icons.event_available_rounded,
          color: UiColors.success,
          onTap: () => onNavigate('Manage Events|ongoing'),
        ),
      ];

      final left = Column(children: [
        Panel(
          title: 'Needs your action',
          icon: Icons.notifications_active_outlined,
          child: needsAction.isEmpty
              ? const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'Nothing to review right now',
              message: 'New submissions from organizations will show up here.')
              : Column(children: [
            for (final a in needsAction.take(5))
              _ActionRow(
                activity: a,
                orgName: _orgName(a['organization_id']),
                actionLabel: a['status'] == 'Endorsed' ? 'Review plan' : 'Review date',
                onTap: () => onNavigate(a['status'] == 'Endorsed' ? 'Manage GPOA' : 'Manage Events'),
              ),
            if (needsAction.length > 5)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => onNavigate('Manage GPOA'),
                    child: Text('See all ${needsAction.length}')),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        Panel(
          title: 'Happening today',
          icon: Icons.today_rounded,
          child: today.isEmpty
              ? const EmptyState(icon: Icons.event_busy_rounded, title: 'No events today')
              : Column(children: [
            for (final a in today.take(5))
              _ActionRow(
                activity: a,
                orgName: _orgName(a['organization_id']),
                actionLabel: 'Details',
                onTap: () => onNavigate('Manage Events|ongoing|${a['id']}'),
              ),
          ]),
        ),
      ]);

      final right = Panel(
        title: 'Most activities completed',
        icon: Icons.emoji_events_outlined,
        child: _TopOrgs(activities: active, organizations: organizations),
      );

      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Welcome back',
              subtitle: "Here's what needs your attention today.",
            ),
            if (wide)
              Row(children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(child: stats[i]),
                ],
              ])
            else
              Column(children: [for (final s in stats) Padding(padding: const EdgeInsets.only(bottom: 12), child: s)]),
            const SizedBox(height: 24),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: left),
                const SizedBox(width: 20),
                Expanded(child: right),
              ])
            else ...[left, const SizedBox(height: 20), right],
          ],
        ),
      );
    });
  }
}

class _ActionRow extends StatelessWidget {
  final Map<String, dynamic> activity;
  final String orgName, actionLabel;
  final VoidCallback onTap;
  const _ActionRow({
    required this.activity,
    required this.orgName,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final submitted = AppUtils.formatDateTime(activity['created_at']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: UiColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((activity['title'] ?? 'Untitled activity').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: UiColors.text)),
                const SizedBox(height: 2),
                Text('$orgName · Submitted $submitted',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: UiColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusChip(activity['status']?.toString()),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: UiColors.primary,
              side: const BorderSide(color: UiColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _TopOrgs extends StatelessWidget {
  final List<Map<String, dynamic>> activities, organizations;
  const _TopOrgs({required this.activities, required this.organizations});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final a in activities.where((a) => a['status'] == 'Completed')) {
      final id = a['organization_id']?.toString();
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    final ranked = organizations.where((o) => counts.containsKey(o['id'].toString())).toList()
      ..sort((a, b) => counts[b['id'].toString()]!.compareTo(counts[a['id'].toString()]!));

    if (ranked.isEmpty) {
      return const EmptyState(
          icon: Icons.hourglass_empty_rounded,
          title: 'No completed activities yet',
          message: 'Rankings appear after events are completed.');
    }
    return Column(
      children: [
        for (var i = 0; i < ranked.take(5).length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox(
                  width: 24,
                  child: Text('${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: UiColors.muted))),
              Expanded(
                child: Text((ranked[i]['name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: UiColors.text)),
              ),
              Text('${counts[ranked[i]['id'].toString()]} done',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: UiColors.success)),
            ]),
          ),
      ],
    );
  }
}