import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:csuatlasf/utils/app_utils.dart';
import 'package:csuatlasf/widgets/common_ui.dart';
import 'package:csuatlasf/widgets/gpoa_details.dart';
import 'package:csuatlasf/widgets/pdf_preview_dialog.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final _supabase = Supabase.instance.client;
  bool _isSidebarCollapsed = false;
  String _activePage = 'Dashboard';
  bool _isLoading = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _profiles = [];
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscriptions();
    _fetchInitialData();
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _setupRealtimeSubscriptions() {
    _subscriptions.add(_supabase.from('organizations').stream(primaryKey: ['id']).listen((data) {
      if (mounted) {
        setState(() {
          _organizations = List<Map<String, dynamic>>.from(data);
        });
      }
    }));
    _subscriptions.add(_supabase.from('activities').stream(primaryKey: ['id']).listen((data) {
      if (mounted) {
        final now = DateTime.now();
        for (var item in data) {
          if (item['status'] == 'Scheduled' && item['proposed_date'] != null) {
            try {
              final eventDate = DateTime.parse(item['proposed_date'].toString()).toLocal();
              final duration = AppUtils.parseDuration(item['time_frame']);
              if (eventDate.add(duration).isBefore(now)) {
                _supabase.from('activities').update({'status': 'Completed'}).eq('id', item['id']);
              }
            } catch (_) {}
          }
        }
        setState(() {
          _activities = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    }));
    _subscriptions.add(_supabase.from('profiles').stream(primaryKey: ['id']).listen((data) {
      if (mounted) {
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(data);
        });
      }
    }));
  }

  Future<void> _fetchInitialData() async {
    try {
      final orgsData = await _supabase.from('organizations').select();
      final activitiesData = await _supabase.from('activities').select() as List;
      final profilesData = await _supabase.from('profiles').select();
      final now = DateTime.now();
      for (var item in activitiesData) {
        if (item['status'] == 'Scheduled' && item['proposed_date'] != null) {
          try {
            final eventDate = DateTime.parse(item['proposed_date'].toString()).toLocal();
            final duration = AppUtils.parseDuration(item['time_frame']);
            if (eventDate.add(duration).isBefore(now)) {
              await _supabase.from('activities').update({'status': 'Completed'}).eq('id', item['id']);
              item['status'] = 'Completed';
            }
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _organizations = List<Map<String, dynamic>>.from(orgsData);
          _activities = List<Map<String, dynamic>>.from(activitiesData);
          _profiles = List<Map<String, dynamic>>.from(profilesData);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onPageSelected(String page) {
    setState(() { _activePage = page; });
  }

  Future<void> _addOrganization(String name, String type) async {
    try {
      await _supabase.from('organizations').insert({'name': name, 'type': type});
      if (!mounted) {
        return;
      }
      AppUtils.showTopToast(context, 'Organization added successfully!');
      await _fetchInitialData();
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _editOrganization(String id, String name, String type) async {
    try {
      await _supabase.from('organizations').update({'name': name, 'type': type}).eq('id', id);
      if (!mounted) {
        return;
      }
      AppUtils.showTopToast(context, 'Organization updated successfully!');
      await _fetchInitialData();
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _deleteOrganization(String id) async {
    try {
      await _supabase.from('organizations').delete().eq('id', id);
      if (!mounted) {
        return;
      }
      AppUtils.showTopToast(context, 'Organization deleted.');
      await _fetchInitialData();
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await _supabase.auth.signOut();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/');
              }
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Row(
        children: [
          _AdminSidebar(
            isCollapsed: _isSidebarCollapsed,
            activePage: _activePage,
            onPageSelected: _onPageSelected,
            onToggleCollapse: () { setState(() { _isSidebarCollapsed = !_isSidebarCollapsed; }); },
          ),
          Expanded(
            child: Column(
              children: [
                _AdminTopBar(onLogout: _showLogoutDialog, onProfile: () => _onPageSelected('Profile'), onSearch: (q) => setState(() => _searchQuery = q)),
                Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _buildBody())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_activePage) {
      case 'Dashboard': return _DashboardContent(onAction: _onPageSelected, activities: _activities, organizations: _organizations);
      case 'Manage Organization': return _ManageOrganizationsView(organizations: _organizations, activities: _activities, profiles: _profiles, onAddOrganization: _addOrganization, onEditOrganization: _editOrganization, onDeleteOrganization: _deleteOrganization, searchQuery: _searchQuery);
      case 'Manage GPOA': return _ManageGPOAView(organizations: _organizations, activities: _activities, onRefresh: _fetchInitialData);
      case 'Manage Events': return _ManageEventsView(activities: _activities, organizations: _organizations, onRefresh: _fetchInitialData);
      case 'Manage Users': return _ManageUsersView(organizations: _organizations, profiles: _profiles, onRefresh: _fetchInitialData, searchQuery: _searchQuery);
      case 'Manage Re-Accreditation': return const _ManageReAccreditationView();
      case 'Add Scores': return _AddScoresView(activities: _activities, organizations: _organizations, onRefresh: _fetchInitialData);
      case 'Accomplishment Reports': return _AccomplishmentReportsView(activities: _activities, onRefresh: _fetchInitialData);
      case 'GPOA Reports': return _GPOAReportsView(organizations: _organizations, activities: _activities, profiles: _profiles);
      case 'View Ranks': return _RankingsView(organizations: _organizations);
      case 'Profile': return const _ProfileView();
      default: return _DashboardContent(onAction: _onPageSelected, activities: _activities, organizations: _organizations);
    }
  }
}

class _AdminSidebar extends StatelessWidget {
  final bool isCollapsed;
  final String activePage;
  final Function(String) onPageSelected;
  final VoidCallback onToggleCollapse;
  const _AdminSidebar({required this.isCollapsed, required this.activePage, required this.onPageSelected, required this.onToggleCollapse});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isCollapsed ? 80 : 280,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(10, 0))
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Row(
              mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Image.asset('assets/images/csulogo.png', width: 32, height: 32, errorBuilder: (c, e, s) => const Icon(Icons.school, color: Color(0xFF6366F1), size: 32)),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ATLAS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1E293B), letterSpacing: 1)),
                        Text('Admin Dashboard', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF6366F1), letterSpacing: 0.5)),
                      ],
                    ),
                  )
                ]
              ],
            ),
          ),
          const Divider(indent: 24, endIndent: 24, height: 1),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SidebarItem(icon: Icons.dashboard_rounded, title: 'Dashboard', isSelected: activePage == 'Dashboard', isCollapsed: isCollapsed, onTap: () => onPageSelected('Dashboard')),
                  if (!isCollapsed) const _SidebarHeader(title: 'ORGANIZATION MANAGEMENT'),
                  _SidebarItem(icon: Icons.people_outline_rounded, title: 'Manage Organization', isSelected: activePage == 'Manage Organization', isCollapsed: isCollapsed, onTap: () => onPageSelected('Manage Organization')),
                  _SidebarItem(icon: Icons.verified_rounded, title: 'Manage GPOA', isSelected: activePage == 'Manage GPOA', isCollapsed: isCollapsed, onTap: () => onPageSelected('Manage GPOA')),
                  _SidebarItem(icon: Icons.calendar_month_rounded, title: 'Manage Events', isSelected: activePage == 'Manage Events', isCollapsed: isCollapsed, onTap: () => onPageSelected('Manage Events')),
                  _SidebarItem(icon: Icons.manage_accounts_rounded, title: 'Manage Users', isSelected: activePage == 'Manage Users', isCollapsed: isCollapsed, onTap: () => onPageSelected('Manage Users')),
                  _SidebarItem(icon: Icons.sync_rounded, title: 'Manage Re-Accreditation', isSelected: activePage == 'Manage Re-Accreditation', isCollapsed: isCollapsed, onTap: () => onPageSelected('Manage Re-Accreditation')),
                  if (!isCollapsed) const _SidebarHeader(title: 'SCORING & EVALUATION'),
                  _SidebarItem(icon: Icons.score_rounded, title: 'Add Scores', isSelected: activePage == 'Add Scores', isCollapsed: isCollapsed, onTap: () => onPageSelected('Add Scores')),
                  _SidebarItem(icon: Icons.emoji_events_rounded, title: 'View Ranks', isSelected: activePage == 'View Ranks', isCollapsed: isCollapsed, onTap: () => onPageSelected('View Ranks')),
                  if (!isCollapsed) const _SidebarHeader(title: 'REPORTS'),
                  _SidebarItem(icon: Icons.print_rounded, title: 'GPOA Reports', isSelected: activePage == 'GPOA Reports', isCollapsed: isCollapsed, onTap: () => onPageSelected('GPOA Reports')),
                  _SidebarItem(icon: Icons.assignment_rounded, title: 'Accomplishment Reports', isSelected: activePage == 'Accomplishment Reports', isCollapsed: isCollapsed, onTap: () => onPageSelected('Accomplishment Reports')),
                ],
              ),
            ),
          ),
          const Divider(indent: 24, endIndent: 24, height: 1),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Icon(isCollapsed ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded, size: 20, color: Colors.grey[600]),
              title: isCollapsed ? null : Text('Collapse Menu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              onTap: onToggleCollapse,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected, isCollapsed;
  final VoidCallback onTap;
  const _SidebarItem({required this.icon, required this.title, required this.onTap, this.isSelected = false, this.isCollapsed = false});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isCollapsed ? title : '',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : null,
        ),
        child: ListTile(
          leading: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 20),
          title: isCollapsed ? null : Text(title, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF475569), fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final String title;
  const _SidebarHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 16, 12),
      child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1.5)),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  final VoidCallback onLogout, onProfile;
  final Function(String)? onSearch;
  const _AdminTopBar({required this.onLogout, required this.onProfile, this.onSearch});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
              child: TextField(
                onChanged: onSearch,
                decoration: const InputDecoration(
                  hintText: 'Search anything...',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: IconButton(icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B)), onPressed: () {}),
          ),
          const SizedBox(width: 24),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Admin User', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A))),
              Text('System Administrator', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'logout') {
                onLogout();
              }
              if (val == 'profile') {
                onProfile();
              }
            },
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person_outline_rounded, size: 18), SizedBox(width: 12), Text('My Profile')])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout_rounded, size: 18, color: Colors.red), SizedBox(width: 12), Text('Logout', style: TextStyle(color: Colors.red))])),
            ],
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2))),
              child: const CircleAvatar(radius: 20, backgroundColor: Color(0xFFEDE7F6), child: Icon(Icons.person_rounded, size: 22, color: Color(0xFF6366F1))),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final Function(String) onAction;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  const _DashboardContent({required this.onAction, required this.activities, required this.organizations});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayActivities = activities.where((a) {
      if (a['proposed_date'] == null) {
        return false;
      }
      try {
        final date = DateTime.parse(a['proposed_date'].toString()).toLocal();
        return date.year == today.year && date.month == today.month && date.day == today.day;
      } catch (_) { return false; }
    }).toList();
    final pendingAction = activities.where((a) => a['status'] == 'Endorsed' || a['status'] == 'Awaiting Date Approval').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dashboard Overview', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
          const SizedBox(height: 8),
          const Text("Welcome back, System Admin. Here's your system status.", style: TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 48),
          Row(
            children: [
            SummaryCard(title: 'Active Organizations', value: organizations.length.toString(), change: '+12.5%', isPositive: true, icon: Icons.business_rounded, color: const Color(0xFF3B82F6).withValues(alpha: 0.1), iconColor: const Color(0xFF3B82F6), onTap: () => onAction('Manage Organization')),
            const SizedBox(width: 24),
            SummaryCard(title: 'Pending Reviews', value: pendingAction.length.toString(), change: '-28%', isPositive: false, icon: Icons.pending_actions_rounded, color: const Color(0xFFF59E0B).withValues(alpha: 0.1), iconColor: const Color(0xFFF59E0B), onTap: () => onAction('Manage GPOA')),
            const SizedBox(width: 24),
            SummaryCard(title: 'Activities Today', value: todayActivities.length.toString(), change: '+41.7%', isPositive: true, icon: Icons.event_rounded, color: const Color(0xFF10B981).withValues(alpha: 0.1), iconColor: const Color(0xFF10B981), onTap: () => onAction('Manage Events')),
            ],
          ),
          const SizedBox(height: 48),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    _RecentActivitiesList(title: 'Awaiting Approval', activities: pendingAction, organizations: organizations, onAction: onAction, onViewAll: () => onAction('Manage GPOA'), emptyText: 'No pending approvals.', icon: Icons.approval_rounded, iconColor: const Color(0xFFF59E0B)),
                    const SizedBox(height: 48),
                    _RecentActivitiesList(title: 'Live Activities', activities: todayActivities, organizations: organizations, onAction: onAction, onViewAll: () => onAction('Manage Events'), emptyText: 'No activities for today.', icon: Icons.play_circle_rounded, iconColor: const Color(0xFF10B981)),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    _TopOrganizationsCard(activities: activities, organizations: organizations),
                    const SizedBox(height: 32),
                    const _SystemStatusCard(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title, value, change;
  final bool isPositive;
  final IconData icon;
  final Color color, iconColor;
  final VoidCallback onTap;
  const SummaryCard({super.key, required this.title, required this.value, required this.change, required this.isPositive, required this.icon, required this.color, required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))]),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: iconColor, size: 24)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: isPositive ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            Icon(isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 14, color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                            const SizedBox(width: 4),
                            Text(change, style: TextStyle(fontSize: 12, color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentActivitiesList extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  final Function(String) onAction;
  final VoidCallback onViewAll;
  final String emptyText;
  final IconData icon;
  final Color iconColor;
  const _RecentActivitiesList({required this.title, required this.activities, required this.organizations, required this.onAction, required this.onViewAll, this.emptyText = 'Nothing right now.', this.icon = Icons.event_rounded, this.iconColor = const Color(0xFF6366F1)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: iconColor, size: 20)),
                const SizedBox(width: 16),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              TextButton(onPressed: onViewAll, child: const Text('View All', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 32),
          if (activities.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Column(children: [const Icon(Icons.inbox_rounded, size: 40, color: Color(0xFFCBD5E1)), const SizedBox(height: 12), Text(emptyText, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500)) ])))
          else
            ...activities.take(5).map((activity) {
              String displayStatus = activity['status'];
              Color statusColor = const Color(0xFF64748B);
              if (activity['status'] == 'Scheduled') { displayStatus = 'Ongoing'; statusColor = const Color(0xFF10B981); }
              else if (activity['status'] == 'Endorsed') { displayStatus = 'GPOA Review'; statusColor = const Color(0xFFF59E0B); }
              else if (activity['status'] == 'Awaiting Date Approval') { displayStatus = 'Date Review'; statusColor = const Color(0xFF8B5CF6); }
              
              final org = organizations.firstWhere((o) => o['id'] == activity['organization_id']?.toString(), orElse: () => {'name': 'Unknown Org'});
              final String displayDate = activity['status'] == 'Pending' || activity['status'] == 'Endorsed' || activity['status'] == 'Needs Revision'
                  ? 'Submitted: ${AppUtils.formatDateTime(activity['created_at'])}'
                  : 'Event: ${AppUtils.formatDateTime(activity['proposed_date'])}';
              return _ActivityTile(title: activity['title'], orgName: org['name'] ?? 'Unknown Org', subtitle: activity['subtitle'] ?? '', date: displayDate, status: displayStatus, statusColor: statusColor, activityData: activity, onAction: onAction);
            }),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final String title, orgName, subtitle, date, status;
  final Color statusColor;
  final Map<String, dynamic> activityData;
  final Function(String) onAction;
  const _ActivityTile({required this.title, required this.orgName, required this.subtitle, required this.date, required this.status, required this.statusColor, required this.activityData, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF1F5F9))),
      child: InkWell(
        onTap: () {
          final s = activityData['status'].toString();
          if (s == 'Endorsed') { onAction('Manage GPOA'); }
          else if (s == 'Awaiting Date Approval') { onAction('Manage Events'); }
          else {
            showDialog(
              context: context,
              builder: (c) => Dialog(
                child: Container(
                  width: 1000,
                  padding: const EdgeInsets.all(32),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), Text(orgName, style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold))])),
                          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
                        ]),
                        const Divider(height: 32),
                        GPOAActivityDetailsView(
                          title: title,
                          sdgs: activityData['sdgs'] ?? '',
                          objectives: activityData['objectives'] ?? '',
                          outcome: activityData['outcome'] ?? '',
                          participants: activityData['participants'] ?? '',
                          timeFrame: activityData['time_frame'] ?? '',
                          delivery: activityData['delivery_strategy'] ?? '',
                          persons: activityData['persons_involved'] ?? '',
                          facilities: activityData['facilities_materials'] ?? '',
                          budget: activityData['budget_allocation'] ?? '',
                          status: activityData['status'] ?? 'Pending',
                          createdAt: AppUtils.formatDateTime(activityData['created_at']),
                          proposedDate: activityData['proposed_date'] != null ? AppUtils.formatDateTime(activityData['proposed_date']) : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.event_rounded, color: Color(0xFF6366F1), size: 20)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B))), Text('$orgName • $subtitle', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12))])),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(status: activityData['status'] ?? 'Pending'),
                  const SizedBox(height: 6),
                  Text(date, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _TopOrganizationsCard extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  const _TopOrganizationsCard({required this.activities, required this.organizations});

  @override
  Widget build(BuildContext context) {
    final completedCounts = <String, int>{};
    for (var act in activities.where((a) => a['status'] == 'Completed')) {
      final id = act['organization_id'].toString();
      completedCounts[id] = (completedCounts[id] ?? 0) + 1;
    }
    final sortedOrgs = organizations.where((o) => completedCounts.containsKey(o['id'].toString())).toList()
      ..sort((a, b) => completedCounts[b['id'].toString()]!.compareTo(completedCounts[a['id'].toString()]!));

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.stars_rounded, color: Colors.orange, size: 20), SizedBox(width: 12), Text('Top Performing Orgs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
          const SizedBox(height: 24),
          if (sortedOrgs.isEmpty) const Center(child: Text('No completed activities yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)))
          else ...sortedOrgs.take(3).map((org) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  CircleAvatar(radius: 14, backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1), child: const Icon(Icons.business_rounded, size: 16, color: Color(0xFF6366F1))),
                  const SizedBox(width: 12),
                  Text(org['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text('${completedCounts[org['id'].toString()]} DONE', style: const TextStyle(fontSize: 10, color: Color(0xFF3B82F6), fontWeight: FontWeight.w900)),
                )
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('System Status', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _StatusRow(label: 'All Systems', status: 'Operational', color: Colors.green),
          const SizedBox(height: 12),
          _StatusRow(label: 'Database', status: 'Online', color: Colors.blue),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label, status;
  final Color color;
  const _StatusRow({required this.label, required this.status, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [CircleAvatar(radius: 4, backgroundColor: color), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 12))]),
          Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ManageGPOAView extends StatefulWidget {
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;
  const _ManageGPOAView({required this.organizations, required this.activities, required this.onRefresh});
  @override
  State<_ManageGPOAView> createState() => _ManageGPOAViewState();
}

class _ManageGPOAViewState extends State<_ManageGPOAView> {
  String? _selectedOrgId;
  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> orgsToDisplay = _selectedOrgId == null ? widget.organizations : widget.organizations.where((o) => o['id'].toString() == _selectedOrgId).toList();
    final pendingApprovals = widget.activities.where((a) => a['status'] == 'Endorsed' || a['status'] == 'Needs Revision').toList();

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Proposal Review Center', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)), Text('Evaluate and endorse student organization General Plan of Activities (GPOA).', style: TextStyle(color: Color(0xFF64748B), fontSize: 16))]),
                if (_selectedOrgId != null || orgsToDisplay.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)], border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
                    child: DropdownButton<String?>(
                      value: _selectedOrgId,
                      hint: const Text('Filter by Organization'),
                      underline: const SizedBox(),
                      icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF6366F1)),
                      onChanged: (val) => setState(() => _selectedOrgId = val),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Organizations', style: TextStyle(fontWeight: FontWeight.bold))),
                        ...widget.organizations.map((org) => DropdownMenuItem(value: org['id'], child: Text(org['name'] ?? 'Unknown Org'))),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
              child: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF6366F1)),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.notification_important_rounded, size: 18), const SizedBox(width: 8), Text('Action Required (${pendingApprovals.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                  const Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_rounded, size: 18), SizedBox(width: 8), Text('Organizational Archives', style: TextStyle(fontWeight: FontWeight.bold))])),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: TabBarView(
                children: [
                  pendingApprovals.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 48, color: Colors.green), SizedBox(height: 16), Text('All clear! No pending approvals.', style: TextStyle(color: Colors.grey))])) : ListView.builder(
                    itemCount: pendingApprovals.length,
                    itemBuilder: (context, index) {
                      final act = pendingApprovals[index];
                      final org = widget.organizations.firstWhere((o) => o['id'].toString() == act['organization_id']?.toString(), orElse: () => {'name': 'Unknown Org'});
                      return _buildGPOAListTile(act, org);
                    },
                  ),
                  orgsToDisplay.isEmpty ? const Center(child: Text('No organizations found.')) : ListView.builder(
                    itemCount: orgsToDisplay.length,
                    itemBuilder: (context, index) {
                      final org = orgsToDisplay[index];
                      final orgActivities = widget.activities.where((a) => a['organization_id']?.toString() == org['id']).toList();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: const Icon(Icons.business, color: Color(0xFF6366F1)),
                            title: Text(org['name']?.toUpperCase() ?? 'UNKNOWN ORGANIZATION', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), letterSpacing: 0.5)),
                            subtitle: Text('${orgActivities.length} Proposal(s)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            childrenPadding: const EdgeInsets.all(24),
                            children: orgActivities.isEmpty ? [const Center(child: Text('No GPOA proposals submitted.', style: TextStyle(color: Colors.grey, fontSize: 13)))] : orgActivities.map((act) => _buildGPOAListTile(act, org)).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGPOAListTile(Map<String, dynamic> act, Map<String, dynamic> org) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
      child: ListTile(
        leading: const Icon(Icons.description_outlined, color: Color(0xFF6366F1)),
        title: Text(act['title'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${act['status'] ?? 'Pending'}'),
            Text('Submitted: ${AppUtils.formatDateTime(act['created_at'])}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: () => _showGPOADetailsDialog(context, act, org),
      ),
    );
  }

  void _showGPOADetailsDialog(BuildContext context, Map<String, dynamic> act, Map<String, dynamic> org) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 1000,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(act['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), Text(org['name'] ?? 'Unknown Org', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))])),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
              const Divider(height: 32),
              Flexible(
                child: SingleChildScrollView(
                  child: GPOAActivityDetailsView(
                    title: act['title'] ?? '',
                    sdgs: act['sdgs'] ?? '',
                    objectives: act['objectives'] ?? '',
                    outcome: act['outcome'] ?? '',
                    participants: act['participants'] ?? '',
                    timeFrame: act['time_frame'] ?? '',
                    delivery: act['delivery_strategy'] ?? '',
                    persons: act['persons_involved'] ?? '',
                    facilities: act['facilities_materials'] ?? '',
                    budget: act['budget_allocation'] ?? '',
                    status: act['status'] ?? 'Pending',
                    createdAt: AppUtils.formatDateTime(act['created_at']),
                    proposedDate: act['proposed_date'] != null ? AppUtils.formatDateTime(act['proposed_date']) : null,
                    onStatusUpdate: act['status'] == 'Endorsed' ? (s) async {
                      if (s == 'Needs Revision' || s == 'Rejected') {
                        final remarkController = TextEditingController();
                        final isReject = s == 'Rejected';
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(isReject ? 'Reject GPOA' : 'Return for Revision'),
                            content: Column(mainAxisSize: MainAxisSize.min, children: [Text(isReject ? 'Reason for rejection:' : 'Explain changes needed:'), const SizedBox(height: 16), TextField(controller: remarkController, decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder()), maxLines: 4)]),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: isReject ? Colors.red : Colors.orange), child: Text(isReject ? 'Reject' : 'Send Feedback'))],
                          ),
                        );
                        if (confirm != true) return;
                        try {
                          await Supabase.instance.client.from('activities').update({'status': s, 'remarks': remarkController.text}).eq('id', act['id']);
                          if (context.mounted) { AppUtils.showTopToast(context, s == 'Rejected' ? 'Proposal rejected.' : 'Feedback sent.'); Navigator.pop(context); }
                          widget.onRefresh();
                        } catch (e) { if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true); }
                      } else {
                        try {
                          await Supabase.instance.client.from('activities').update({'status': s}).eq('id', act['id']);
                          if (context.mounted) { AppUtils.showTopToast(context, 'Activity approved!'); Navigator.pop(context); }
                          widget.onRefresh();
                        } catch (e) { if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true); }
                      }
                    } : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageOrganizationsView extends StatelessWidget {
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> activities, profiles;
  final Function(String, String) onAddOrganization;
  final Function(String, String, String) onEditOrganization;
  final Function(String) onDeleteOrganization;
  final String searchQuery;
  const _ManageOrganizationsView({required this.organizations, required this.activities, required this.profiles, required this.onAddOrganization, required this.onEditOrganization, required this.onDeleteOrganization, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    final filteredOrgs = organizations.where((o) => (o['name'] ?? '').toLowerCase().contains(searchQuery.toLowerCase())).toList();
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Organizations Management', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)), const SizedBox(height: 4), Text('Overview and control of ${organizations.length} registered student organizations.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 15, fontWeight: FontWeight.w500))]),
              ElevatedButton.icon(
                onPressed: () => _showAddOrgDialog(context),
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: const Text('Register New Organization'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: filteredOrgs.isEmpty ? const Center(child: Text('No organizations found.')) : ListView.builder(
              itemCount: filteredOrgs.length,
              itemBuilder: (c, i) {
                final org = filteredOrgs[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))], border: Border.all(color: const Color(0xFFF1F5F9))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    onTap: () => _showOrgDetailsDialog(context, org),
                    leading: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.business_rounded, color: Color(0xFF6366F1), size: 28)),
                    title: Text(org['name']?.toUpperCase() ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B), letterSpacing: 0.5)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(org['type'] ?? '', style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                          if (org['created_at'] != null)
                            Text('Registered: ${AppUtils.formatDateTime(org['created_at'])}', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                        ],
                      ),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue), onPressed: () => _showEditOrgDialog(context, org)),
                      IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), onPressed: () => _showDeleteConfirm(context, org)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showOrgDetailsDialog(BuildContext context, Map<String, dynamic> org) { showDialog(context: context, builder: (c) => _AdminViewOrgProfileDialog(org: org, activities: activities, profiles: profiles)); }
  void _showAddOrgDialog(BuildContext context) {
    final name = TextEditingController(); String? type;
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Add Organization'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), DropdownButtonFormField<String>(items: ['Specialized Organization', 'College Student Council', 'Campus Student Council'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => type = v, decoration: const InputDecoration(labelText: 'Type'))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (name.text.isNotEmpty && type != null) { onAddOrganization(name.text, type!); Navigator.pop(c); } }, child: const Text('Add'))]));
  }
  void _showEditOrgDialog(BuildContext context, Map<String, dynamic> org) {
    final name = TextEditingController(text: org['name']); String? type = org['type'];
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Edit Organization'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), DropdownButtonFormField<String>(initialValue: type, items: ['Specialized Organization', 'College Student Council', 'Campus Student Council'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => type = v, decoration: const InputDecoration(labelText: 'Type'))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (name.text.isNotEmpty && type != null) { onEditOrganization(org['id']!, name.text, type!); Navigator.pop(c); } }, child: const Text('Save'))]));
  }
  void _showDeleteConfirm(BuildContext context, Map<String, dynamic> org) {
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Delete Organization'), content: Text('Are you sure you want to delete ${org['name']}?'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () { onDeleteOrganization(org['id']!); Navigator.pop(c); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Delete'))]));
  }
}

