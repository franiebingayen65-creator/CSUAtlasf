import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:csuatlasf/utils/app_utils.dart';
import 'package:csuatlasf/utils/pdf_generator.dart';
import 'package:csuatlasf/widgets/common_ui.dart';
import 'package:csuatlasf/widgets/csc_scoring_components.dart';
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
  final String _searchQuery = '';
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
        setState(() {
          _activities = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
        _checkAndReportAutoCompletion();
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

  void _checkAndReportAutoCompletion() {
    final now = DateTime.now();
    for (var item in _activities) {
      if (item['status'] == 'Scheduled' && item['proposed_date'] != null) {
        try {
          final eventDate = DateTime.parse(item['proposed_date'].toString()).toLocal();
          final duration = AppUtils.parseDuration(item['time_frame']);
          if (eventDate.add(duration).isBefore(now)) {
            // Efficiency: We don't await here to not block the UI, 
            // and the stream will eventually refresh the state.
            _supabase.from('activities').update({'status': 'Completed'}).eq('id', item['id']).then((_) {});
          }
        } catch (_) {}
      }
    }
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
                _AdminTopBar(onLogout: _showLogoutDialog, onProfile: () => _onPageSelected('Profile'), onNavigate: _onPageSelected),
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
      case 'Manage Scores':
      case 'Add Scores':
        return _AddScoresView(activities: _activities, organizations: _organizations, onRefresh: _fetchInitialData);
      case 'Accomplishment Reports': return _AccomplishmentReportsView(activities: _activities, onRefresh: _fetchInitialData);
      case 'GPOA Reports': return _GPOAReportsView(organizations: _organizations, activities: _activities, profiles: _profiles);
      case 'Archives': return _ArchivesView(activities: _activities, organizations: _organizations);
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
                  _SidebarItem(icon: Icons.rate_review_rounded, title: 'Manage Scores', isSelected: activePage == 'Manage Scores' || activePage == 'Add Scores', isCollapsed: isCollapsed, onTap: () => onPageSelected('Manage Scores')),
                  _SidebarItem(icon: Icons.emoji_events_rounded, title: 'View Ranks', isSelected: activePage == 'View Ranks', isCollapsed: isCollapsed, onTap: () => onPageSelected('View Ranks')),
                  if (!isCollapsed) const _SidebarHeader(title: 'REPORTS'),
                  _SidebarItem(icon: Icons.print_rounded, title: 'GPOA Reports', isSelected: activePage == 'GPOA Reports', isCollapsed: isCollapsed, onTap: () => onPageSelected('GPOA Reports')),
                  _SidebarItem(icon: Icons.assignment_rounded, title: 'Accomplishment Reports', isSelected: activePage == 'Accomplishment Reports', isCollapsed: isCollapsed, onTap: () => onPageSelected('Accomplishment Reports')),
                  _SidebarItem(icon: Icons.folder_special_rounded, title: 'Archives', isSelected: activePage == 'Archives', isCollapsed: isCollapsed, onTap: () => onPageSelected('Archives')),
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
  final Function(String)? onNavigate;
  const _AdminTopBar({required this.onLogout, required this.onProfile, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF6366F1), size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Cagayan State University - OSDW Portal',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A), letterSpacing: -0.5),
              ),
            ],
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: NotificationInboxButton(onNotificationTap: onNavigate),
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
    final activeActivities = activities.where((a) => a['is_archived'] != true).toList();
    final today = DateTime.now();
    final todayActivities = activeActivities.where((a) {
      if (a['proposed_date'] == null) {
        return false;
      }
      try {
        final date = DateTime.parse(a['proposed_date'].toString()).toLocal();
        return date.year == today.year && date.month == today.month && date.day == today.day;
      } catch (_) { return false; }
    }).toList();
    final pendingAction = activeActivities.where((a) => a['status'] == 'Endorsed' || a['status'] == 'Awaiting Date Approval').toList();

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
                    _TopOrganizationsCard(activities: activeActivities, organizations: organizations),
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
                  constraints: const BoxConstraints(maxWidth: 1000),
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
    final activeActivities = widget.activities.where((a) => a['is_archived'] != true).toList();
    final archivedActivities = widget.activities.where((a) => a['is_archived'] == true && (_selectedOrgId == null || a['organization_id']?.toString() == _selectedOrgId)).toList();
    final pendingApprovals = activeActivities.where((a) {
      final matchesOrganization = _selectedOrgId == null ||
          a['organization_id']?.toString() == _selectedOrgId;
      final status = a['status']?.toString();
      return matchesOrganization &&
          ['Pending', 'Endorsed', 'Awaiting Date Approval', 'Needs Revision']
              .contains(status);
    }).toList();

    return DefaultTabController(
      length: 3,
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
                        ...widget.organizations.map((org) => DropdownMenuItem(value: org['id'].toString(), child: Text(org['name'] ?? 'Unknown Org'))),
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
                  const Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_rounded, size: 18), SizedBox(width: 8), Text('GPOA by Organization', style: TextStyle(fontWeight: FontWeight.bold))])),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.archive_outlined, size: 18), const SizedBox(width: 8), Text('Archived GPOA (${archivedActivities.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
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
                      final orgActivities = activeActivities.where((a) => a['organization_id']?.toString() == org['id']).toList();
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
                  archivedActivities.isEmpty
                      ? const Center(child: Text('No archived GPOA activities.'))
                      : ListView.builder(
                          itemCount: archivedActivities.length,
                          itemBuilder: (context, index) {
                            final activity = archivedActivities[index];
                            final org = widget.organizations.firstWhere(
                              (o) => o['id'].toString() == activity['organization_id']?.toString(),
                              orElse: () => {'name': 'Unknown Org'},
                            );
                            return _buildGPOAListTile(activity, org);
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: act['is_archived'] == true ? 'Restore GPOA' : 'Archive GPOA',
              icon: Icon(act['is_archived'] == true ? Icons.unarchive_outlined : Icons.archive_outlined, color: const Color(0xFF64748B)),
              onPressed: () async {
                final archived = act['is_archived'] == true;
                try {
                  await Supabase.instance.client.from('activities').update({'is_archived': !archived}).eq('id', act['id']);
                  if (mounted) {
                    AppUtils.showTopToast(context, archived ? 'GPOA restored.' : 'GPOA archived.');
                    widget.onRefresh();
                  }
                } catch (e) {
                  if (mounted) AppUtils.showTopToast(context, 'Could not update archive: $e', isError: true);
                }
              },
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
        onTap: () => _showGPOADetailsDialog(context, act, org),
      ),
    );
  }

  void _showGPOADetailsDialog(BuildContext context, Map<String, dynamic> act, Map<String, dynamic> org) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
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
                    onStatusUpdate: (act['status'] == 'Endorsed' || act['status'] == 'Needs Revision') ? (s) async {
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
                          if (context.mounted) { AppUtils.showTopToast(context, s == 'Approved' ? 'GPOA approved and moved to scheduling!' : 'Status updated.'); Navigator.pop(context); }
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
    final activeActivities = widget.activities.where((a) => a['is_archived'] != true).toList();
    final awaiting = activeActivities.where((a) => a['status'] == 'Awaiting Date Approval').toList();
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
                      final orgActs = activeActivities.where((a) => a['organization_id']?.toString() == org['id'].toString() && ['Approved', 'Scheduled', 'Completed', 'Awaiting Date Approval', 'Needs Revision'].contains(a['status'])).toList();
                      
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
          constraints: const BoxConstraints(maxWidth: 1000), 
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

class _AccomplishmentReportsView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;
  const _AccomplishmentReportsView({required this.activities, required this.onRefresh});

  @override
  State<_AccomplishmentReportsView> createState() => _AccomplishmentReportsViewState();
}