class _ManageUsersView extends StatelessWidget {
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> profiles;
  final VoidCallback onRefresh;
  final String searchQuery;
  const _ManageUsersView({required this.organizations, required this.profiles, required this.onRefresh, this.searchQuery = ''});

  @override
  Widget build(BuildContext context) {
    final filtered = profiles.where((p) {
      final name = (p['full_name'] ?? '').toLowerCase().contains(searchQuery.toLowerCase());
      final org = organizations.firstWhere((o) => o['id'] == p['organization_id']?.toString(), orElse: () => {'name': ''});
      return name || (org['name'] ?? '').toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('User Accounts', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)), const SizedBox(height: 4), Text('Managing ${profiles.length} portal access accounts.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 15, fontWeight: FontWeight.w500))]),
              ElevatedButton.icon(onPressed: () => _showAddUserDialog(context), icon: const Icon(Icons.person_add_rounded, size: 18), label: const Text('Provision New Account'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: filtered.isEmpty ? const Center(child: Text('No user accounts found.')) : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (c, i) {
                final user = filtered[i];
                final role = user['role'] ?? 'User';
                final org = organizations.firstWhere((o) => o['id'] == user['organization_id']?.toString(), orElse: () => {'name': 'Independent'});
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF1F5F9))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    leading: CircleAvatar(backgroundColor: (role == 'Adviser' ? Colors.indigo : Colors.purple).withValues(alpha: 0.1), child: Icon(role == 'Adviser' ? Icons.verified_user_rounded : Icons.person_rounded, color: role == 'Adviser' ? Colors.indigo : Colors.purple, size: 20)),
                    title: Text(user['full_name'] ?? 'Unknown User', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${user['role']} • ${org['name']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        if (user['created_at'] != null)
                          Text('Provisioned: ${AppUtils.formatDateTime(user['created_at'])}', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                      ],
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_note_rounded, color: Colors.blue), onPressed: () => _showEditUserDialog(context, user)),
                      IconButton(icon: const Icon(Icons.person_remove_rounded, color: Colors.red), onPressed: () => _showDeleteConfirm(context, user)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, Map<String, dynamic> user) {
    final name = TextEditingController(text: user['full_name']); final email = TextEditingController(text: user['email']); String? role = user['role'], orgId = user['organization_id']?.toString();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Edit User'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')), DropdownButtonFormField<String>(initialValue: role, items: ['Adviser', 'President'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => role = v, decoration: const InputDecoration(labelText: 'Role')), DropdownButtonFormField<String>(initialValue: orgId, items: organizations.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['name'] ?? ''))).toList(), onChanged: (v) => orgId = v, decoration: const InputDecoration(labelText: 'Organization'))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () async { try { await Supabase.instance.client.from('profiles').update({'full_name': name.text, 'email': email.text, 'role': role, 'organization_id': orgId}).eq('id', user['id']); onRefresh(); if (c.mounted) { AppUtils.showTopToast(c, 'User updated!'); Navigator.pop(c); } } catch (e) { if (c.mounted) AppUtils.showTopToast(c, 'Error: $e', isError: true); } }, child: const Text('Save'))]));
  }
  void _showDeleteConfirm(BuildContext context, Map<String, dynamic> user) {
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Delete User?'), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () async { try { await Supabase.instance.client.from('profiles').delete().eq('id', user['id']); if (c.mounted) { AppUtils.showTopToast(c, 'User deleted.'); Navigator.pop(c); onRefresh(); } } catch (e) { if (c.mounted) AppUtils.showTopToast(c, 'Error: $e', isError: true); } }, child: const Text('Delete'))]));
  }
  void _showAddUserDialog(BuildContext context) {
    final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController(); String? role, orgId;
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Add User'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')), TextField(controller: pass, decoration: const InputDecoration(labelText: 'Password'), obscureText: true), DropdownButtonFormField<String>(items: ['Adviser', 'President'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => role = v, decoration: const InputDecoration(labelText: 'Role')), DropdownButtonFormField<String>(items: organizations.map((e) => DropdownMenuItem(value: e['id'].toString(), child: Text(e['name'] ?? ''))).toList(), onChanged: (v) => orgId = v, decoration: const InputDecoration(labelText: 'Organization'))]), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), ElevatedButton(onPressed: () async { try { if (name.text.isEmpty || email.text.isEmpty || role == null || orgId == null) return; final resp = await Supabase.instance.client.auth.signUp(email: email.text, password: pass.text, data: {'full_name': name.text}); if (resp.user != null) { await Supabase.instance.client.from('profiles').insert({'id': resp.user!.id, 'full_name': name.text, 'email': email.text, 'role': role, 'organization_id': orgId}); onRefresh(); if (c.mounted) { AppUtils.showTopToast(c, 'User added!'); Navigator.pop(c); } } } catch (e) { if (c.mounted) AppUtils.showTopToast(c, 'Error: $e', isError: true); } }, child: const Text('Add'))]));
  }
}

class _ManageEventsView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  final VoidCallback onRefresh;
  const _ManageEventsView({required this.activities, required this.organizations, required this.onRefresh});
  @override
  State<_ManageEventsView> createState() => _ManageEventsViewState();
}

class _ManageEventsViewState extends State<_ManageEventsView> {
  String? _selectedOrgId;
  @override
  Widget build(BuildContext context) {
    final awaiting = widget.activities.where((a) => a['status'] == 'Awaiting Date Approval').toList();
    final List<Map<String, dynamic>> orgsToDisplay = _selectedOrgId == null 
        ? widget.organizations 
        : widget.organizations.where((o) => o['id'].toString() == _selectedOrgId).toList();

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Event Scheduling', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                    Text('Manage proposed event dates and oversee activity timelines.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                  ),
                  child: DropdownButton<String?>(
                    value: _selectedOrgId,
                    hint: const Text('Filter by Organization'),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.filter_list_rounded, color: Color(0xFF6366F1)),
                    onChanged: (val) => setState(() => _selectedOrgId = val),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Organizations', style: TextStyle(fontWeight: FontWeight.bold))),
                      ...widget.organizations.map((org) => DropdownMenuItem(value: org['id'].toString(), child: Text(org['name'] ?? ''))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
              ),
              child: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF6366F1)),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.pending_actions_rounded, size: 18), const SizedBox(width: 8), Text('Awaiting Approval (${awaiting.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                  const Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_month_rounded, size: 18), SizedBox(width: 8), Text('Organizations Schedule', style: TextStyle(fontWeight: FontWeight.bold))])),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Immediate actions
                  awaiting.isEmpty 
                      ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green), SizedBox(height: 16), Text('All event dates are approved.', style: TextStyle(color: Colors.grey))])) 
                      : ListView.builder(
                          itemCount: awaiting.length,
                          itemBuilder: (context, index) {
                            final act = awaiting[index];
                            final org = widget.organizations.firstWhere((o) => o['id'].toString() == act['organization_id']?.toString(), orElse: () => {'name': 'Unknown Org'});
                            return _buildEventCard(context, act, org);
                          },
                        ),
                  // Tab 2: Organization-based groupings
                  ListView.builder(
                    itemCount: orgsToDisplay.length,
                    itemBuilder: (context, index) {
                      final org = orgsToDisplay[index];
                      final orgActs = widget.activities.where((a) => a['organization_id']?.toString() == org['id'].toString() && ['Approved', 'Scheduled', 'Completed', 'Awaiting Date Approval', 'Needs Revision'].contains(a['status'])).toList();
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: const Icon(Icons.business_rounded, color: Color(0xFF6366F1)),
                            title: Text(org['name']?.toUpperCase() ?? 'UNKNOWN', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), letterSpacing: 0.5)),
                            subtitle: Text('${orgActs.length} Event(s) tracked', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            childrenPadding: const EdgeInsets.all(24),
                            children: orgActs.isEmpty 
                                ? [const Padding(padding: EdgeInsets.all(16), child: Text('No events currently tracking.', style: TextStyle(color: Colors.grey, fontSize: 13)))] 
                                : orgActs.map((act) => _buildEventCard(context, act, org)).toList(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Map<String, dynamic> act, Map<String, dynamic> org) {
    final status = act['status'];
    final bool isAwaiting = status == 'Awaiting Date Approval';
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isAwaiting ? const Color(0xFF6366F1).withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1), width: isAwaiting ? 1.5 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (status == 'Scheduled' ? Colors.green : (isAwaiting ? const Color(0xFF6366F1) : Colors.orange)).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            status == 'Scheduled' ? Icons.event_available_rounded : Icons.event_rounded,
            color: status == 'Scheduled' ? Colors.green : (isAwaiting ? const Color(0xFF6366F1) : Colors.orange),
          ),
        ),
        title: Text(act['title'] ?? 'Untitled Activity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                StatusBadge(status: status),
                const SizedBox(width: 8),
                const Icon(Icons.access_time_rounded, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(AppUtils.formatDateTime(act['proposed_date']), style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
        trailing: isAwaiting 
            ? ElevatedButton(
                onPressed: () => _showEventDetails(context, act, org),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, elevation: 0),
                child: const Text('Review Date'),
              )
            : const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
        onTap: () => _showEventDetails(context, act, org),
      ),
    );
  }

  void _showEventDetails(BuildContext context, Map<String, dynamic> act, Map<String, dynamic> org) {
    showDialog(
      context: context, 
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          width: 1000, 
          padding: const EdgeInsets.all(32), 
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(act['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                        Text(org['name'] ?? 'Unknown Org', style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx), 
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFFF8FAFC)),
                  ),
                ],
              ),
              const Divider(height: 48, color: Color(0xFFF1F5F9)),
              if (act['status'] == 'Awaiting Date Approval')
                Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 32),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.calendar_today_rounded, color: Color(0xFF6366F1)),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PROPOSED DATE & TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(AppUtils.formatDateTime(act['proposed_date']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Approve Event Date'),
                              content: const Text('Are you sure you want to approve this schedule? The organization will be notified.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                  child: const Text('Confirm Approval'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              await Supabase.instance.client.from('activities').update({'status': 'Scheduled'}).eq('id', act['id']);
                              if (ctx.mounted) {
                                AppUtils.showTopToast(ctx, 'Event date approved successfully!');
                                Navigator.pop(ctx);
                              }
                              widget.onRefresh();
                            } catch (e) {
                              if (ctx.mounted) AppUtils.showTopToast(ctx, 'Error: $e', isError: true);
                            }
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: const Text('Approve Date'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final remarkController = TextEditingController();
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (rtx) => AlertDialog(
                              title: const Text('Request Reschedule'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Explain why this date cannot be approved:'),
                                  const SizedBox(height: 16),
                                  TextField(controller: remarkController, decoration: const InputDecoration(labelText: 'Feedback for Organization', border: OutlineInputBorder()), maxLines: 3),
                                ],
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(rtx, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(rtx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                  child: const Text('Send Feedback'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              await Supabase.instance.client.from('activities').update({'status': 'Needs Revision', 'remarks': remarkController.text}).eq('id', act['id']);
                              if (ctx.mounted) {
                                AppUtils.showTopToast(ctx, 'Reschedule request sent.');
                                Navigator.pop(ctx);
                              }
                              widget.onRefresh();
                            } catch (e) {
                              if (ctx.mounted) AppUtils.showTopToast(ctx, 'Error: $e', isError: true);
                            }
                          }
                        },
                        icon: const Icon(Icons.history_edu_rounded, size: 18),
                        label: const Text('Reject Date'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: GPOAActivityDetailsView(
                    title: act['title'] ?? '',
                    sdgs: act['sdgs'] ?? '',
                    objectives: act['objectives'] ?? '',
                    outcome: act['outcome'] ?? '',
                    participants: act['participants'] ?? '',
                    timeFrame: act['time_frame'] ?? '',
                    delivery: act['delivery_strategy'] ?? '',
                    persons: act['persons_involved'] ?? '',
                    facilities: act['facilities_materials'] ?? '',
                    budget: act['budget_allocation'] ?? '',
                    status: act['status'] ?? 'Pending',
                    createdAt: AppUtils.formatDateTime(act['created_at']),
                    proposedDate: act['proposed_date'] != null ? AppUtils.formatDateTime(act['proposed_date']) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccomplishmentReportsView extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;
  const _AccomplishmentReportsView({required this.activities, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final reportReady = activities.where((a) => ['Completed', 'Scheduled'].contains(a['status'])).toList();

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Accomplishment Reports', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
          const Text('Review and approve accomplishment reports submitted by organizations.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
          const SizedBox(height: 40),
          Expanded(
            child: reportReady.isEmpty
                ? const Center(child: Text('No activities currently require reports.'))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 24,
                      mainAxisSpacing: 24,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: reportReady.length,
                    itemBuilder: (context, index) {
                      final act = reportReady[index];
                      final hasReport = act['report_url'] != null;
                      final isApproved = act['report_status'] == 'Approved';

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (isApproved ? Colors.green : (hasReport ? Colors.blue : Colors.orange)).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isApproved ? Icons.verified_rounded : (hasReport ? Icons.file_present_rounded : Icons.pending_actions_rounded),
                                      size: 16,
                                      color: isApproved ? Colors.green : (hasReport ? Colors.blue : Colors.orange),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (hasReport)
                                    StatusBadge(status: act['report_status'] ?? 'Submitted'),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(act['title'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const Spacer(),
                              if (hasReport)
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _viewReport(act['report_url']),
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF8FAFC), foregroundColor: const Color(0xFF1E293B), elevation: 0),
                                        child: const Text('View File'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isApproved)
                                      IconButton(
                                        onPressed: () => _approveReport(context, act['id']),
                                        icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
                                        tooltip: 'Approve Report',
                                      ),
                                  ],
                                )
                              else
                                const Text('Waiting for submission...', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _viewReport(dynamic url) async {
    if (url == null) return;
    final uri = Uri.parse(url.toString());
    try {
      // ignore: deprecated_member_use
      if (await canLaunchUrl(uri)) {
        // ignore: deprecated_member_use
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _approveReport(BuildContext context, dynamic id) async {
    try {
      await Supabase.instance.client.from('activities').update({'report_status': 'Approved'}).eq('id', id);
      if (context.mounted) {
        AppUtils.showTopToast(context, 'Report approved successfully!');
      }
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        AppUtils.showTopToast(context, 'Error: $e', isError: true);
      }
    }
  }
}

class _AddScoresView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  final VoidCallback onRefresh;
  const _AddScoresView({required this.activities, required this.organizations, required this.onRefresh});

  @override
  State<_AddScoresView> createState() => _AddScoresViewState();
}

class _AddScoresViewState extends State<_AddScoresView> {
  String? _selectedOrgId;
  final String _schoolYear = '2025-2026';
  bool _isSaving = false;

  final Map<String, TextEditingController> _controllers = {
    'i': TextEditingController(text: '0'),
    'ii': TextEditingController(text: '0'),
    'iii': TextEditingController(text: '0'),
    'iv': TextEditingController(text: '0'),
    'v': TextEditingController(text: '0'),
    'vi': TextEditingController(text: '0'),
    'vii': TextEditingController(text: '0'),
    'viii': TextEditingController(text: '0'),
    'ix': TextEditingController(text: '0'),
    'x': TextEditingController(text: '0'),
  };

  double get grandTotal {
    double total = 0;
    _controllers.forEach((key, controller) {
      total += double.tryParse(controller.text) ?? 0;
    });
    return total;
  }

  String get adjectivalRating {
    double total = grandTotal;
    if (total >= 96) return 'Outstanding';
    if (total >= 86) return 'Very Satisfactory';
    if (total >= 76) return 'Satisfactory';
    if (total >= 66) return 'Fair';
    return 'Poor';
  }

  @override
  void initState() {
    super.initState();
    for (var controller in _controllers.values) {
      controller.addListener(() { if (mounted) setState(() {}); });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEvaluation() async {
    if (_selectedOrgId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('organization_evaluations')
          .select()
          .eq('organization_id', _selectedOrgId!)
          .eq('school_year', _schoolYear)
          .maybeSingle();

      if (res != null) {
        setState(() {
          _controllers['i']!.text = (res['score_i'] ?? 0).toString();
          _controllers['ii']!.text = (res['score_ii'] ?? 0).toString();
          _controllers['iii']!.text = (res['score_iii'] ?? 0).toString();
          _controllers['iv']!.text = (res['score_iv'] ?? 0).toString();
          _controllers['v']!.text = (res['score_v'] ?? 0).toString();
          _controllers['vi']!.text = (res['score_vi'] ?? 0).toString();
          _controllers['vii']!.text = (res['score_vii'] ?? 0).toString();
          _controllers['viii']!.text = (res['score_viii'] ?? 0).toString();
          _controllers['ix']!.text = (res['score_ix'] ?? 0).toString();
          _controllers['x']!.text = (res['score_x'] ?? 0).toString();
        });
      } else {
        setState(() {
          for (var c in _controllers.values) { c.text = '0'; }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEvaluation() async {
    if (_selectedOrgId == null) {
      AppUtils.showTopToast(context, 'Please select an organization first.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final data = {
        'organization_id': _selectedOrgId,
        'school_year': _schoolYear,
        'score_i': double.tryParse(_controllers['i']!.text) ?? 0,
        'score_ii': double.tryParse(_controllers['ii']!.text) ?? 0,
        'score_iii': double.tryParse(_controllers['iii']!.text) ?? 0,
        'score_iv': double.tryParse(_controllers['iv']!.text) ?? 0,
        'score_v': double.tryParse(_controllers['v']!.text) ?? 0,
        'score_vi': double.tryParse(_controllers['vi']!.text) ?? 0,
        'score_vii': double.tryParse(_controllers['vii']!.text) ?? 0,
        'score_viii': double.tryParse(_controllers['viii']!.text) ?? 0,
        'score_ix': double.tryParse(_controllers['ix']!.text) ?? 0,
        'score_x': double.tryParse(_controllers['x']!.text) ?? 0,
        'grand_total': grandTotal,
        'adjectival_rating': adjectivalRating,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client.from('organization_evaluations').upsert(data, onConflict: 'organization_id,school_year');
      if (mounted) {
        AppUtils.showTopToast(context, 'Evaluation record updated successfully!');
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            _buildTopPanel(),
            const SizedBox(height: 32),
            _buildFolioPage(1, _buildPage1Content()),
            const SizedBox(height: 40),
            _buildFolioPage(2, _buildPage2Content()),
            const SizedBox(height: 40),
            _buildFolioPage(3, _buildPage3Content()),
            const SizedBox(height: 40),
            _buildFolioPage(4, _buildPage4Content()),
            const SizedBox(height: 40),
            _buildFolioPage(5, _buildPage5Content()),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      width: 850,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: Color(0xFF6366F1), size: 28),
          const SizedBox(width: 16),
          const Text('CSC EVALUATION PANEL', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
          const SizedBox(width: 40),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedOrgId,
              hint: const Text('Select Organization'),
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
              items: widget.organizations.map((o) => DropdownMenuItem(value: o['id'].toString(), child: Text(o['name'] ?? '', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (val) { setState(() => _selectedOrgId = val); _loadEvaluation(); },
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveEvaluation,
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
            label: const Text('Commit Record'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ),
    );
  }

  Widget _buildFolioPage(int num, Widget content) {
    return Container(
      width: 850,
      constraints: const BoxConstraints(minHeight: 1300),
      padding: const EdgeInsets.all(60),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFolioHeader(),
          const SizedBox(height: 30),
          content,
          const SizedBox(height: 60),
          const Divider(color: Colors.black, thickness: 1.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$num | P a g e', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              const Text('Search for the Most Outstanding College Student Council Organization SY 2025-2026', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFolioHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset('assets/images/csulogo.png', height: 80, errorBuilder: (c, e, s) => const Icon(Icons.school, size: 80, color: Colors.red)),
        const SizedBox(width: 15),
        const SizedBox(
          width: 485,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('REPUBLIC OF THE PHILIPPINES', style: TextStyle(fontSize: 10, color: Color(0xFFB71C1C), fontWeight: FontWeight.bold)),
              Text('CAGAYAN STATE UNIVERSITY', style: TextStyle(fontSize: 16, color: Color(0xFFB71C1C), fontWeight: FontWeight.w900)),
              Text('ANDREWS CAMPUS', style: TextStyle(fontSize: 12, color: Color(0xFFB71C1C), fontWeight: FontWeight.bold)),
              Text('Caritan, Tuguegarao City, Cagayan', style: TextStyle(fontSize: 10, color: Color(0xFFB71C1C))),
            ],
          ),
        ),
        const SizedBox(width: 15),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Email Address: osdw@csu.edu.ph', style: TextStyle(fontSize: 9)),
            Text('Website: www.csu.edu.ph', style: TextStyle(fontSize: 9)),
            Text('Facebook Page: Osdw Andrews', style: TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );
  }

  Widget _buildPage1Content() {
    final org = widget.organizations.firstWhere((o) => o['id'].toString() == _selectedOrgId, orElse: () => {'name': '________________'});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: Column(
            children: [
              Text('OFFICE OF STUDENT DEVELOPMENT AND WELFARE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, decoration: TextDecoration.underline)),
              SizedBox(height: 4),
              Text('CRITERIA FOR THE SEARCH FOR OUTSTANDING COLLEGE STUDENT COUNCIL SY 2025-2026', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5)),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            SizedBox(width: 350, child: _buildInfoField('Organization:', org['name'].toString().toUpperCase())),
            const SizedBox(width: 20),
            SizedBox(width: 350, child: _buildInfoField('Points:', grandTotal.toStringAsFixed(2))),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 350, child: _buildInfoField('Campus:', 'ANDREWS CAMPUS')),
            const SizedBox(width: 20),
            SizedBox(width: 350, child: _buildInfoField('Adjectival Rating:', adjectivalRating.toUpperCase())),
          ],
        ),
        const SizedBox(height: 40),
        const Center(child: Text('I. & II. ACTIVITIES CONDUCTED / SPONSORED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline))),
        const SizedBox(height: 25),
        _buildPage1Matrix(),
      ],
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(width: 10),
          Container(width: 200, padding: const EdgeInsets.only(bottom: 2), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black))), child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildPage1Matrix() {
    return Table(
      border: TableBorder.all(color: Colors.black),
      columnWidths: const {
        0: FixedColumnWidth(130),
        1: FixedColumnWidth(110),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1),
        7: FlexColumnWidth(1),
        8: FixedColumnWidth(70),
      },
      children: [
        _buildMatrixIAndIIHeader(),
        _buildMatrixCriteriaRow(['3', '2.5'], ['3', '2.5'], ['5', '2.5'], ['5', '2.0'], ['5', '1.5'], ['7', '2.5']),
        _buildMatrixCriteriaRow(['2', '2.0'], ['2', '2.0'], ['4', '2.0'], ['4', '1.5'], ['4', '1.0'], ['6', '2.0']),
        _buildMatrixCriteriaRow(['1', '1.5'], ['1', '1.5'], ['3', '1.5'], ['3', '1.0'], ['3', '0.5'], ['5', '1.5']),
        TableRow(
          children: [
            const TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Text('Note: Attendance should be 50%+1 of the total target participants.', style: TextStyle(fontSize: 7.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(),
          ],
        ),
        _buildMatrixActivityRow('I. Symposium/ Seminars Conducted (10 pts)\nMax Activities: 4', 'i'),
        _buildMatrixActivityRow('II. Convocations/ Programs and Literary Activities (10 pts)\nMax Activities: 4', 'ii'),
      ],
    );
  }

  TableRow _buildMatrixIAndIIHeader() {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      children: [
        const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Text('Activities', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)))),
        const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Text('Supporting Docs', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)))),
        for (final l in ['Int\'l', 'Nat\'l', 'Reg\'l', 'Univ', 'Camp', 'Coll'])
          TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Column(children: [
            Center(child: Padding(padding: const EdgeInsets.all(2), child: Text(l, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)))),
            const Divider(height: 1, color: Colors.black),
            Row(children: [
              SizedBox(width: 30, child: Center(child: Text('No. of SDGs', style: const TextStyle(fontSize: 5, fontWeight: FontWeight.bold)))),
              Container(width: 1, height: 10, color: Colors.black),
              SizedBox(width: 20, child: Center(child: Text('Pts', style: const TextStyle(fontSize: 5, fontWeight: FontWeight.bold)))),
            ])
          ])),
        const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Text('Pts', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)))),
      ],
    );
  }

  TableRow _buildMatrixCriteriaRow(List<String> l1, List<String> l2, List<String> l3, List<String> l4, List<String> l5, List<String> l6) {
    return TableRow(
      children: [
        const SizedBox(), const SizedBox(),
        for (final pair in [l1, l2, l3, l4, l5, l6])
          Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            SizedBox(width: 25, child: Center(child: Text(pair[0], style: const TextStyle(fontSize: 7.5)))),
            Container(width: 0.5, height: 10, color: Colors.black26),
            SizedBox(width: 20, child: Center(child: Text(pair[1], style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold)))),
          ]))),
        const SizedBox(),
      ],
    );
  }

  TableRow _buildMatrixActivityRow(String title, String key) {
    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
        const Padding(padding: EdgeInsets.all(8), child: Text('• Approved letter\n• Narrative Report\n• Attendance Sheet\n• Program/ Invitation', style: TextStyle(fontSize: 7.5))),
        for (var i = 0; i < 6; i++)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: SizedBox(
              height: 70,
              child: Row(
                children: [
                  Container(width: 25, decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black54, width: 0.5)))),
                  const SizedBox(width: 25),
                ],
              ),
            ),
          ),
        TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(key)),
      ],
    );
  }

  Widget _buildPage2Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(child: Text('III, IV, V, & VI. CATEGORICAL EVALUATION MATRIX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline))),
        const SizedBox(height: 25),
        _buildCategoricalMatrix(),
        const SizedBox(height: 20),
        const Text('Note: Every activity must be anchored to at least one (1) SDG.', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCategoricalMatrix() {
    return Table(
      border: TableBorder.all(color: Colors.black),
      columnWidths: const {
        0: FixedColumnWidth(130),
        1: FixedColumnWidth(110),
        2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
        4: FlexColumnWidth(1), 5: FlexColumnWidth(1),
        6: FlexColumnWidth(1), 7: FlexColumnWidth(1),
        8: FixedColumnWidth(70),
      },
      children: [
        _buildMatrixIAndIIHeader(),
        _buildCategoricalRow('III. Religious Activities (5 pts)\nMax Activities: 3', 'Approved Letter, Narrative Report, Certification from Parish Priest/ Minister', 'iii'),
        _buildCategoricalRow('IV. Socio-Cultural and Sports Activities (10 pts)\nMax Activities: 4', 'Approved Letter, Narrative Report, Pictorials, Result of Competition', 'iv'),
        _buildCategoricalRow('V. Maka-kalikasan/ Clean and Green Activities (10 pts)\nMax Activities: 4', 'Office Order, MOA/MOU, Certification from Barangay/ Agency', 'v'),
        _buildCategoricalRow('VI. Extension Services Sponsored/ Conducted (10 pts)\nMax Activities: 4', 'Approved Letter, Certification from Recipient/ Agency, Narrative Report', 'vi'),
      ],
    );
  }

  TableRow _buildCategoricalRow(String title, String docs, String key) {
    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(6), child: Text(title, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(6), child: Text(docs, style: const TextStyle(fontSize: 7))),
        for (var i = 0; i < 6; i++)
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: SizedBox(
              height: 70,
              child: Row(
                children: [
                  Container(width: 25, decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black54, width: 0.5)))),
                  const SizedBox(width: 25),
                ],
              ),
            ),
          ),
        TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(key)),
      ],
    );
  }

  Widget _buildPage3Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('VII. Tangible/ Physical Projects (15 pts)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const Text('• Accumulated amount. CSC office equipment alone not credited.', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
        const SizedBox(height: 15),
        _buildMappingTable([
          ['140,001 and above', '15.0'], ['130,001 - 140,000', '14.0'],
          ['120,001 - 130,000', '13.0'], ['110,001 - 120,000', '12.0'],
          ['100,001 - 110,000', '11.0'], ['90,001 - 100,000', '10.0'],
          ['80,001 - 90,000', '9.0'], ['70,001 - 80,000', '8.0'],
          ['60,001 - 70,000', '7.0'], ['50,001 - 60,000', '6.0'],
          ['40,001 - 50,000', '5.0'], ['30,001 - 40,000', '4.0'],
          ['20,001 - 30,000', '3.0'], ['10,001 - 20,000', '2.0'],
          ['Below 10,000', '1.0'],
        ], scoreKey: 'vii'),
        const SizedBox(height: 40),
        const Text('VIII. Fund Drive/ IGP (10 pts)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 15),
        _buildMappingTable([
          ['20,001 and above', '10.0'], ['15,001 - 20,000', '8.0'],
          ['10,001 - 15,000', '6.0'], ['5,001 - 10,000', '4.0'],
          ['Below 5,000', '2.0'],
        ], scoreKey: 'viii'),
      ],
    );
  }

  Widget _buildPage4Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('IX. Financial Assistance (10 pts)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 15),
        _buildMappingTable([
          ['10,001 and above', '10.0'], ['7,501 - 10,000', '8.0'],
          ['5,001 - 7,500', '6.0'], ['2,501 - 5,000', '4.0'],
          ['Below 2,500', '2.0'],
        ], scoreKey: 'ix'),
        const SizedBox(height: 40),
        const Text('X. Action Plan Implementation (10 pts)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 15),
        _buildMappingTable([
          ['94% - 100%', '10.0'], ['84% - 93%', '8.0'],
          ['74% - 83%', '6.0'], ['64% - 73%', '4.0'],
          ['Below 64%', '2.0'],
        ], scoreKey: 'x'),
        const SizedBox(height: 50),
        const Center(child: Text('FINAL SCORE SUMMARY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2))),
        const SizedBox(height: 25),
        _buildFinalSummaryTable(),
        const SizedBox(height: 40),
        _buildGrandTotalRow(),
      ],
    );
  }

  Widget _buildFinalSummaryTable() {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 2),
      columnWidths: const {0: FlexColumnWidth(4), 1: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade300),
          children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('SUB-CATEGORIES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1))),
            const Center(child: Padding(padding: EdgeInsets.all(12), child: Text('SCORE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
          ],
        ),
        ...[
          ['I. Symposium/ Seminars Conducted', 'i'],
          ['II. Convocations/ Programs and Literary Activities', 'ii'],
          ['III. Religious Activities', 'iii'],
          ['IV. Socio-Cultural and Sports Activities', 'iv'],
          ['V. Maka-kalikasan/ Clean and Green Activities', 'v'],
          ['VI. Extension Services Sponsored/ Conducted', 'vi'],
          ['VII. Tangible/ Physical Projects', 'vii'],
          ['VIII. Fund Drive/ IGP', 'viii'],
          ['IX. Financial Assistance', 'ix'],
          ['X. Action Plan Implementation', 'x'],
        ].map((s) => TableRow(children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(s[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
          TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(s[1])),
        ])),
      ],
    );
  }

  Widget _buildGrandTotalRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text('Grand Total Score Achieved:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(width: 20),
        Container(
          width: 150,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black, width: 2))),
          child: Center(child: Text(grandTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF6366F1)))),
        ),
      ],
    );
  }

  Widget _buildPage5Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 60),
        const Text('Certified True and Correct:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 80),
        _buildSignatureGrid(),
        const SizedBox(height: 120),
        const Text('Noted:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 80),
        _buildNotedBlock(),
      ],
    );
  }

  Widget _buildSignatureGrid() {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: 330, child: _buildSignatureLine()),
            const SizedBox(width: 60),
            SizedBox(width: 330, child: _buildSignatureLine()),
          ],
        ),
        const SizedBox(height: 80),
        Row(
          children: [
            SizedBox(width: 330, child: _buildSignatureLine()),
            const SizedBox(width: 60),
            SizedBox(width: 330, child: _buildSignatureLine()),
          ],
        ),
      ],
    );
  }

  Widget _buildNotedBlock() {
    return const Center(
      child: Column(
        children: [
          Text('LORAINE SUYU-TATTAO, Ph.D.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, decoration: TextDecoration.underline, letterSpacing: 0.5)),
          Text('University Director', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text('Office of the Student Development and Welfare', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMappingTable(List<List<String>> rows, {String? scoreKey}) {
    return Table(
      border: TableBorder.all(color: Colors.black),
      columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Amount / Range / Percentage', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
            const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Points', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
          ],
        ),
        ...rows.map((r) => TableRow(children: [
          Center(child: Padding(padding: const EdgeInsets.all(6), child: Text(r[0], style: const TextStyle(fontSize: 9)))),
          Center(child: Padding(padding: const EdgeInsets.all(6), child: Text(r[1], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
        ])),
        if (scoreKey != null)
          TableRow(
            decoration: BoxDecoration(color: Colors.blue.shade50),
            children: [
              const Padding(padding: EdgeInsets.all(10), child: Text('Actual Score achieved based on rubric:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(scoreKey)),
            ],
          ),
      ],
    );
  }

  Widget _buildIntegratedInput(String key) {
    return TextField(
      controller: _controllers[key],
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF6366F1)),
      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
    );
  }

  Widget _buildSignatureLine() {
    return Column(
      children: [
        Container(height: 1.5, color: Colors.black),
        const SizedBox(height: 6),
        const Text('Signature over Printed Name of Evaluator', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
      ],
    );
  }
}


class GuideItem extends StatelessWidget {
  final String label, desc;
  const GuideItem({super.key, required this.label, required this.desc});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))), Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)))]));
  }
}