class _AccomplishmentReportsViewState extends State<_AccomplishmentReportsView> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Accomplishment Reports', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
          const Text('Review and approve accomplishment reports submitted by organizations.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Active'), icon: Icon(Icons.inbox_outlined)),
              ButtonSegment(value: true, label: Text('Archived'), icon: Icon(Icons.archive_outlined)),
            ],
            selected: {_showArchived},
            onSelectionChanged: (selection) => setState(() => _showArchived = selection.first),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_showArchived),
              future: Supabase.instance.client.from('accomplishment_reports').select('*, activities(*)').eq('is_archived', _showArchived).order('report_date', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final reports = snapshot.data ?? [];
                
                if (reports.isEmpty) {
                  return const Center(child: Text('No accomplishment reports submitted yet.'));
                }

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 24,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    final activity = report['activities'] ?? {};
                    final reportStatus = report['status'] ?? 'Pending';
                    final isApproved = reportStatus == 'Approved';
                    final statusColor = statusColorFor(reportStatus);

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: statusColor.withValues(alpha: 0.22)),
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
                                    color: statusColor.withValues(alpha: 0.09),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isApproved ? Icons.verified_rounded : Icons.file_present_rounded,
                                    size: 16,
                                    color: statusColor,
                                  ),
                                ),
                                const Spacer(),
                                StatusBadge(status: reportStatus),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(activity['title'] ?? 'Untitled Activity', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _viewReport(report['attachments']),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF8FAFC), foregroundColor: const Color(0xFF1E293B), elevation: 0),
                                    child: const Text('View File'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!isApproved)
                                  IconButton(
                                    onPressed: () => _approveReport(context, report['id']),
                                    icon: const Icon(Icons.check_circle_rounded, color: Colors.green),
                                    tooltip: 'Approve Report',
                                  ),
                                IconButton(
                                  tooltip: _showArchived ? 'Restore report' : 'Archive report',
                                  icon: Icon(_showArchived ? Icons.unarchive_outlined : Icons.archive_outlined, color: const Color(0xFF64748B)),
                                  onPressed: () => _setReportArchived(context, report['id'], !_showArchived),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setReportArchived(BuildContext context, dynamic reportId, bool archived) async {
    try {
      await Supabase.instance.client.from('accomplishment_reports').update({'is_archived': archived}).eq('id', reportId);
      if (context.mounted) {
        AppUtils.showTopToast(context, archived ? 'Report archived.' : 'Report restored.');
        setState(() {});
        widget.onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Could not update archive: $e', isError: true);
    }
  }

  void _viewReport(dynamic attachments) async {
    if (attachments == null || (attachments as List).isEmpty) return;
    final url = attachments.first.toString();
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<void> _approveReport(BuildContext context, dynamic reportId) async {
    try {
      await Supabase.instance.client.from('accomplishment_reports').update({'status': 'Approved'}).eq('id', reportId);
      if (context.mounted) AppUtils.showTopToast(context, 'Report approved successfully!');
      widget.onRefresh();
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
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

  final Map<String, TextEditingController> _levelGridControllers = {};

  final _amountVIIController = TextEditingController();
  final _amountVIIIController = TextEditingController();
  final _amountIXController = TextEditingController();
  final _percentXController = TextEditingController();

  double get grandTotal {
    double total = 0;
    _controllers.forEach((key, controller) {
      total += double.tryParse(controller.text) ?? 0;
    });
    return total;
  }

  String get adjectivalRating => getAdjectivalRating(grandTotal);

  @override
  void initState() {
    super.initState();
    _initLevelGridControllers();
    for (var controller in _controllers.values) {
      controller.addListener(() { if (mounted) setState(() {}); });
    }
  }

  void _initLevelGridControllers() {
    final levels = ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    final itemMaxes = {'i': 4, 'ii': 4, 'iii': 5, 'iv': 10, 'v': 10, 'vi': 5};

    itemMaxes.forEach((item, maxActs) {
      for (int act = 1; act <= maxActs; act++) {
        for (final lvl in levels) {
          _levelGridControllers['${item}_${act}_${lvl}_sdg'] ??= TextEditingController();
          _levelGridControllers['${item}_${act}_${lvl}_pts'] ??= TextEditingController();
          _levelGridControllers['${item}_${act}_$lvl'] ??= TextEditingController();
        }
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    for (var controller in _levelGridControllers.values) {
      controller.dispose();
    }
    _amountVIIController.dispose();
    _amountVIIIController.dispose();
    _amountIXController.dispose();
    _percentXController.dispose();
    super.dispose();
  }

  void _onGridInputChanged(String key, int act, String lvl, int maxActs) {
    final levels = _selectedOrgType == 'Campus Student Council'
        ? ['intl', 'natl', 'regl', 'univ', 'camp']
        : ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];

    final itemMaxes = {'i': 4, 'ii': 4, 'iii': 5, 'iv': 10, 'v': _selectedOrgType == 'Campus Student Council' ? 5 : 10, 'vi': 5};
    final limit = itemMaxes[key] ?? maxActs;

    int totalActiveSlots = 0;
    for (int a = 1; a <= maxActs; a++) {
      for (final l in levels) {
        final pText = _levelGridControllers['${key}_${a}_${l}_pts']?.text.trim() ?? '';
        final vText = _levelGridControllers['${key}_${a}_$l']?.text.trim() ?? '';
        final sText = _levelGridControllers['${key}_${a}_${l}_sdg']?.text.trim() ?? '';

        final pVal = double.tryParse(pText);
        final vVal = double.tryParse(vText);
        final sVal = int.tryParse(sText);

        if ((pVal != null && pVal > 0) || (vVal != null && vVal > 0) || (sVal != null && sVal > 0)) {
          totalActiveSlots++;
        }
      }
    }

    if (totalActiveSlots > limit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _levelGridControllers['${key}_${act}_${lvl}_pts']?.clear();
        _levelGridControllers['${key}_${act}_$lvl']?.clear();
        _levelGridControllers['${key}_${act}_${lvl}_sdg']?.clear();
        _recalculateItemFromGrid(key);
        if (mounted) setState(() {});
      });
      AppUtils.showTopToast(context, 'Maximum limit of $limit activities reached for this category.', isError: true);
      return;
    }

    _recalculateItemFromGrid(key);
  }

  void _recalculateItemFromGrid(String key) {
    double total = 0;
    final levels = _selectedOrgType == 'Campus Student Council'
        ? ['intl', 'natl', 'regl', 'univ', 'camp']
        : ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    final itemMaxes = {'i': 4, 'ii': 4, 'iii': 5, 'iv': 10, 'v': _selectedOrgType == 'Campus Student Council' ? 5 : 10, 'vi': 5};
    final maxActs = itemMaxes[key] ?? 4;

    for (int act = 1; act <= maxActs; act++) {
      for (final lvl in levels) {
        final ptsController = _levelGridControllers['${key}_${act}_${lvl}_pts'];
        final lvlController = _levelGridControllers['${key}_${act}_$lvl'];
        final sdgController = _levelGridControllers['${key}_${act}_${lvl}_sdg'];

        final ptsVal = double.tryParse(ptsController?.text ?? '') ??
            double.tryParse(lvlController?.text ?? '');
        final sdgVal = int.tryParse(sdgController?.text ?? '');

        if (ptsVal != null && ptsVal > 0) {
          total += ptsVal;
        } else if (sdgVal != null && sdgVal > 0) {
          final computed = (key == 'i' || key == 'ii')
              ? calculateSDGPoints(lvl, sdgVal, _selectedOrgType)
              : getCategoricalLevelUnitPoints(lvl, _selectedOrgType);
          
          if (ptsController != null && ptsController.text.isEmpty) ptsController.text = computed.toStringAsFixed(1);
          if (lvlController != null && lvlController.text.isEmpty) lvlController.text = computed.toStringAsFixed(1);
          total += computed;
        }
      }
    }
    double maxAllowed = (key == 'iii') ? 5.0 : 10.0;
    if (total > maxAllowed) {
      total = maxAllowed;
    }
    _controllers[key]?.text = total.toStringAsFixed(1);
  }

  final Map<String, Map<String, String>> _sessionGridCache = {};

  Future<void> _loadEvaluation() async {
    if (_selectedOrgId == null) return;
    try {
      final res = await Supabase.instance.client
          .from('organization_evaluations')
          .select()
          .eq('organization_id', _selectedOrgId!)
          .eq('school_year', _schoolYear)
          .maybeSingle();

      for (var c in _levelGridControllers.values) {
        c.clear();
      }

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

          final rawRating = res['adjectival_rating']?.toString() ?? '';
          if (rawRating.contains('|')) {
            final jsonStr = rawRating.substring(rawRating.indexOf('|') + 1);
            try {
              final Map<String, dynamic> decoded = jsonDecode(jsonStr);
              decoded.forEach((k, v) {
                final keyStr = k.toString();
                if (_levelGridControllers.containsKey(keyStr)) {
                  _levelGridControllers[keyStr]!.text = v.toString();
                }
              });
            } catch (_) {}
          }

          final cachedGrid = _sessionGridCache[_selectedOrgId];
          if (cachedGrid != null) {
            cachedGrid.forEach((k, v) {
              if (_levelGridControllers.containsKey(k)) {
                _levelGridControllers[k]!.text = v;
              }
            });
          }
        });
      } else {
        setState(() {
          for (var c in _controllers.values) { c.text = '0'; }
          _amountVIIController.clear();
          _amountVIIIController.clear();
          _amountIXController.clear();
          _percentXController.clear();

          final cachedGrid = _sessionGridCache[_selectedOrgId];
          if (cachedGrid != null) {
            cachedGrid.forEach((k, v) {
              if (_levelGridControllers.containsKey(k)) {
                _levelGridControllers[k]!.text = v;
              }
            });
          }
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
      final Map<String, String> gridData = {};
      _levelGridControllers.forEach((key, controller) {
        if (controller.text.trim().isNotEmpty && controller.text.trim() != '—') {
          gridData[key] = controller.text.trim();
        }
      });
      _sessionGridCache[_selectedOrgId!] = gridData;

      final ratingWithGrid = '$adjectivalRating|${jsonEncode(gridData)}';

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
        'adjectival_rating': ratingWithGrid,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client.from('organization_evaluations').upsert(data, onConflict: 'organization_id,school_year');
      if (mounted) {
        AppUtils.showTopToast(context, 'Evaluation record updated successfully!');
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Error saving evaluation: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_selectedOrgId == null) {
      AppUtils.showTopToast(context, 'Please select an organization first.', isError: true);
      return;
    }

    final keys = ['i', 'ii', 'iii', 'iv', 'v', 'vi'];
    for (final k in keys) {
      _recalculateItemFromGrid(k);
    }

    final org = widget.organizations.firstWhere((o) => o['id'].toString() == _selectedOrgId, orElse: () => {'name': 'Selected Organization'});
    final Map<String, double> scores = {};
    _controllers.forEach((key, controller) {
      scores[key] = double.tryParse(controller.text) ?? 0;
    });

    final Map<String, String> gridValues = {};
    _levelGridControllers.forEach((key, controller) {
      if (controller.text.trim().isNotEmpty) {
        gridValues[key] = controller.text.trim();
      }
    });

    await CSCEvaluationPdfGenerator.showPdfPreviewDialog(
      context,
      organization: org,
      schoolYear: _schoolYear,
      scores: scores,
      gridValues: gridValues,
      grandTotal: grandTotal,
      adjectivalRating: adjectivalRating,
      orgType: _selectedOrgType ?? 'College Student Council',
    );
  }

  Future<void> _downloadPdfFile() async {
    if (_selectedOrgId == null) {
      AppUtils.showTopToast(context, 'Please select an organization first.', isError: true);
      return;
    }

    final keys = ['i', 'ii', 'iii', 'iv', 'v', 'vi'];
    for (final k in keys) {
      _recalculateItemFromGrid(k);
    }

    final org = widget.organizations.firstWhere((o) => o['id'].toString() == _selectedOrgId, orElse: () => {'name': 'Selected Organization'});
    final Map<String, double> scores = {};
    _controllers.forEach((key, controller) {
      scores[key] = double.tryParse(controller.text) ?? 0;
    });

    final Map<String, String> gridValues = {};
    _levelGridControllers.forEach((key, controller) {
      if (controller.text.trim().isNotEmpty) {
        gridValues[key] = controller.text.trim();
      }
    });

    await CSCEvaluationPdfGenerator.saveAndDownloadPdf(
      context,
      organization: org,
      schoolYear: _schoolYear,
      scores: scores,
      gridValues: gridValues,
      grandTotal: grandTotal,
      adjectivalRating: adjectivalRating,
      orgType: _selectedOrgType ?? 'College Student Council',
    );
  }

  String? _selectedOrgType;

  List<Map<String, dynamic>> get _filteredOrganizations {
    if (_selectedOrgType == null) return widget.organizations;
    final target = _selectedOrgType!.toLowerCase();
    final matches = widget.organizations.where((o) {
      final type = (o['type'] ?? '').toString().toLowerCase();
      if (target.contains('college')) return type.contains('college');
      if (target.contains('campus')) return type.contains('campus');
      if (target.contains('specialized')) return type.contains('specialized') || type.contains('special');
      return type == target;
    }).toList();
    return matches.isNotEmpty ? matches : widget.organizations;
  }

  double _sheetZoomScale = 1.45;

  @override
  Widget build(BuildContext context) {
    if (_selectedOrgType == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Center(child: _buildTypeSelectionScreen()),
      );
    }

    final isSpecialized = (_selectedOrgType ?? '').toLowerCase().contains('special');
    final double baseUnscaledHeight = isSpecialized ? 5200.0 : 6500.0;
    final double extraZoomScrollHeight = _sheetZoomScale > 1.0 ? baseUnscaledHeight * (_sheetZoomScale - 1.0) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            _buildTopPanel(),
            const SizedBox(height: 24),
            _buildScoreBanner(),
            const SizedBox(height: 32),
            _buildZoomControls(),
            const SizedBox(height: 24),
            Transform.scale(
              scale: _sheetZoomScale,
              alignment: Alignment.topCenter,
              child: Column(
                children: [
                  _buildFolioPage(1, _buildPage1Content()),
                  const SizedBox(height: 40),
                  _buildFolioPage(2, _buildPage2Content()),
                  const SizedBox(height: 40),
                  _buildFolioPage(3, _buildPage3Content()),
                  const SizedBox(height: 40),
                  _buildFolioPage(4, _buildPage4Content()),
                  if (!isSpecialized) ...[
                    const SizedBox(height: 40),
                    _buildFolioPage(5, _buildPage5Content()),
                  ],
                ],
              ),
            ),
            SizedBox(height: 80 + extraZoomScrollHeight),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelectionScreen() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1000),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rate_review_rounded, size: 52, color: Color(0xFF6366F1)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Manage Organization Evaluations',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Select a classification to score, manage evaluations, or review sheets for SY 2025-2026',
            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              _buildTypeCard(
                type: 'College Student Council',
                icon: Icons.account_balance_rounded,
                color: const Color(0xFF4F46E5),
                bgLight: const Color(0xFFEEF2FF),
                title: 'College Student Council',
                subtitle: 'Evaluate Academic College Student Councils',
              ),
              _buildTypeCard(
                type: 'Campus Student Council',
                icon: Icons.domain_rounded,
                color: const Color(0xFF0D9488),
                bgLight: const Color(0xFFCCFBF1),
                title: 'Campus Student Council',
                subtitle: 'Evaluate Main Campus Student Government',
              ),
              _buildTypeCard(
                type: 'Specialized Organization',
                icon: Icons.stars_rounded,
                color: const Color(0xFFD97706),
                bgLight: const Color(0xFFFEF3C7),
                title: 'Specialized Organization',
                subtitle: 'Evaluate Interest, Cultural, & Special Orgs',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCategoryEvaluationsDialog(String categoryType) async {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 760,
            constraints: const BoxConstraints(maxHeight: 650),
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: Supabase.instance.client
                  .from('organization_evaluations')
                  .select('*, organizations(*)')
                  .eq('school_year', _schoolYear),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                }

                final allEvals = snapshot.data ?? [];
                
                final targetType = categoryType.toLowerCase();
                final categoryOrgs = widget.organizations.where((o) {
                  final orgType = (o['type'] ?? '').toString().toLowerCase();
                  if (targetType.contains('college')) return orgType.contains('college');
                  if (targetType.contains('campus')) return orgType.contains('campus');
                  if (targetType.contains('specialized')) return orgType.contains('specialized') || orgType.contains('special');
                  return true;
                }).toList();

                final Map<String, Map<String, dynamic>> evalMap = {};
                for (var eval in allEvals) {
                  final orgId = eval['organization_id']?.toString();
                  if (orgId != null) evalMap[orgId] = eval;
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.assessment_rounded, color: Color(0xFF6366F1), size: 26),
                            const SizedBox(width: 10),
                            Text(
                              '$categoryType - Organizations & Evaluations',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (categoryOrgs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No organizations found for this category.',
                            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: categoryOrgs.length,
                          itemBuilder: (c, idx) {
                            final org = categoryOrgs[idx];
                            final orgId = org['id']?.toString();
                            final orgName = (org['name'] ?? 'Unknown Org').toString().toUpperCase();
                            final eval = evalMap[orgId];
                            final isEvaluated = eval != null;

                            final total = isEvaluated ? ((eval['grand_total'] as num?)?.toDouble() ?? 0.0) : 0.0;
                            final rawRating = isEvaluated ? (eval['adjectival_rating'] ?? 'Pending').toString() : 'Pending Evaluation';
                            final rating = rawRating.contains('|') ? rawRating.split('|').first : rawRating;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isEvaluated ? const Color(0xFFF8FAFC) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isEvaluated ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(orgName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            if (isEvaluated) ...[
                                              Text('Score: ${total.toStringAsFixed(2)} pts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF4F46E5))),
                                              const SizedBox(width: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                                child: Text(rating.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                              ),
                                            ] else ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                                child: const Text('NOT EVALUATED YET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final Map<String, double> orgScores = {};
                                          final Map<String, String> gridData = {};

                                          if (isEvaluated) {
                                            orgScores['i'] = (eval['score_i'] as num?)?.toDouble() ?? 0;
                                            orgScores['ii'] = (eval['score_ii'] as num?)?.toDouble() ?? 0;
                                            orgScores['iii'] = (eval['score_iii'] as num?)?.toDouble() ?? 0;
                                            orgScores['iv'] = (eval['score_iv'] as num?)?.toDouble() ?? 0;
                                            orgScores['v'] = (eval['score_v'] as num?)?.toDouble() ?? 0;
                                            orgScores['vi'] = (eval['score_vi'] as num?)?.toDouble() ?? 0;
                                            orgScores['vii'] = (eval['score_vii'] as num?)?.toDouble() ?? 0;
                                            orgScores['viii'] = (eval['score_viii'] as num?)?.toDouble() ?? 0;
                                            orgScores['ix'] = (eval['score_ix'] as num?)?.toDouble() ?? 0;
                                            orgScores['x'] = (eval['score_x'] as num?)?.toDouble() ?? 0;

                                            final rawR = (eval['adjectival_rating'] ?? '').toString();
                                            if (rawR.contains('|')) {
                                              final jsonStr = rawR.substring(rawR.indexOf('|') + 1);
                                              try {
                                                final Map<String, dynamic> decoded = jsonDecode(jsonStr);
                                                decoded.forEach((k, v) => gridData[k.toString()] = v.toString());
                                              } catch (_) {}
                                            }
                                          }

                                          await CSCEvaluationPdfGenerator.showPdfPreviewDialog(
                                            context,
                                            organization: org,
                                            schoolYear: _schoolYear,
                                            scores: orgScores,
                                            gridValues: gridData,
                                            grandTotal: total,
                                            adjectivalRating: rating,
                                            orgType: categoryType,
                                          );
                                        },
                                        icon: const Icon(Icons.print_rounded, size: 16),
                                        label: const Text('Preview PDF'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF10B981),
                                          side: const BorderSide(color: Color(0xFF10B981)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(dialogCtx).pop();
                                          setState(() {
                                            _selectedOrgType = categoryType;
                                            _selectedOrgId = orgId;
                                            _loadEvaluation();
                                          });
                                        },
                                        icon: Icon(isEvaluated ? Icons.edit_note_rounded : Icons.add_chart_rounded, size: 16),
                                        label: Text(isEvaluated ? 'Load Sheet' : 'Open Sheet'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF4F46E5),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypeCard({
    required String type,
    required IconData icon,
    required Color color,
    required Color bgLight,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 36, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedOrgType = type;
                  _selectedOrgId = null;
                  final available = _filteredOrganizations;
                  if (available.isNotEmpty) {
                    _selectedOrgId = available.first['id'].toString();
                    _loadEvaluation();
                  }
                });
              },
              icon: const Icon(Icons.assignment_turned_in_rounded, size: 16),
              label: const Text('Evaluate Category'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showCategoryEvaluationsDialog(type),
              icon: const Icon(Icons.visibility_rounded, size: 16),
              label: const Text('View Evaluations'),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.zoom_in_map_rounded, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          const Text('Sheet Zoom:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Zoom Out',
            icon: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF4F46E5), size: 22),
            onPressed: () {
              setState(() {
                if (_sheetZoomScale > 0.6) _sheetZoomScale -= 0.15;
              });
            },
          ),
          InkWell(
            onTap: () => setState(() => _sheetZoomScale = 1.45),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(_sheetZoomScale * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF4F46E5)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Zoom In',
            icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5), size: 22),
            onPressed: () {
              setState(() {
                if (_sheetZoomScale < 2.2) _sheetZoomScale += 0.15;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopPanel() {
    final displayOrgs = _filteredOrganizations;

    return Container(
      constraints: const BoxConstraints(maxWidth: 1000),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stars_rounded, color: Color(0xFF6366F1), size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(_selectedOrgType ?? 'COLLEGE STUDENT COUNCIL').toUpperCase()} EVALUATION',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => setState(() {
                      _selectedOrgType = null;
                      _selectedOrgId = null;
                    }),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFF4F46E5)),
                        SizedBox(width: 4),
                        Text(
                          'Switch Category',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5), decoration: TextDecoration.underline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedOrgId,
                  isExpanded: true,
                  hint: Text('Select ${_selectedOrgType ?? 'Organization'}', overflow: TextOverflow.ellipsis),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: displayOrgs.map((o) => DropdownMenuItem(value: o['id'].toString(), child: Text(o['name'] ?? '', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) { setState(() => _selectedOrgId = val); _loadEvaluation(); },
                ),
              ),
              OutlinedButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.print_rounded, size: 18),
                label: const Text('Export 5-Page PDF'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _downloadPdfFile,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Save PDF File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveEvaluation,
                icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Commit Record'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBanner() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1000),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TOTAL EVALUATION SCORE', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(
                grandTotal.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.white30),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Text(
                  adjectivalRating.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolioPage(int num, Widget content) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 900, minHeight: 1250),
      width: 900,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFolioHeader(),
              const SizedBox(height: 16),
              content,
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Divider(color: Colors.black, thickness: 1.0),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('$num | P a g e  ', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)),
                  Expanded(
                    child: Text(
                      'Search for the Most Outstanding ${_selectedOrgType ?? 'College Student Council'} Organization SY 2025-2026',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFolioHeader() {
    final typeLower = (_selectedOrgType ?? '').toLowerCase();
    final isCampus = typeLower.contains('campus');
    final isSpecialized = typeLower.contains('specialized') || typeLower.contains('special');

    final campusHeader = isSpecialized ? 'ANDREWS CAMPUS' : (isCampus ? 'Central Administration' : 'LAL-LO CAMPUS');
    final locationHeader = isSpecialized ? 'Caritan, Tuguegarao City, Cagayan' : (isCampus ? 'Caritan, Tuguegarao City, Cagayan' : 'Sta. Maria, Lal-lo, Cagayan');
    final emailHeader = isSpecialized ? 'osdw@csu.edu.ph' : (isCampus ? 'osdw@csu.edu.ph' : 'osdw.lallo@csu.edu.ph');
    final fbHeader = isSpecialized ? 'Ossw Andrews' : (isCampus ? 'CSU Office of Student Development & Welfare' : 'Osdw Lallo');

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REPUBLIC OF THE PHILIPPINES', style: TextStyle(fontSize: 10, color: Color(0xFFB71C1C), fontWeight: FontWeight.normal)),
                const Text('CAGAYAN STATE UNIVERSITY', style: TextStyle(fontSize: 16, color: Color(0xFFB71C1C), fontWeight: FontWeight.w900)),
                Text(campusHeader, style: const TextStyle(fontSize: 12, color: Color(0xFFB71C1C), fontWeight: FontWeight.bold)),
                Text(locationHeader, style: const TextStyle(fontSize: 10, color: Color(0xFFB71C1C), fontStyle: FontStyle.italic)),
              ],
            ),
            Expanded(
              child: Center(
                child: Image.asset('assets/images/csulogo.png', height: 60, errorBuilder: (c, e, s) => const Icon(Icons.school, size: 60, color: Color(0xFFB71C1C))),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Email Address: $emailHeader', style: const TextStyle(fontSize: 9, color: Color(0xFFB71C1C), fontStyle: FontStyle.italic, decoration: TextDecoration.underline)),
                const Text('Website: www.csu.edu.ph', style: TextStyle(fontSize: 9, color: Color(0xFFB71C1C), fontStyle: FontStyle.italic, decoration: TextDecoration.underline)),
                Text('Facebook Page: $fbHeader', style: const TextStyle(fontSize: 9, color: Color(0xFFB71C1C), fontStyle: FontStyle.italic)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'OFFICE OF STUDENT DEVELOPMENT AND WELFARE',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 0.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        const Divider(color: Colors.black, thickness: 1.5, height: 1),
      ],
    );
  }

  Widget _buildPage1Content() {
    final isSpecialized = (_selectedOrgType ?? '').toLowerCase().contains('special');
    final org = widget.organizations.firstWhere((o) => o['id'].toString() == _selectedOrgId, orElse: () => {'name': '________________'});
    final campusName = isSpecialized ? 'ANDREWS CAMPUS' : (_selectedOrgType == 'Campus Student Council' ? 'CENTRAL ADMINISTRATION' : 'LAL-LO CAMPUS');

    if (isSpecialized) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'CRITERIA FOR THE SEARCH FOR OUTSTANDING SPECIALIZED ORGANIZATION SY 2025-2026',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildInfoField('Organization:', org['name'].toString().toUpperCase())),
              const SizedBox(width: 20),
              Expanded(child: _buildInfoField('Points:', grandTotal.toStringAsFixed(2))),
            ],
          ),
          Row(
            children: [
              Expanded(child: _buildInfoField('Campus:', campusName)),
              const SizedBox(width: 20),
              Expanded(child: _buildInfoField('Adjectival Rating:', adjectivalRating.toUpperCase())),
            ],
          ),
          const SizedBox(height: 24),
          const Center(child: Text('ACTIVITIES CONDUCTED/ SPONSORED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline))),
          const SizedBox(height: 16),
          _buildSpecializedPage1Matrix(),
          const SizedBox(height: 16),
          const Text(
            'For Items III, IV, V and VI, the number of SDGs is no longer required, as discussed during the OSDW 3rd Quarter Meeting held last August 15, 2024. All activities under these items are now considered specific and aligned with their respective objectives.',
            style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          _buildCategoricalHeader(),
          _buildActivityCategoryTable(
            title: 'III. Makakalikasan/ Clean and Green Activities and Projects (10 points)\nMax. No. of Activities: 10',
            docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU\n• Consent letter/Invitation Letter\n• Narrative Report\n• Certificate signed by partner agency\n• Attendance Sheet\n• Documentation',
            key: 'iii',
            maxActs: 10,
            isSDGMatrix: false,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            'CRITERIA FOR THE SEARCH FOR OUTSTANDING ${(_selectedOrgType ?? 'COLLEGE STUDENT COUNCIL').toUpperCase()} SY 2025-2026',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _buildInfoField('Organization:', org['name'].toString().toUpperCase())),
            const SizedBox(width: 20),
            Expanded(child: _buildInfoField('Points:', grandTotal.toStringAsFixed(2))),
          ],
        ),
        Row(
          children: [
            Expanded(child: _buildInfoField('Campus:', campusName)),
            const SizedBox(width: 20),
            Expanded(child: _buildInfoField('Adjectival Rating:', adjectivalRating.toUpperCase())),
          ],
        ),
        const SizedBox(height: 24),
        const Center(child: Text('ACTIVITIES CONDUCTED/ SPONSORED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline))),
        const SizedBox(height: 16),
        _buildPage1Matrix(),
        const SizedBox(height: 16),
        const Text(
          'For Items III, IV, V and VI, the number of SDGs is no longer required, as discussed during the OSDW 3rd Quarter Meeting held last August 15, 2024. All activities under these items are now considered specific and aligned with their respective objectives.',
          style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 16),
        _buildCategoricalHeader(),
        _buildActivityCategoryTable(
          title: 'III. Religious Activities (5 points)\nMax. No. of Activities: 5',
          docs: '• Approved Letter\n• Documentation\n• Narrative Report\n• Attendance Sheet (Except for Holy Mass and Praying of Rosary)\n• Concept Paper',
          key: 'iii',
          maxActs: 5,
          isSDGMatrix: false,
        ),
      ],
    );
  }

  Widget _buildSpecializedPage1Matrix() {
    return Column(
      children: [
        Table(
          border: TableBorder.all(color: Colors.black, width: 0.5),
          columnWidths: const {
            0: FixedColumnWidth(125), 1: FixedColumnWidth(125),
            2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
            4: FlexColumnWidth(1), 5: FlexColumnWidth(1),
            6: FlexColumnWidth(1), 7: FlexColumnWidth(1),
          },
          children: [
            _buildMatrixIAndIIHeader(),
            _buildMatrixCriteriaRow(['3', '5.5'], ['3', '5.0'], ['5', '4.5'], ['5', '4.0'], ['7', '3.5'], ['10', '3.0']),
            _buildMatrixCriteriaRow(['2', '5.0'], ['2', '4.5'], ['4', '4.0'], ['4', '3.5'], ['6', '3.0'], ['9', '2.5']),
            _buildMatrixCriteriaRow(['1', '4.5'], ['1', '4.0'], ['3', '3.5'], ['3', '3.0'], ['5', '2.5'], ['8', '2.0']),
            TableRow(
              children: [
                const TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.all(5),
                    child: Text('Attendance should be 50%+1 of the total target participants.', style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(),
              ],
            ),
          ],
        ),
        _buildActivityCategoryTable(
          title: 'I. Symposium /Seminars Conducted (20 points)\nMax. No. of Activities: 7',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'i',
          maxActs: 7,
          isSDGMatrix: true,
        ),
        _buildActivityCategoryTable(
          title: 'II. Activities Conducted /Sponsored in line with the nature of the organization (30 points)\nMax. No. of Activities: 10',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'ii',
          maxActs: 10,
          isSDGMatrix: true,
        ),
      ],
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 2),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black))),
              child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage1Matrix() {
    final isCampus = _selectedOrgType == 'Campus Student Council';
    final colWidths = isCampus ? const {
      0: FixedColumnWidth(125), 1: FixedColumnWidth(125),
      2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
      4: FlexColumnWidth(1), 5: FlexColumnWidth(1),
      6: FlexColumnWidth(1),
    } : const {
      0: FixedColumnWidth(125), 1: FixedColumnWidth(125),
      2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
      4: FlexColumnWidth(1), 5: FlexColumnWidth(1),
      6: FlexColumnWidth(1), 7: FlexColumnWidth(1),
    };

    return Column(
      children: [
        Table(
          border: TableBorder.all(color: Colors.black, width: 0.5),
          columnWidths: colWidths,
          children: [
            _buildMatrixIAndIIHeader(),
            if (isCampus) ...[
              _buildMatrixCriteriaRow(['3', '1.5'], ['5', '2.5'], ['5', '2.0'], ['5', '1.5'], ['7', '2.5']),
              _buildMatrixCriteriaRow(['2', '1.0'], ['4', '2.0'], ['4', '1.5'], ['4', '1.0'], ['6', '2.0']),
              _buildMatrixCriteriaRow(['1', '0.5'], ['3', '1.5'], ['3', '1.0'], ['3', '0.5'], ['5', '1.5']),
              TableRow(
                children: [
                  const TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: Text('Attendance should be 50%+1 of the total target participants.', style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(),
                  const SizedBox(),
                  Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                    Expanded(child: Center(child: const Text('2', style: TextStyle(fontSize: 9)))),
                    Container(width: 0.5, height: 12, color: Colors.black26),
                    Expanded(child: Center(child: const Text('1', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
                  ]))),
                  const SizedBox(), const SizedBox(), const SizedBox(),
                ],
              ),
              TableRow(
                children: [
                  const SizedBox(), const SizedBox(), const SizedBox(),
                  Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
                    Expanded(child: Center(child: const Text('1', style: TextStyle(fontSize: 9)))),
                    Container(width: 0.5, height: 12, color: Colors.black26),
                    Expanded(child: Center(child: const Text('.5', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
                  ]))),
                  const SizedBox(), const SizedBox(), const SizedBox(),
                ],
              ),
            ] else ...[
              _buildMatrixCriteriaRow(['3', '2.5'], ['3', '2.5'], ['5', '2.5'], ['5', '2.0'], ['5', '1.5'], ['7', '2.5']),
              _buildMatrixCriteriaRow(['2', '2.0'], ['2', '2.0'], ['4', '2.0'], ['4', '1.5'], ['4', '1.0'], ['6', '2.0']),
              _buildMatrixCriteriaRow(['1', '1.5'], ['1', '1.5'], ['3', '1.5'], ['3', '1.0'], ['3', '0.5'], ['5', '1.5']),
              TableRow(
                children: [
                  const TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: Text('Attendance should be 50%+1 of total target participants.', style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(), const SizedBox(),
                ],
              ),
            ],
          ],
        ),
        _buildActivityCategoryTable(
          title: 'I. Symposium/ Seminars Conducted (10 points)\nMax. No. of Activities: 4',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'i',
          maxActs: 4,
          isSDGMatrix: true,
        ),
        _buildActivityCategoryTable(
          title: 'II. Convocations/ Programs and Literary Activities (10 points)\nMax. No. of Activities: 4',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'ii',
          maxActs: 4,
          isSDGMatrix: true,
        ),
      ],
    );
  }

  TableRow _buildMatrixIAndIIHeader() {
    final isCampus = _selectedOrgType == 'Campus Student Council';
    final levelsList = isCampus ? [
      'Int\'l Level\n(at least 3 countries)',
      'National Level',
      'Regional Level/\nProvincial',
      'University Wide/\nMunicipality',
      'Campus Wide/\nBarangay',
    ] : [
      'Int\'l Level\n(at least 3 countries)',
      'National Level',
      'Regional Level/\nProvincial',
      'University Wide/\nMunicipality',
      'Campus Wide/\nBarangay',
      'College Level'
    ];

    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      children: [
        const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Padding(padding: EdgeInsets.all(5), child: Text('Activities', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))),
        const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Padding(padding: EdgeInsets.all(5), child: Text('Supporting Docs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))),
        for (final l in levelsList)
          TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Column(children: [
            Center(child: Padding(padding: const EdgeInsets.all(3), child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
            const Divider(height: 1, color: Colors.black),
            Row(children: [
              Expanded(child: Center(child: Text('SDGs', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)))),
              Container(width: 0.5, height: 12, color: Colors.black),
              Expanded(child: Center(child: Text('Pts', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)))),
            ])
          ])),
      ],
    );
  }

  TableRow _buildMatrixCriteriaRow(List<String> l1, List<String> l2, List<String> l3, List<String> l4, List<String> l5, [List<String>? l6]) {
    final pairs = [l1, l2, l3, l4, l5];
    if (l6 != null && _selectedOrgType != 'Campus Student Council') pairs.add(l6);

    return TableRow(
      children: [
        const SizedBox(), const SizedBox(),
        for (final pair in pairs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Center(child: Text(pair[0], style: const TextStyle(fontSize: 9)))),
                Container(width: 0.5, height: 12, color: Colors.grey.shade400),
                Expanded(child: Center(child: Text(pair[1], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCategoricalHeader() {
    final isCampus = _selectedOrgType == 'Campus Student Council';
    final levelsList = isCampus ? [
      'International Level\n(at least 3 countries)\n3 points',
      'National Level\n2.5 points',
      'Regional Level/\nProvincial\n2 points',
      'University Wide/\nMunicipality\n1.5 points',
      'Campus Wide/\nBarangay\n1 point',
    ] : [
      'International Level\n(at least 3 countries)\n3.5 points',
      'National Level\n3 points',
      'Regional Level/\nProvincial\n2.5 points',
      'University Wide/\nMunicipality\n2 points',
      'Campus Wide/\nBarangay\n1.5 points',
      'College Level\n1 point'
    ];

    final colWidths = isCampus ? const {
      0: FixedColumnWidth(125), 1: FixedColumnWidth(125),
      2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
      4: FlexColumnWidth(1), 5: FlexColumnWidth(1),
      6: FlexColumnWidth(1),
    } : const {
      0: FixedColumnWidth(125), 1: FixedColumnWidth(125),
      2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
      4: FlexColumnWidth(1), 5: FlexColumnWidth(1),
      6: FlexColumnWidth(1), 7: FlexColumnWidth(1),
    };

    return Table(
      border: TableBorder.all(color: Colors.black, width: 0.5),
      columnWidths: colWidths,
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Padding(padding: EdgeInsets.all(5), child: Text('Activities', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))),
            const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Padding(padding: EdgeInsets.all(5), child: Text('Supporting Documents', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))),
            for (final l in levelsList)
              TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: Center(child: Padding(padding: const EdgeInsets.all(3), child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold))))),
          ],
        ),
      ],
    );
  }

  Widget _buildActivityCategoryTable({
    required String title,
    required String docs,
    required String key,
    required int maxActs,
    required bool isSDGMatrix,
  }) {
    final levels = _selectedOrgType == 'Campus Student Council'
        ? ['intl', 'natl', 'regl', 'univ', 'camp']
        : ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    const double rowHeight = 28.0;

    return IntrinsicHeight(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 125,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.black, width: 0.5)),
                ),
                child: Center(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 125,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.black, width: 0.5)),
                ),
                child: Center(
                  child: Text(
                    docs,
                    style: const TextStyle(fontSize: 7),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: List.generate(maxActs, (actIdx) {
                  final act = actIdx + 1;
                  return Container(
                    height: rowHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: act < maxActs ? Colors.black : Colors.transparent,
                          width: act < maxActs ? 0.5 : 0.0,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final lvl in levels)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: lvl != levels.last ? Colors.black : Colors.transparent,
                                    width: lvl != levels.last ? 0.5 : 0.0,
                                  ),
                                ),
                              ),
                              child: isSDGMatrix
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              border: Border(right: BorderSide(color: Colors.black, width: 0.5)),
                                            ),
                                            child: Center(
                                              child: TextField(
                                                controller: _levelGridControllers['${key}_${act}_${lvl}_sdg'],
                                                textAlign: TextAlign.center,
                                                keyboardType: TextInputType.number,
                                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                                                decoration: const InputDecoration(
                                                  border: InputBorder.none,
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.zero,
                                                  hintText: '—',
                                                ),
                                                onChanged: (val) {
                                                  if (val.trim().isEmpty) {
                                                    _levelGridControllers['${key}_${act}_${lvl}_sdg']?.clear();
                                                  }
                                                  _onGridInputChanged(key, act, lvl, maxActs);
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: TextField(
                                              controller: _levelGridControllers['${key}_${act}_${lvl}_pts'],
                                              textAlign: TextAlign.center,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                                hintText: '—',
                                              ),
                                              onChanged: (val) {
                                                if (val.trim().isEmpty) {
                                                  _levelGridControllers['${key}_${act}_${lvl}_pts']?.clear();
                                                  _levelGridControllers['${key}_${act}_$lvl']?.clear();
                                                }
                                                _onGridInputChanged(key, act, lvl, maxActs);
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Center(
                                      child: TextField(
                                        controller: _levelGridControllers['${key}_${act}_$lvl'] ?? _levelGridControllers['${key}_${act}_${lvl}_pts'],
                                        textAlign: TextAlign.center,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          hintText: '—',
                                        ),
                                        onChanged: (val) {
                                          final cleanVal = val.trim();
                                          if (cleanVal.isEmpty) {
                                            _levelGridControllers['${key}_${act}_${lvl}_pts']?.clear();
                                            _levelGridControllers['${key}_${act}_$lvl']?.clear();
                                          } else {
                                            _levelGridControllers['${key}_${act}_${lvl}_pts']?.text = cleanVal;
                                            _levelGridControllers['${key}_${act}_$lvl']?.text = cleanVal;
                                          }
                                          _onGridInputChanged(key, act, lvl, maxActs);
                                        },
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage2Content() {
    final isCampus = _selectedOrgType == 'Campus Student Council';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoricalHeader(),
        _buildActivityCategoryTable(
          title: 'IV. Socio-Cultural and Sports Activities (10 points)\nMax. No. of Activities: 5 for socio-cultural 5 for sports activities',
          docs: '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper',
          key: 'iv',
          maxActs: 10,
          isSDGMatrix: false,
        ),
        const SizedBox(height: 16),
        _buildActivityCategoryTable(
          title: 'V. Makakalikasan/ Clean and Green Activities and Projects (10 points)\nMax. No. of Activities: ${isCampus ? '5' : '10'}',
          docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU\n• Consent letter/Invitation Letter\n• Narrative report\n• Certificate signed by partner agency\n• Attendance Sheet\n• Documentation',
          key: 'v',
          maxActs: isCampus ? 5 : 10,
          isSDGMatrix: false,
        ),
        const SizedBox(height: 16),
        _buildActivityCategoryTable(
          title: 'VI. Extension Services Sponsored/ Conducted (10 points)\nMax. No. of Activities: 5',
          docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU/ Barangay Resolution\n• Consent/Invitation Letter\n• Narrative report\n• Partner Certificate\n• Attendance Sheet\n• Documentation',
          key: 'vi',
          maxActs: 5,
          isSDGMatrix: false,
        ),
        const SizedBox(height: 12),
        const Text('For activities conducted with co-sponsor, the points will be divided equally. Any Regional Activity conducted should have CHED Endorsement.', style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic)),
        const SizedBox(height: 24),
        const Text('VII. Tangible/ Physical Projects (15 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const Text('• Computation is accumulated amount. Consumables not included. Office equipment for CSC use alone not credited.', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
        const Text('• Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        _buildMappingTable([
          ['25,000 and below', '1.0'],
          ['25,001 – 30,000', '2.0'],
          ['30,001 – 35,000', '3.0'],
        ]),
      ],
    );
  }

  Widget _buildPage3Content() {
    final isCampus = _selectedOrgType == 'Campus Student Council';

    if (isCampus) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMappingTable([
            ['35,001 – 40,000', '4.0'], ['40,001 – 45,000', '5.0'],
            ['45,001 – 50,000', '6.0'], ['50,001 – 55,000', '7.0'],
            ['55,001 – 60,000', '8.0'], ['60,001 – 65,000', '9.0'],
            ['65,001 – 70,000', '10.0'], ['70,001 – 75,000', '11.0'],
            ['75,001 – 80,000', '12.0'], ['80,001 – 85,000', '13.0'],
            ['85,001 – 90,000', '14.0'], ['90,001 – 95,000', '15.0'],
          ], scoreKey: 'vii'),
          const SizedBox(height: 24),
          const Text('VIII. Fund Drive/ IGP (10 points) _______________________', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          _buildMappingTable([
            ['4,001 – 5,000', '1.0'], ['5,001 – 10,000', '1.5'],
            ['10,001 – 15,000', '2.0'], ['15,001 – 20,000', '2.5'],
            ['20,001 – 25,000', '3.0'], ['25,001 – 30,000', '3.5'],
            ['30,001 – 35,000', '4.0'], ['35,001 – 40,000', '4.5'],
            ['40,001 – 45,000', '5.0'], ['45,001 – 50,000', '5.5'],
            ['50,001 – 55,000', '6.0'], ['55,001 – 60,000', '6.5'],
            ['60,001 – 65,000', '7.0'], ['65,001 – 70,000', '7.5'],
            ['70,001 – 75,000', '8.0'], ['75,001 – 80,000', '8.5'],
          ]),
        ],
      );
    }

    final tableVIIIRows = [
      ['4,001 – 5,000', '1.0'], ['5,001 – 10,000', '2.0'],
      ['10,001 – 15,000', '3.0'], ['15,001 – 20,000', '4.0'],
      ['20,001 – 25,000', '5.0'], ['25,001 – 30,000', '6.0'],
      ['30,001 – 35,000', '7.0'], ['35,001 – 40,000', '8.0'],
      ['40,001 – 45,000', '9.0'], ['45,001 – above', '10.0'],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMappingTable([
          ['35,001 – 40,000', '4.0'], ['40,001 – 45,000', '5.0'],
          ['45,001 – 50,000', '6.0'], ['50,001 – 55,000', '7.0'],
          ['55,001 – 60,000', '8.0'], ['60,001 – 65,000', '9.0'],
          ['65,001 – 70,000', '10.0'], ['70,001 – 75,000', '11.0'],
          ['75,001 – 80,000', '12.0'], ['80,001 – 85,000', '13.0'],
          ['85,001 – 90,000', '14.0'], ['90,001 – 95,000', '15.0'],
        ], scoreKey: 'vii'),
        const SizedBox(height: 24),
        const Text('VIII. Fund Drive/ IGP (10 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const Text('• Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        _buildMappingTable(tableVIIIRows, scoreKey: 'viii'),
        const SizedBox(height: 24),
        const Text('IX. Financial Assistance given to members (subsidy to activities and to seminar) (10 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const Text('• Supporting Documents: Disbursement Vouchers, Acknowledgment Receipt, Certificate of Appearance/Proof of Activity Conducted', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        _buildMappingTable([
          ['5,000 and below', '1.0'],
          ['5,001 – 10,000', '2.0'],
          ['10,001 – 15,000', '3.0'],
        ]),
      ],
    );
  }

  Widget _buildPage4Content() {
    final isCampus = _selectedOrgType == 'Campus Student Council';

    if (isCampus) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMappingTable([
            ['80,001 – 85,000', '9.0'],
            ['85,001 – 90,000', '9.5'],
            ['90,001 – 95,000', '10.0'],
          ], headerLabel: 'Amount', scoreKey: 'viii'),
          const SizedBox(height: 24),
          const Text('IX. Financial Assistance given to members (subsidy to activities and to seminar) (10 points) _______________________', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('Supporting Documents: Disbursement Vouchers, Acknowledgment Receipt, Certificate of Appearance/Proof of Activity Conducted', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          _buildMappingTable([
            ['4,001 – 5,000', '1.0'], ['5,001 – 10,000', '1.5'],
            ['10,001 – 15,000', '2.0'], ['15,001 – 20,000', '2.5'],
            ['20,001 – 25,000', '3.0'], ['25,001 – 30,000', '3.5'],
            ['30,001 – 35,000', '4.0'], ['35,001 – 40,000', '4.5'],
            ['40,001 – 45,000', '5.0'], ['45,001 – 50,000', '5.5'],
            ['50,001 – 55,000', '6.0'], ['55,001 – 60,000', '6.5'],
            ['60,001 – 65,000', '7.0'], ['65,001 – 70,000', '7.5'],
            ['70,001 – 75,000', '8.0'], ['75,001 – 80,000', '8.5'],
            ['80,001 – 85,000', '9.0'], ['85,001 – 90,000', '9.5'],
            ['90,001 – 95,000', '10.0'],
          ], scoreKey: 'ix'),
          const SizedBox(height: 24),
          const Text('X. Percentage of Implementation of the Approved Action Plan (10 points) _______________________', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          _buildPercentageTable([
            ['94%-100%', '10'],
            ['88%-93%', '9'],
            ['82%-87%', '8'],
            ['76%-81%', '7'],
            ['70%-75%', '6'],
          ]),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMappingTable([
          ['15,001 – 20,000', '4.0'], ['20,001 – 25,000', '5.0'],
          ['25,001 – 30,000', '6.0'], ['30,001 – 35,000', '7.0'],
          ['35,001 – 40,000', '8.0'], ['40,001 – 45,000', '9.0'],
          ['45,001 – above', '10.0'],
        ], scoreKey: 'ix'),
        const SizedBox(height: 24),
        const Text('X. Percentage of Implementation of the Approved Action Plan (10 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const Text('• Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        _buildMappingTable([
          ['94% - 100%', '10.0'], ['88% - 93%', '9.0'],
          ['82% - 87%', '8.0'], ['76% - 81%', '7.0'],
          ['70% - 75%', '6.0'], ['64% - 69%', '5.0'],
          ['58% - 63%', '4.0'], ['52% - 57%', '3.0'],
          ['46% - 51%', '2.0'], ['40% - 45%', '1.0'],
        ], headerLabel: 'Percentage of Implementation', scoreKey: 'x'),
        const SizedBox(height: 32),
        _buildFinalSummaryTable(),
        const SizedBox(height: 24),
        _buildGrandTotalRow(),
      ],
    );
  }

  Widget _buildFinalSummaryTable() {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 1.5),
      columnWidths: const {0: FlexColumnWidth(4), 1: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade300),
          children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('Sub Categories', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
            const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Score', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
          ],
        ),
        ...[
          ['I. Symposium/ Seminars Conducted (10 points)', 'i'],
          ['II. Convocations/Programs and Literary Activities (10 points)', 'ii'],
          ['III. Religious Activities (5 points)', 'iii'],
          ['IV. Socio-Cultural & Sports Activities (10 points)', 'iv'],
          ['V. Maka-kalikasan/Clean and Green Activities and Projects (10 points)', 'v'],
          ['VI. Extension Services Sponsored/Conducted (10 points)', 'vi'],
          ['VII. Tangible/ Physical Projects (15 points)', 'vii'],
          ['VIII. Fund Drive/ IGP (10 points)', 'viii'],
          ['IX. Financial Assistance given to members (10 points)', 'ix'],
          ['X. Percentage of Implementation of the Approved Action Plan (10 points)', 'x'],
        ].map((s) => TableRow(children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(s[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(s[1])),
        ])),
      ],
    );
  }

  Widget _buildGrandTotalRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text('Grand Total:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(width: 16),
        Container(
          width: 130,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black, width: 2))),
          child: Center(child: Text(grandTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF6366F1)))),
        ),
      ],
    );
  }

  Widget _buildPercentageTable(List<List<String>> rows, {String? scoreKey, String headerLabel = 'Percentage of Implementation'}) {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 0.5),
      columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            Center(child: Padding(padding: const EdgeInsets.all(6), child: Text(headerLabel, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)))),
            const Center(child: Padding(padding: EdgeInsets.all(6), child: Text('Points', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)))),
          ],
        ),
        ...rows.map((r) => TableRow(children: [
          Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(r[0], style: const TextStyle(fontSize: 10)))),
          Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(r[1], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
        ])),
        if (scoreKey != null)
          TableRow(
            decoration: BoxDecoration(color: Colors.blue.shade50),
            children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('Actual Score achieved based on rubric:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(scoreKey)),
            ],
          ),
      ],
    );
  }

  Widget _buildPage5Content() {
    final isCampus = _selectedOrgType == 'Campus Student Council';

    if (isCampus) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPercentageTable([
            ['64%-69%', '5'],
            ['58%-63%', '4'],
            ['52%-57%', '3'],
            ['46%-51%', '2'],
            ['40%-45%', '1'],
          ], scoreKey: 'x'),
          const SizedBox(height: 24),
          _buildFinalSummaryTable(),
          const SizedBox(height: 20),
          _buildGrandTotalRow(),
          const SizedBox(height: 32),
          const Text('Certified True and Correct:', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
          const SizedBox(height: 50),
          _buildSignatureGrid(),
          const SizedBox(height: 50),
          const Text('Noted:', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
          const SizedBox(height: 30),
          _buildNotedBlock(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        const Text('Certified True and Correct:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 60),
        _buildSignatureGrid(),
        const SizedBox(height: 80),
        const Text('Noted:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _buildNotedBlock(),
      ],
    );
  }

  Widget _buildSignatureGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSignatureLine()),
            const SizedBox(width: 40),
            Expanded(child: _buildSignatureLine()),
          ],
        ),
        const SizedBox(height: 60),
        Row(
          children: [
            Expanded(child: _buildSignatureLine()),
            const SizedBox(width: 40),
            Expanded(child: _buildSignatureLine()),
          ],
        ),
      ],
    );
  }

  Widget _buildNotedBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('LORAINE SUYU-TATTAO, Ph.D.', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, decoration: TextDecoration.underline, letterSpacing: 0.5)),
        SizedBox(height: 2),
        Text('University Director', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        Text('Office of the Student Services and Welfare', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildMappingTable(List<List<String>> rows, {String headerLabel = 'Amount', String? scoreKey}) {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 0.5),
      columnWidths: const {0: FlexColumnWidth(3), 1: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade200),
          children: [
            Center(child: Padding(padding: const EdgeInsets.all(6), child: Text(headerLabel, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)))),
            const Center(child: Padding(padding: EdgeInsets.all(6), child: Text('Points', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)))),
          ],
        ),
        ...rows.map((r) => TableRow(children: [
          Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(r[0], style: const TextStyle(fontSize: 10)))),
          Center(child: Padding(padding: const EdgeInsets.all(4), child: Text(r[1], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
        ])),
        if (scoreKey != null)
          TableRow(
            decoration: BoxDecoration(color: Colors.blue.shade50),
            children: [
              const Padding(padding: EdgeInsets.all(8), child: Text('Actual Score achieved based on rubric:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(scoreKey)),
            ],
          ),
      ],
    );
  }

  Widget _buildIntegratedInput(String key) {
    final isSpecialized = (_selectedOrgType ?? '').toLowerCase().contains('special');
    final double maxScore = isSpecialized
        ? (key == 'i' ? 20.0 : (key == 'ii' ? 30.0 : 10.0))
        : ((key == 'vii') ? 15.0 : (key == 'iii' ? 5.0 : 10.0));

    return TextField(
      controller: _controllers[key],
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6366F1)),
      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 2)),
      onChanged: (val) {
        final pts = double.tryParse(val.trim());
        if (pts != null && pts > maxScore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _controllers[key]?.text = maxScore.toStringAsFixed(1);
            if (mounted) setState(() {});
          });
          AppUtils.showTopToast(context, 'Maximum score for this category is ${maxScore.toStringAsFixed(1)} points.', isError: true);
        } else {
          if (mounted) setState(() {});
        }
      },
    );
  }

  Widget _buildSignatureLine() {
    return Column(
      children: [
        Container(height: 1, color: Colors.black),
        const SizedBox(height: 4),
        const Text('Signature over Printed Name of Evaluator', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
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
                      final total = (eval['grand_total'] as num?)?.toDouble() ?? 0.0;
                      final rank = 1 + _evaluations.where((item) =>
                          ((item['grand_total'] as num?)?.toDouble() ?? 0.0) > total).length;
                      final rawRating = (eval['adjectival_rating'] ?? 'N/A').toString();
                      final rating = rawRating.contains('|') ? rawRating.split('|').first : rawRating;
                      
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
                              decoration: BoxDecoration(color: rank <= 3 ? Colors.orange.withValues(alpha: 0.1) : const Color(0xFFF1F5F9), shape: BoxShape.circle),
                              child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, color: rank <= 3 ? Colors.orange : const Color(0xFF64748B))),
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
                final orgActivities = activities.where((a) {
                  final isOrg = a['organization_id']?.toString() == org['id'].toString();
                  final isApproved = ['Approved', 'Scheduled', 'Completed'].contains(a['status']);
                  return isOrg && isApproved;
                }).toList();
                
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
                            Text('${orgActivities.length} Approved', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(org['name'] ?? 'Unknown Org', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: orgActivities.isEmpty ? null : () => _printGPOA(context, org, orgActivities),
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

class _ArchivesView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>>? organizations;

  const _ArchivesView({
    required this.activities,
    this.organizations,
  });

  @override
  State<_ArchivesView> createState() => _ArchivesViewState();
}

class _ArchivesViewState extends State<_ArchivesView> {
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _schoolYear = '2025-2026';
  List<Map<String, dynamic>> _accomplishmentReports = [];
  bool _isLoadingReports = true;

  @override
  void initState() {
    super.initState();
    _fetchAccomplishmentReports();
  }

  Future<void> _fetchAccomplishmentReports() async {
    try {
      final res = await Supabase.instance.client
          .from('accomplishment_reports')
          .select('*, activities(*)');
      if (mounted) {
        setState(() {
          _accomplishmentReports = List<Map<String, dynamic>>.from(res);
          _isLoadingReports = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingReports = false);
    }
  }

  void _openGPOADialog(List<Map<String, dynamic>> acts, String orgName, String? orgId) {
    final org = widget.organizations?.firstWhere(
      (o) => o['id'].toString() == orgId?.toString(),
      orElse: () => {'id': orgId, 'name': orgName, 'type': 'College Student Council'},
    ) ?? {'id': orgId, 'name': orgName, 'type': 'College Student Council'};

    showDialog(
      context: context,
      builder: (ctx) => GPOAPreviewDialog(
        organization: org,
        activities: acts,
        president: const {'full_name': 'Student Leader'},
        adviser: const {'full_name': 'Faculty Adviser'},
        fileName: 'GPOA_${orgName.replaceAll(" ", "_")}.pdf',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const String orgNameFilter = '';
    final archivedDocs = <Map<String, dynamic>>[];

    // 1. Process GPOAs - EXACTLY 1 GPOA ENTRY PER ORGANIZATION
    if (_selectedCategory == 'All' || _selectedCategory == 'GPOA') {
      final Map<String, List<Map<String, dynamic>>> orgActsMap = {};
      final Map<String, String> orgNamesMap = {};

      for (var act in widget.activities) {
        final orgId = act['organization_id']?.toString() ?? 'unknown';
        final orgName = (act['organization_name'] ?? act['organization']?['name'] ?? 'Organization').toString();

        orgNamesMap[orgId] = orgName;
        orgActsMap.putIfAbsent(orgId, () => []).add(act);
      }

      orgActsMap.forEach((orgId, acts) {
        final orgName = orgNamesMap[orgId] ?? 'Organization';

        final query = _searchQuery.toLowerCase();
        if (query.isNotEmpty && !orgName.toLowerCase().contains(query)) {
          return;
        }

        archivedDocs.add({
          'type': 'GPOA',
          'title': 'Approved Annual GPOA - $orgName',
          'org_name': orgName,
          'date': 'SY $_schoolYear',
          'color': const Color(0xFF4F46E5),
          'icon': Icons.description_rounded,
          'acts': acts,
          'org_id': orgId,
          'is_gpoa': true,
        });
      });
    }

    // 2. Process Approved Event Letters
    for (var act in widget.activities) {
      final actTitle = (act['title'] ?? 'Untitled Activity').toString();
      final orgName = (act['organization_name'] ?? act['organization']?['name'] ?? 'Organization').toString();

      final query = _searchQuery.toLowerCase();
      if (query.isNotEmpty && !actTitle.toLowerCase().contains(query) && !orgName.toLowerCase().contains(query)) {
        continue;
      }

      if (act['letter_url'] != null && act['letter_url'].toString().isNotEmpty) {
        if (_selectedCategory == 'All' || _selectedCategory == 'GPOA') {
          archivedDocs.add({
            'type': 'Approved Letter',
            'title': 'Approved Event Letter - $actTitle',
            'org_name': orgName,
            'date': act['proposed_date']?.toString().split('T').first ?? 'SY $_schoolYear',
            'color': const Color(0xFF0284C7),
            'icon': Icons.mark_as_unread_rounded,
            'file_url': act['letter_url'],
            'act': act,
            'is_gpoa': false,
          });
        }
      }
    }

    // 2. Process Accomplishment Reports from Supabase
    for (var rep in _accomplishmentReports) {
      final act = rep['activities'] ?? {};
      final actTitle = (act['title'] ?? rep['title'] ?? 'Activity Report').toString();
      final orgName = (rep['organization_name'] ?? act['organization_name'] ?? 'Organization').toString();

      if (orgNameFilter.isNotEmpty && !orgName.toLowerCase().contains(orgNameFilter)) {
        continue;
      }

      final query = _searchQuery.toLowerCase();
      if (query.isNotEmpty && !actTitle.toLowerCase().contains(query) && !orgName.toLowerCase().contains(query)) {
        continue;
      }

      final rawUrls = rep['file_urls'] ?? rep['report_url'] ?? rep['attachment_url'];
      String? fileUrl;
      if (rawUrls is List && rawUrls.isNotEmpty) {
        fileUrl = rawUrls.first.toString();
      } else if (rawUrls is String && rawUrls.isNotEmpty) {
        fileUrl = rawUrls;
      }

      if (_selectedCategory == 'All' || _selectedCategory == 'Accomplishment') {
        archivedDocs.add({
          'type': 'Accomplishment Report',
          'title': 'Accomplishment Report - $actTitle',
          'org_name': orgName,
          'date': rep['created_at']?.toString().split('T').first ?? 'SY $_schoolYear',
          'color': const Color(0xFF0D9488),
          'icon': Icons.assignment_turned_in_rounded,
          'file_url': fileUrl,
          'act': act,
          'is_gpoa': false,
        });
      }
    }

    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.folder_special_rounded, color: Color(0xFF6366F1), size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Digital Archives', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                      Text('Centralized repository of GPOAs, Accomplishment Reports, and Financial Proofs', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
                child: DropdownButton<String>(
                  value: _schoolYear,
                  underline: const SizedBox(),
                  items: ['2024-2025', '2025-2026', '2026-2027'].map((sy) => DropdownMenuItem(value: sy, child: Text('SY $sy'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _schoolYear = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search by document title, activity, or organization…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Wrap(
                spacing: 8,
                children: ['All', 'GPOA', 'Accomplishment', 'Financial'].map((cat) {
                  final isSel = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSel,
                    onSelected: (s) {
                      if (s) setState(() => _selectedCategory = cat);
                    },
                    selectedColor: const Color(0xFF6366F1),
                    labelStyle: TextStyle(color: isSel ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.bold),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: _isLoadingReports
                ? const Center(child: CircularProgressIndicator())
                : archivedDocs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                            SizedBox(height: 12),
                            Text('No archived documents match your criteria.', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: archivedDocs.length,
                        itemBuilder: (ctx, idx) {
                          final doc = archivedDocs[idx];
                          final Color col = doc['color'];
                          final IconData icon = doc['icon'];
                          final isGPOA = doc['is_gpoa'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: col.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(icon, color: col, size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(doc['title'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B))),
                                      const SizedBox(height: 4),
                                      Text('${doc['org_name']} • ${doc['date']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (isGPOA && doc['acts'] != null) {
                                      final actsList = List<Map<String, dynamic>>.from(doc['acts'] as List);
                                      _openGPOADialog(actsList, doc['org_name'].toString(), doc['org_id']?.toString());
                                    } else if (doc['file_url'] != null && doc['file_url'].toString().isNotEmpty) {
                                      AppUtils.showTopToast(context, 'Opening document URL: ${doc['file_url']}');
                                    } else {
                                      AppUtils.showTopToast(context, 'Viewing ${doc['title']}...');
                                    }
                                  },
                                  icon: Icon(isGPOA ? Icons.picture_as_pdf_rounded : Icons.remove_red_eye_rounded, size: 16),
                                  label: Text(isGPOA ? 'View GPOA' : 'View File'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: col,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
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