class _ManageReAccreditationView extends StatelessWidget {
  const _ManageReAccreditationView();
  @override
  Widget build(BuildContext context) { return const Center(child: Text('Re-Accreditation coming soon.')); }
}

class _RankingsView extends StatefulWidget {
  final List<Map<String, dynamic>> organizations;
  const _RankingsView({required this.organizations});

  @override
  State<_RankingsView> createState() => _RankingsViewState();
}

class _RankingsViewState extends State<_RankingsView> {
  String _schoolYear = '2025-2026';
  List<Map<String, dynamic>> _evaluations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRankings();
  }

  Future<void> _fetchRankings() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('organization_evaluations')
          .select('*, organizations(name)')
          .eq('school_year', _schoolYear)
          .order('grand_total', ascending: false);
      
      if (mounted) {
        setState(() {
          _evaluations = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leaderboard & Rankings', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                  Text('Top performing College Student Councils based on annual evaluations.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
                child: DropdownButton<String>(
                  value: _schoolYear,
                  underline: const SizedBox(),
                  items: ['2024-2025', '2025-2026', '2026-2027'].map((sy) => DropdownMenuItem(value: sy, child: Text('SY $sy'))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _schoolYear = val);
                      _fetchRankings();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _evaluations.isEmpty
                ? const Center(child: Text('No evaluations found for this school year.'))
                : ListView.builder(
                    itemCount: _evaluations.length,
                    itemBuilder: (context, index) {
                      final eval = _evaluations[index];
                      final orgName = eval['organizations']?['name'] ?? 'Unknown Org';
                      final total = eval['grand_total'] ?? 0;
                      final rating = eval['adjectival_rating'] ?? 'N/A';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: index < 3 ? Colors.orange.withValues(alpha: 0.1) : const Color(0xFFF1F5F9), shape: BoxShape.circle),
                              child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: index < 3 ? Colors.orange : const Color(0xFF64748B))),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(orgName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B))),
                                  Text(rating, style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('TOTAL SCORE', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w800)),
                                Text(total.toStringAsFixed(2), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdminViewOrgProfileDialog extends StatefulWidget {
  final Map<String, dynamic> org; final List<Map<String, dynamic>> activities, profiles;
  const _AdminViewOrgProfileDialog({required this.org, required this.activities, required this.profiles});
  @override
  State<_AdminViewOrgProfileDialog> createState() => _AdminViewOrgProfileDialogState();
}

class _AdminViewOrgProfileDialogState extends State<_AdminViewOrgProfileDialog> {
  final _supabase = Supabase.instance.client; List<Map<String, dynamic>> _officers = []; bool _isLoading = true;
  @override void initState() { super.initState(); _fetchOfficers(); }
  Future<void> _fetchOfficers() async { try { final res = await _supabase.from('org_officers').select().eq('organization_id', widget.org['id']); if (mounted) setState(() { _officers = List<Map<String, dynamic>>.from(res); _isLoading = false; }); } catch (_) { if (mounted) setState(() => _isLoading = false); } }
  @override
  Widget build(BuildContext context) {
    final orgId = widget.org['id'].toString();
    final president = widget.profiles.firstWhere((p) => p['organization_id']?.toString() == orgId && p['role'] == 'President', orElse: () => {'full_name': 'None'});
    final adviser = widget.profiles.firstWhere((p) => p['organization_id']?.toString() == orgId && p['role'] == 'Adviser', orElse: () => {'full_name': 'None'});
    final completed = widget.activities.where((a) => a['organization_id']?.toString() == orgId && a['status'] == 'Completed').toList();

    return Dialog(
      child: Container(
        width: 800,
        padding: const EdgeInsets.all(32),
        child: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.org['name'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(widget.org['type'] ?? ''),
              const Divider(),
              _AdminOrgDetailItem(label: 'Adviser', value: adviser['full_name'], icon: Icons.person_outline),
              _AdminOrgDetailItem(label: 'President', value: president['full_name'], icon: Icons.person),
              const SizedBox(height: 16),
              if (_officers.isNotEmpty) ...[
                const Text('Officers:', style: TextStyle(fontWeight: FontWeight.bold)),
                ..._officers.map((o) => Text('${o['full_name']} (${o['position']})')),
                const Divider(),
              ],
              if (completed.isNotEmpty) ...[
                const Text('Recent Accomplishments:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...completed.take(5).map((a) => ListTile(
                  title: Text(a['title'], style: const TextStyle(fontSize: 13)),
                  subtitle: Text('Completed: ${AppUtils.formatDateTime(a['proposed_date'])}', style: const TextStyle(fontSize: 11)),
                )),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminOrgDetailItem extends StatelessWidget {
  final String label, value; final IconData icon;
  const _AdminOrgDetailItem({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFF5F7FB), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 18, color: Colors.grey[600])),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)), Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))])
    ]);
  }
}

class _GPOAReportsView extends StatelessWidget {
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> profiles;

  const _GPOAReportsView({
    required this.organizations,
    required this.activities,
    required this.profiles,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GPOA Reports', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
          const Text('Select an organization to generate and print their full General Plan of Activities.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 24,
                mainAxisSpacing: 24,
                childAspectRatio: 1.5,
              ),
              itemCount: organizations.length,
              itemBuilder: (context, index) {
                final org = organizations[index];
                final orgActivities = activities.where((a) => a['organization_id']?.toString() == org['id'].toString()).toList();
                
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.business_rounded, color: Color(0xFF6366F1), size: 20),
                            ),
                            const Spacer(),
                            Text('${orgActivities.length} Activities', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(org['name'] ?? 'Unknown Org', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _printGPOA(context, org, orgActivities),
                            icon: const Icon(Icons.print_rounded, size: 16),
                            label: const Text('Generate Report'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _printGPOA(BuildContext context, Map<String, dynamic> org, List<Map<String, dynamic>> orgActivities) async {
    final president = profiles.firstWhere(
      (p) => p['organization_id']?.toString() == org['id'].toString() && p['role'] == 'President',
      orElse: () => {'full_name': 'Not Assigned'},
    );
    final adviser = profiles.firstWhere(
      (p) => p['organization_id']?.toString() == org['id'].toString() && p['role'] == 'Adviser',
      orElse: () => {'full_name': 'Not Assigned'},
    );

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => GPOAPreviewDialog(
          organization: org,
          activities: orgActivities,
          president: president,
          adviser: adviser,
          fileName: 'GPOA_${org['name']}.pdf',
        ),
      );
    }
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView();
  @override
  Widget build(BuildContext context) { return const Center(child: Text('Profile Settings coming soon.')); }
}
