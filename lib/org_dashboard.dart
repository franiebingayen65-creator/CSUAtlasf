import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:csuatlasf/utils/app_utils.dart';
import 'package:csuatlasf/widgets/common_ui.dart';
import 'package:csuatlasf/widgets/gpoa_details.dart';
import 'package:csuatlasf/widgets/pdf_preview_dialog.dart';

class OrgDashboard extends StatefulWidget {
  const OrgDashboard({super.key});
  @override
  State<OrgDashboard> createState() => _OrgDashboardState();
}

class _OrgDashboardState extends State<OrgDashboard> {
  final _supabase = Supabase.instance.client;
  bool _isSidebarCollapsed = false;
  String _activePage = 'Dashboard';
  bool _isLoading = true;
  Map<String, dynamic>? _orgData;
  String? _userRole;
  List<Map<String, dynamic>> _myActivities = [];
  List<Map<String, dynamic>> _orgProfiles = [];
  StreamSubscription? _activitySubscription;

  @override
  void initState() {
    super.initState();
    _fetchOrgData();
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrgData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profileData = await _supabase
          .from('profiles')
          .select('*, organizations(*)')
          .eq('id', user.id);

      if (profileData.isEmpty) {
        if (mounted) setState(() { _orgData = null; _isLoading = false; });
        return;
      }

      final profile = profileData.first;
      _orgData = profile['organizations'];
      _userRole = profile['role'];

      if (_orgData != null) {
        final profilesData = await _supabase.from('profiles').select().eq('organization_id', _orgData!['id']);
        _orgProfiles = List<Map<String, dynamic>>.from(profilesData);

        final activitiesData = await _supabase
            .from('activities')
            .select()
            .eq('organization_id', _orgData!['id']) as List;
        
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
            _myActivities = List<Map<String, dynamic>>.from(activitiesData);
            _isLoading = false;
          });
        }

        _activitySubscription?.cancel();
        _activitySubscription = _supabase
            .from('activities')
            .stream(primaryKey: ['id'])
            .eq('organization_id', _orgData!['id'])
            .listen((data) {
              if (mounted) {
                setState(() { _myActivities = List<Map<String, dynamic>>.from(data); });
                _handleAutoCompletion();
              }
            });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  void _handleAutoCompletion() {
    final now = DateTime.now();
    for (var item in _myActivities) {
      if (item['status'] == 'Scheduled' && item['proposed_date'] != null) {
        try {
          final eventDate = DateTime.parse(item['proposed_date'].toString()).toLocal();
          final duration = AppUtils.parseDuration(item['time_frame']);
          if (eventDate.add(duration).isBefore(now)) {
            _supabase.from('activities').update({'status': 'Completed'}).eq('id', item['id']).then((_) {});
          }
        } catch (_) {}
      }
    }
  }

  void _onPageSelected(String page) {
    setState(() { _activePage = page; });
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_orgData == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('No organization assigned.'),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _showLogoutDialog, child: const Text('Logout'))
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Row(
        children: [
          _OrgSidebar(
            isCollapsed: _isSidebarCollapsed,
            activePage: _activePage,
            onPageSelected: _onPageSelected,
            orgName: _orgData!['name'],
            userRole: _userRole ?? 'President',
            onToggleCollapse: () { setState(() { _isSidebarCollapsed = !_isSidebarCollapsed; }); },
          ),
          Expanded(
            child: Column(
              children: [
                _OrgTopBar(
                  orgName: _orgData!['name'],
                  userRole: _userRole ?? 'President',
                  onLogout: _showLogoutDialog,
                  onProfile: () => _onPageSelected('Profile'),
                  onNavigate: _onPageSelected,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_activePage) {
      case 'Dashboard':
        return _OrgDashboardContent(orgData: _orgData!, activities: _myActivities, userRole: _userRole ?? 'President', onRefresh: _fetchOrgData);
      case 'GPOA Submission':
        return _GPOASubmissionView(orgId: _orgData!['id'], orgType: _orgData!['type']?.toString(), onBack: () => setState(() => _activePage = 'Manage GPOA'));
      case 'Manage GPOA':
        return _GPOAStatusGridView(activities: _myActivities, onAction: (page) => setState(() => _activePage = page), userRole: _userRole ?? 'President', onRefresh: _fetchOrgData);
      case 'GPOA Review':
        return _GPOAReviewView(activities: _myActivities, onRefresh: _fetchOrgData);
      case 'Manage Events':
      case 'View Events':
      case 'Scheduling & Letters':
        return _OrgManageEventsView(activities: _myActivities, onRefresh: _fetchOrgData, userRole: _userRole ?? 'President');
      case 'GPOA Report':
        return _GPOAReportPrintingView(orgData: _orgData!, activities: _myActivities, profiles: _orgProfiles, onBack: () => setState(() => _activePage = 'Manage GPOA'));
      case 'Submit Report':
        return _SubmitReportView(activities: _myActivities, userRole: _userRole ?? 'President', onRefresh: _fetchOrgData);
      case 'Evaluation Scores':
      case 'Organization Ranks':
        return _OrgEvaluationScoresView(orgData: _orgData!);
      case 'Archives':
        return _ArchivesView(orgData: _orgData!, activities: _myActivities, userRole: _userRole ?? 'President');
      case 'Profile':
        return _OrgProfileView(orgData: _orgData!);
      default:
        return _OrgDashboardContent(orgData: _orgData!, activities: _myActivities, userRole: _userRole ?? 'President', onRefresh: _fetchOrgData);
    }
  }
}

class _OrgSidebar extends StatelessWidget {
  final bool isCollapsed;
  final String activePage;
  final Function(String) onPageSelected;
  final VoidCallback onToggleCollapse;
  final String orgName, userRole;

  const _OrgSidebar({
    required this.isCollapsed,
    required this.activePage,
    required this.onPageSelected,
    required this.onToggleCollapse,
    required this.orgName,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
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
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/images/csulogo.png',
                    width: 32,
                    height: 32,
                    errorBuilder: (c, e, s) => const Icon(Icons.school, color: Color(0xFF6366F1), size: 32),
                  ),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ATLAS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1E293B), letterSpacing: 1)),
                        Text(isAdviser ? 'Adviser Portal' : 'Organization Portal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1).withValues(alpha: 0.7), letterSpacing: 0.5)),
                      ],
                    ),
                  ),
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
                  _SidebarItem(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    isSelected: activePage == 'Dashboard',
                    isCollapsed: isCollapsed,
                    onTap: () => onPageSelected('Dashboard'),
                  ),
                  if (!isCollapsed) const _SidebarHeader(title: 'GPOA MANAGEMENT'),
                  _SidebarItem(
                    icon: Icons.grid_view_rounded,
                    title: 'Manage GPOA',
                    isSelected: ['Manage GPOA', 'GPOA Submission', 'GPOA Report'].contains(activePage),
                    isCollapsed: isCollapsed,
                    onTap: () => onPageSelected('Manage GPOA'),
                  ),
                  if (isAdviser)
                    _SidebarItem(
                      icon: Icons.rate_review_rounded,
                      title: 'GPOA Review',
                      isSelected: activePage == 'GPOA Review',
                      isCollapsed: isCollapsed,
                      onTap: () => onPageSelected('GPOA Review'),
                    ),
                  if (!isCollapsed) const _SidebarHeader(title: 'EVENT TRACKING'),
                  _SidebarItem(
                    icon: Icons.calendar_month_rounded,
                    title: 'Manage Events',
                    isSelected: activePage == 'Manage Events' || activePage == 'View Events' || activePage == 'Scheduling & Letters',
                    isCollapsed: isCollapsed,
                    onTap: () => onPageSelected('Manage Events'),
                  ),
                  if (!isCollapsed) const _SidebarHeader(title: 'REPORTS & PERFORMANCE'),
                  _SidebarItem(
                    icon: Icons.upload_file_rounded,
                    title: isAdviser ? 'Review Reports' : 'Submit Report',
                    isSelected: activePage == 'Submit Report',
                    isCollapsed: isCollapsed,
                    onTap: () => onPageSelected('Submit Report'),
                  ),
                  _SidebarItem(
                    icon: Icons.stars_rounded,
                    title: 'Evaluation Scores',
                    isSelected: activePage == 'Evaluation Scores' || activePage == 'Organization Ranks',
                    isCollapsed: isCollapsed,
                    onTap: () => onPageSelected('Evaluation Scores'),
                  ),
                  _SidebarItem(
                    icon: Icons.folder_special_rounded,
                    title: 'Archives',
                    isSelected: activePage == 'Archives',
                    isCollapsed: isCollapsed,
                    onTap: () => onPageSelected('Archives'),
                  ),
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

  const _SidebarItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isSelected = false,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isCollapsed ? title : '',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
              : null,
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

class _OrgTopBar extends StatelessWidget {
  final String orgName, userRole;
  final VoidCallback onLogout, onProfile;
  final Function(String page)? onNavigate;

  const _OrgTopBar({required this.orgName, required this.userRole, required this.onLogout, required this.onProfile, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(orgName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(userRole, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  ],
                )
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
            child: NotificationInboxButton(onNotificationTap: onNavigate),
          ),
          const SizedBox(width: 20),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'logout') onLogout();
              if (val == 'profile') onProfile();
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
              child: const CircleAvatar(radius: 20, backgroundColor: Color(0xFFEDE7F6), child: Icon(Icons.business_rounded, size: 22, color: Color(0xFF6366F1))),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgDashboardContent extends StatelessWidget {
  final Map<String, dynamic> orgData;
  final List<Map<String, dynamic>> activities;
  final String userRole;
  final VoidCallback onRefresh;

  const _OrgDashboardContent({required this.orgData, required this.activities, required this.userRole, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final activeActivities = activities.where((a) => a['is_archived'] != true).toList();
    final pendingCount = activeActivities.where((a) => isAdviser ? a['status'] == 'Pending' : ['Pending', 'Endorsed', 'Awaiting Date Approval'].contains(a['status'])).length;
    final clearedCount = activeActivities.where((a) => ['Approved', 'Scheduled', 'Completed'].contains(a['status'])).length;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back, ${isAdviser ? 'Adviser' : 'President'}!', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                      const SizedBox(height: 8),
                      Text('Here\'s what\'s happening with ${orgData['name']}.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Row(
              children: [
                StatCard(title: 'Total GPOA Activities', value: activeActivities.length.toString(), icon: Icons.assignment_rounded, color: const Color(0xFF3B82F6), onTap: () { (context.findAncestorStateOfType<_OrgDashboardState>())?._onPageSelected('GPOA Status'); }),
                const SizedBox(width: 24),
                StatCard(title: 'Awaiting Action', value: pendingCount.toString(), icon: Icons.timer_rounded, color: const Color(0xFFF59E0B), onTap: () { (context.findAncestorStateOfType<_OrgDashboardState>())?._onPageSelected(isAdviser ? 'GPOA Review' : 'GPOA Status'); }),
                const SizedBox(width: 24),
                StatCard(title: 'Cleared/Ongoing', value: clearedCount.toString(), icon: Icons.verified_rounded, color: const Color(0xFF10B981), onTap: () { (context.findAncestorStateOfType<_OrgDashboardState>())?._onPageSelected('Scheduling & Letters'); }),
              ],
            ),
            const SizedBox(height: 48),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Recent Activity Status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          const Spacer(),
                          TextButton(onPressed: () { (context.findAncestorStateOfType<_OrgDashboardState>())?._onPageSelected('GPOA Status'); }, child: const Text('View All'))
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (activeActivities.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(48),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFF1F5F9))),
                          child: const Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFFCBD5E1)),
                              SizedBox(height: 16),
                              Text('No activities submitted yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: activeActivities.length > 5 ? 5 : activeActivities.length,
                          itemBuilder: (context, index) {
                            final activity = activeActivities[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                                border: Border.all(color: const Color(0xFFF1F5F9)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                onTap: () => _showActivityDetails(context, activity, onRefresh),
                                leading: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16)),
                                  child: const Icon(Icons.description_rounded, color: Color(0xFF6366F1), size: 24),
                                ),
                                title: Text(activity['title'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1E293B))),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(activity['subtitle'] ?? activity['sdgs'] ?? 'GPOA Activity', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                                    const SizedBox(height: 4),
                                    Text('Submitted: ${AppUtils.formatDateTime(activity['created_at'])}', style: TextStyle(fontSize: 10, color: Colors.grey[400], fontStyle: FontStyle.italic)),
                                  ],
                                ),
                                trailing: StatusBadge(status: activity['status']),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  flex: 1,
                  child: _OrgStandingCard(
                    orgName: orgData['name']?.toString() ?? 'Organization',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showActivityDetails(BuildContext context, Map<String, dynamic> activity, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: GPOAActivityDetailsView(
              title: activity['title'] ?? 'Untitled',
              sdgs: activity['sdgs'] ?? 'Not specified',
              objectives: activity['objectives'] ?? 'Not specified',
              outcome: activity['outcome'] ?? 'Not specified',
              participants: activity['participants'] ?? 'Not specified',
              timeFrame: activity['time_frame'] ?? 'Not specified',
              delivery: activity['delivery_strategy'] ?? 'Not specified',
              persons: activity['persons_involved'] ?? 'Not specified',
              facilities: activity['facilities_materials'] ?? 'Not specified',
              budget: activity['budget_allocation'] ?? 'Not specified',
              status: activity['status'] ?? 'Pending',
              createdAt: AppUtils.formatDateTime(activity['created_at']),
              proposedDate: activity['proposed_date'] != null ? AppUtils.formatDateTime(activity['proposed_date']) : null,
              onStatusUpdate: activity['status'] == 'Needs Revision' ? (s) async {
                try {
                  await Supabase.instance.client.from('activities').update({'status': 'Pending'}).eq('id', activity['id']);
                  if (!context.mounted) return;
                  AppUtils.showTopToast(context, 'Activity resubmitted for review.');
                  onRefresh();
                  Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
                }
              } : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrgStandingCard extends StatefulWidget {
  final String orgName;
  const _OrgStandingCard({required this.orgName});

  @override
  State<_OrgStandingCard> createState() => _OrgStandingCardState();
}

class _OrgStandingCardState extends State<_OrgStandingCard> {
  static const _schoolYear = '2025-2026';
  Map<String, dynamic>? _standing;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStanding();
  }

  Future<void> _loadStanding() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_my_organization_ranking',
        params: {'p_school_year': _schoolYear},
      );
      if (!mounted) return;
      setState(() {
        _standing = result is List && result.isNotEmpty
            ? Map<String, dynamic>.from(result.first as Map)
            : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawRating = _standing?['adjectival_rating']?.toString() ?? 'Pending Evaluation';
    final rating = rawRating.contains('|') ? rawRating.split('|').first : rawRating;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.star_rounded, color: Color(0xFF6366F1), size: 24)),
            const SizedBox(width: 16),
            const Text('Evaluation Score', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 32),
          const Text('TOTAL EVALUATION SCORE', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(
            _isLoading
                ? 'Loading…'
                : _standing == null
                    ? 'No score yet'
                    : '${(((_standing!['grand_total'] as num?)?.toDouble()) ?? 0).toStringAsFixed(2)} PTS',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF6366F1)),
          ),
          if (_standing != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(
                rating.toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GPOASubmissionView extends StatefulWidget {
  final String orgId;
  final String? orgType;
  final VoidCallback onBack;
  const _GPOASubmissionView({required this.orgId, this.orgType, required this.onBack});
  @override
  State<_GPOASubmissionView> createState() => _GPOASubmissionViewState();
}

class _GPOASubmissionViewState extends State<_GPOASubmissionView> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedType;
  List<String> get _activityTypes {
    final type = (widget.orgType ?? '').toLowerCase();
    if (type.contains('specialized') || type.contains('special')) {
      return const [
        'Symposium /Seminars Conducted',
        'Activities Conducted /Sponsored in line with the nature of the organization',
        'Makakalikasan/ Clean and Green Activities and Projects',
        'Extension Services Sponsored/ Conducted',
      ];
    }
    return const [
      'Symposium/ Seminars Conducted',
      'Convocations/ Programs and Literary Activities',
      'Religious Activities',
      'Socio-Cultural and Sports Activities',
      'Makakalikasan/ Clean and Green Activities and Projects',
      'Extension Services Sponsored/ Conducted',
    ];
  }
  final List<String> _sdgList = [
    'SDG 1: No Poverty', 'SDG 2: Zero Hunger', 'SDG 3: Good Health and Well-being', 'SDG 4: Quality Education', 'SDG 5: Gender Equality',
    'SDG 6: Clean Water and Sanitation', 'SDG 7: Affordable and Clean Energy', 'SDG 8: Decent Work and Economic Growth', 'SDG 9: Industry, Innovation and Infrastructure',
    'SDG 10: Reduced Inequality', 'SDG 11: Sustainable Cities and Communities', 'SDG 12: Responsible Consumption and Production', 'SDG 13: Climate Action',
    'SDG 14: Life Below Water', 'SDG 15: Life on Land', 'SDG 16: Peace, Justice and Strong Institutions', 'SDG 17: Partnerships for the Goals'
  ];
  final List<String> _selectedSDGs = [];
  final List<String> _participantOptions = ['1st year Students', '2nd Year Students', '3rd Year Students', '4th Year Students', 'Transferees', 'Officers and Mayors', 'Faculty Staffs', 'All Students', 'All student of CSU Lal-lo'];
  final List<String> _selectedParticipants = [];
  final List<String> _selectedPersons = [];
  final Map<String, TextEditingController> _controllers = {
    'title': TextEditingController(),
    'objectives': TextEditingController(),
    'outcome': TextEditingController(),
    'timeFrame': TextEditingController(),
    'delivery': TextEditingController(),
    'facilities': TextEditingController(),
    'budget': TextEditingController(),
  };
  bool _isSubmitting = false;

  Future<void> _submitGPOA() async {
    if (!_formKey.currentState!.validate() || _selectedType == null) {
      if (_selectedType == null) AppUtils.showTopToast(context, 'Please select an activity type.', isError: true);
      return;
    }
    if (_selectedSDGs.isEmpty) { AppUtils.showTopToast(context, 'Please select at least one SDG.', isError: true); return; }
    if (_selectedParticipants.isEmpty) { AppUtils.showTopToast(context, 'Please select target participants.', isError: true); return; }
    if (_selectedPersons.isEmpty) { AppUtils.showTopToast(context, 'Please select persons involved.', isError: true); return; }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Submission'),
        content: const Text('Are you sure you want to submit this GPOA Activity proposal?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.from('activities').insert({
        'organization_id': widget.orgId,
        'title': _controllers['title']!.text,
        'subtitle': _selectedType,
        'description': _controllers['objectives']!.text,
        'sdgs': _selectedSDGs.join(', '),
        'objectives': _controllers['objectives']!.text,
        'outcome': _controllers['outcome']!.text,
        'participants': _selectedParticipants.join(', '),
        'time_frame': _controllers['timeFrame']!.text,
        'delivery_strategy': _controllers['delivery']!.text,
        'persons_involved': _selectedPersons.join(', '),
        'facilities_materials': _controllers['facilities']!.text,
        'budget_allocation': _controllers['budget']!.text,
        'status': 'Pending',
        'proposed_date': null,
      });

      if (!mounted) return;
      AppUtils.showTopToast(context, 'GPOA Activity submitted successfully!');
      _formKey.currentState!.reset();
      setState(() {
        _selectedType = null;
        _selectedSDGs.clear();
        _selectedParticipants.clear();
        _selectedPersons.clear();
      });
      for (var c in _controllers.values) {
        c.clear();
      }
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSDGSelector() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select SDGs Addressed'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _sdgList.map((sdg) {
                  final isSelected = _selectedSDGs.contains(sdg);
                  return CheckboxListTile(
                    title: Text(sdg, style: const TextStyle(fontSize: 13)),
                    value: isSelected,
                    dense: true,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          _selectedSDGs.add(sdg);
                        } else {
                          _selectedSDGs.remove(sdg);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      ),
    );
  }

  void _showParticipantSelector() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Target Participants'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _participantOptions.map((opt) {
                  final isSelected = _selectedParticipants.contains(opt);
                  return CheckboxListTile(
                    title: Text(opt, style: const TextStyle(fontSize: 13)),
                    value: isSelected,
                    dense: true,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          _selectedParticipants.add(opt);
                        } else {
                          _selectedParticipants.remove(opt);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      ),
    );
  }

  void _showPersonsSelector() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Persons Involved'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _participantOptions.map((opt) {
                  final isSelected = _selectedPersons.contains(opt);
                  return CheckboxListTile(
                    title: Text(opt, style: const TextStyle(fontSize: 13)),
                    value: isSelected,
                    dense: true,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          _selectedPersons.add(opt);
                        } else {
                          _selectedPersons.remove(opt);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              style: IconButton.styleFrom(backgroundColor: Colors.white, elevation: 2),
            ),
            const SizedBox(width: 20),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.note_add_rounded, color: Color(0xFF6366F1), size: 32)),
            const SizedBox(width: 20),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Submit GPOA Activity', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5)),
              Text('Draft a new activity proposal for your organization.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500)),
            ])
          ]),
          const SizedBox(height: 40),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFormSection(
                  title: 'BASIC INFORMATION',
                  icon: Icons.info_outline_rounded,
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: _buildField('Activity Title', 'title', Icons.title_rounded)),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedType,
                          decoration: InputDecoration(
                            labelText: 'Activity Type',
                            prefixIcon: const Icon(Icons.category_rounded, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
                          ),
                          items: _activityTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (val) => setState(() => _selectedType = val),
                          validator: (val) => val == null ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildFormSection(
                  title: 'STRATEGIC ALIGNMENT',
                  icon: Icons.track_changes_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sustainable Development Goals (SDGs) Addressed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _showSDGSelector,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: Colors.white),
                          child: Row(
                            children: [
                              const Icon(Icons.public_rounded, size: 20, color: Color(0xFF64748B)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _selectedSDGs.isEmpty
                                    ? const Text('Click to select relevant SDGs', style: TextStyle(color: Colors.grey))
                                    : Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: _selectedSDGs.map((s) => Chip(
                                              backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                              side: BorderSide.none,
                                              label: Text(s.split(':').first, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                                              onDeleted: () { setState(() => _selectedSDGs.remove(s)); },
                                              deleteIconColor: const Color(0xFF6366F1),
                                              deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                            )).toList(),
                                      ),
                              ),
                              const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildFormSection(
                  title: 'EXECUTION PLAN',
                  icon: Icons.rocket_launch_rounded,
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                          child: _TimeFrameInput(controller: _controllers['timeFrame']!),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: _buildField('Budget Allocation (₱)', 'budget', Icons.payments_rounded, isNumeric: true)),
                      ]),
                      const SizedBox(height: 24),
                      _buildMultiselectField(label: 'Target Participants', icon: Icons.groups_rounded, selectedItems: _selectedParticipants, onTap: _showParticipantSelector, hint: 'Who will participate in this activity?'),
                      const SizedBox(height: 24),
                      _buildMultiselectField(label: 'Persons Involved', icon: Icons.people_alt_rounded, selectedItems: _selectedPersons, onTap: _showPersonsSelector, hint: 'Who are the organizers/staff?'),
                      const SizedBox(height: 24),
                      _buildField('Delivery Strategy', 'delivery', Icons.map_rounded, maxLines: 5),
                      const SizedBox(height: 24),
                      _buildField('Facilities & Materials Needed', 'facilities', Icons.business_rounded, maxLines: 3),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _buildFormSection(
                  title: 'GOALS & OUTCOMES',
                  icon: Icons.verified_user_rounded,
                  child: Column(children: [
                    _buildField('Objectives', 'objectives', Icons.flag_rounded, maxLines: 5),
                    const SizedBox(height: 24),
                    _buildField('Expected Outcome', 'outcome', Icons.stars_rounded, maxLines: 5),
                  ]),
                ),
                const SizedBox(height: 48),
                Container(
                  width: double.infinity,
                  height: 64,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitGPOA,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                    child: _isSubmitting
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Text('SUBMIT ACTIVITY PROPOSAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildMultiselectField({required String label, required IconData icon, required List<String> selectedItems, required VoidCallback onTap, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
        const SizedBox(height: 12),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: Colors.white),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF64748B)),
                const SizedBox(width: 12),
                Expanded(
                  child: selectedItems.isEmpty
                      ? Text(hint, style: const TextStyle(color: Colors.grey))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: selectedItems.map((p) => Chip(
                                backgroundColor: Colors.blue.withValues(alpha: 0.05),
                                side: BorderSide.none,
                                padding: EdgeInsets.zero,
                                label: Text(p, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                                onDeleted: () { setState(() { selectedItems.remove(p); }); },
                                deleteIconColor: const Color(0xFF2563EB),
                                deleteIcon: const Icon(Icons.close_rounded, size: 12),
                              )).toList(),
                        ),
                ),
                const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(String label, String key, IconData icon, {int maxLines = 1, bool isNumeric = false, String? hint}) {
    List<TextInputFormatter>? formatters;
    if (isNumeric) {
      formatters = [FilteringTextInputFormatter.digitsOnly];
    }
    return TextFormField(
      controller: _controllers[key],
      maxLines: maxLines,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.multiline,
      inputFormatters: formatters,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }
}

// Manage Events Combined View Component
class _OrgManageEventsView extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;
  final String userRole;

  const _OrgManageEventsView({required this.activities, required this.onRefresh, required this.userRole});

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final activeActivities = activities.where((a) => a['is_archived'] != true);
    final schedulingList = activeActivities.where((a) => ['Approved', 'Awaiting Date Approval'].contains(a['status'])).toList();
    final revisionList = activeActivities.where((a) => a['status'] == 'Needs Revision').toList();
    final letterList = activeActivities.where((a) => a['status'] == 'Scheduled').toList();

    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isAdviser ? 'Event Calendar & Tracking' : 'Manage Events', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
            Text(isAdviser ? 'Monitor and oversee event schedule and approvals.' : 'Schedule event dates, manage activity revisions, and track request letters.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 16)),
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
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_month_rounded, size: 18), const SizedBox(width: 8), Text('Event Scheduling (${schedulingList.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_edu_rounded, size: 18), const SizedBox(width: 8), Text('Activity Corrections (${revisionList.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.mark_email_read_rounded, size: 18), const SizedBox(width: 8), Text('Request Letters (${letterList.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: TabBarView(
                children: [
                  _buildEventList(context, schedulingList, tabType: 'scheduling'),
                  _buildEventList(context, revisionList, tabType: 'corrections'),
                  _buildEventList(context, letterList, tabType: 'letters'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventList(BuildContext context, List<Map<String, dynamic>> list, {required String tabType}) {
    final isAdviser = userRole == 'Adviser';
    String emptyText = 'No activities found.';
    IconData emptyIcon = Icons.inbox_rounded;

    if (tabType == 'scheduling') {
      emptyText = 'No activities ready for scheduling.';
      emptyIcon = Icons.calendar_today_outlined;
    } else if (tabType == 'corrections') {
      emptyText = 'No activities needing correction.';
      emptyIcon = Icons.edit_notifications_outlined;
    } else if (tabType == 'letters') {
      emptyText = 'No activities ready for request letters.';
      emptyIcon = Icons.mail_outline_rounded;
    }

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 48, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            Text(emptyText, style: const TextStyle(color: Color(0xFF94A3B8))),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final event = list[index];
        final status = event['status'];
        final hasDate = event['proposed_date'] != null;
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: (status == 'Scheduled' ? Colors.green : Colors.blue).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                  child: Icon(status == 'Scheduled' ? Icons.event_available : Icons.event, color: status == 'Scheduled' ? Colors.green : Colors.blue, size: 24),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Row(children: [const Text('Current Status: ', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))), StatusBadge(status: status)]),
                      const SizedBox(height: 4),
                      Text(hasDate ? 'Scheduled Date: ${AppUtils.formatDateTime(event['proposed_date'])}' : 'Date & Time: Not selected', style: TextStyle(color: hasDate ? const Color(0xFF0F172A) : Colors.red, fontSize: 13, fontWeight: hasDate ? FontWeight.w600 : FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => _showActivityDetails(context, event, onRefresh), icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF94A3B8))),
                const SizedBox(width: 8),
                if (!isAdviser) _buildAction(context, event, onRefresh),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAction(BuildContext context, Map<String, dynamic> event, VoidCallback onRefresh) {
    final status = event['status'];
    if (['Approved', 'Awaiting Date Approval', 'Needs Revision'].contains(status)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'Needs Revision')
            ElevatedButton.icon(
              onPressed: () => _handleRevision(context, event, onRefresh), 
              icon: const Icon(Icons.edit_calendar_rounded, size: 16), 
              label: const Text('Revise Schedule'), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, elevation: 0),
            )
          else ...[
            IconButton(
              onPressed: () => _selectDate(context, event, onRefresh), 
              icon: const Icon(Icons.edit_calendar_rounded, color: Color(0xFF6366F1)),
              tooltip: 'Pick Date',
            ),
            if (status == 'Approved')
              ElevatedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirm Submission'),
                      content: const Text('Are you sure you want to submit this event for date approval?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)), child: const Text('Submit')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    if (context.mounted) {
                      _requestDateApproval(context, event, onRefresh);
                    }
                  }
                },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Submit'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, elevation: 0),
              )
            else
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Text('Pending Approval', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
          ],
        ],
      );
    } else if (status == 'Scheduled') {
      final hasLetter = event['letter_url'] != null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasLetter)
            IconButton(onPressed: () async { final url = Uri.parse(event['letter_url'].toString()); if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); }, icon: const Icon(Icons.file_present_rounded, color: Colors.blue)),
          ElevatedButton.icon(onPressed: () => _uploadLetter(context, event, onRefresh), icon: Icon(hasLetter ? Icons.sync_rounded : Icons.upload_file_rounded, size: 16), label: Text(hasLetter ? 'Update Letter' : 'Upload Letter'), style: ElevatedButton.styleFrom(backgroundColor: hasLetter ? Colors.blue : const Color(0xFF10B981), foregroundColor: Colors.white, elevation: 0)),
        ],
      );
    }
    return const SizedBox();
  }

  void _handleRevision(BuildContext context, Map<String, dynamic> event, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (ctx) => _ReviseActivityDialog(
        activity: event,
        userRole: userRole,
        onRefreshed: onRefresh,
      ),
    );
  }

  void _showActivityDetails(BuildContext context, Map<String, dynamic> activity, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Activity Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(),
                GPOAActivityDetailsView(
                  title: activity['title'] ?? 'Untitled',
                  sdgs: activity['sdgs'] ?? 'Not specified',
                  objectives: activity['objectives'] ?? 'Not specified',
                  outcome: activity['outcome'] ?? 'Not specified',
                  participants: activity['participants'] ?? 'Not specified',
                  timeFrame: activity['time_frame'] ?? 'Not specified',
                  delivery: activity['delivery_strategy'] ?? 'Not specified',
                  persons: activity['persons_involved'] ?? 'Not specified',
                  facilities: activity['facilities_materials'] ?? 'Not specified',
                  budget: activity['budget_allocation'] ?? 'Not specified',
                  status: activity['status'] ?? 'Pending',
                  createdAt: AppUtils.formatDateTime(activity['created_at']),
                  proposedDate: activity['proposed_date'] != null ? AppUtils.formatDateTime(activity['proposed_date']) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadLetter(BuildContext context, Map<String, dynamic> event, VoidCallback onRefresh) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png']);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final fileName = 'letters/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      if (kIsWeb) {
        if (file.bytes == null) {
          return;
        }
        await Supabase.instance.client.storage.from('documents').uploadBinary(fileName, file.bytes!);
      } else {
        final path = file.path;
        if (path == null) {
          return;
        }
        await Supabase.instance.client.storage.from('documents').uploadBinary(fileName, await file.xFile.readAsBytes());
      }
      final url = Supabase.instance.client.storage.from('documents').getPublicUrl(fileName);
      await Supabase.instance.client.from('activities').update({'letter_url': url}).eq('id', event['id']);
      if (context.mounted) onRefresh();
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Upload failed: $e', isError: true);
    }
  }

  Future<void> _selectDate(BuildContext context, Map<String, dynamic> event, VoidCallback onRefresh) async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    DateTime initialDateValue = event['proposed_date'] != null ? DateTime.parse(event['proposed_date'].toString()).toLocal() : now;
    if (initialDateValue.isBefore(firstDate)) {
      initialDateValue = firstDate;
    }

    final DateTime? pickedDate = await showDatePicker(context: context, initialDate: initialDateValue, firstDate: firstDate, lastDate: DateTime(now.year + 5));
    if (pickedDate != null) {
      if (!context.mounted) {
        return;
      }
      final TimeOfDay? pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDateValue));
      if (pickedTime != null) {
        final DateTime finalDateTime = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
        try {
          await Supabase.instance.client.from('activities').update({'proposed_date': finalDateTime.toUtc().toIso8601String()}).eq('id', event['id']);
          if (context.mounted) {
            onRefresh();
          }
        } catch (e) {
          if (context.mounted) {
            AppUtils.showTopToast(context, 'Error: $e', isError: true);
          }
        }
      }
    }
  }

  Future<void> _requestDateApproval(BuildContext context, Map<String, dynamic> event, VoidCallback onRefresh) async {
    if (event['proposed_date'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a date first.')));
      return;
    }
    try {
      await Supabase.instance.client.from('activities').update({'status': 'Awaiting Date Approval'}).eq('id', event['id']);
      if (context.mounted) {
        AppUtils.showTopToast(context, 'Event submitted for date approval!');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }
}

// Adviser Review View
class _GPOAReviewView extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;

  const _GPOAReviewView({required this.activities, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final reviewList = activities.where((a) => ['Pending', 'Needs Revision'].contains(a['status'])).toList();

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GPOA Review Queue', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text('Endorse proposals or track revisions.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Expanded(
            child: reviewList.isEmpty
                ? const Center(child: Text('No activities in review.'))
                : ListView.builder(
                    itemCount: reviewList.length,
                    itemBuilder: (context, index) {
                      final activity = reviewList[index];
                      final isWaiting = activity['status'] == 'Needs Revision';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: GPOAActivityDetailsView(
                          title: activity['title'] ?? 'Untitled',
                          sdgs: activity['sdgs'] ?? '',
                          objectives: activity['objectives'] ?? '',
                          outcome: activity['outcome'] ?? '',
                          participants: activity['participants'] ?? '',
                          timeFrame: activity['time_frame'] ?? '',
                          delivery: activity['delivery_strategy'] ?? '',
                          persons: activity['persons_involved'] ?? '',
                          facilities: activity['facilities_materials'] ?? '',
                          budget: activity['budget_allocation'] ?? '',
                          status: activity['status'] ?? 'Pending',
                          createdAt: AppUtils.formatDateTime(activity['created_at']),
                          proposedDate: activity['proposed_date'] != null ? AppUtils.formatDateTime(activity['proposed_date']) : null,
                          onStatusUpdate: isWaiting ? null : (s) async {
                            if (s == 'Needs Revision' || s == 'Rejected') {
                              final remarkController = TextEditingController();
                              final isReject = s == 'Rejected';
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(isReject ? 'Reject GPOA' : 'Return for Revision'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(isReject ? 'Reason for rejection:' : 'Explain needs changes:'),
                                      const SizedBox(height: 16),
                                      TextField(controller: remarkController, decoration: const InputDecoration(labelText: 'Remarks', border: OutlineInputBorder()), maxLines: 4),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: isReject ? Colors.red : Colors.orange), child: Text(isReject ? 'Reject' : 'Send Feedback')),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                              try {
                                await Supabase.instance.client.from('activities').update({'status': s, 'remarks': remarkController.text}).eq('id', activity['id']);
                                if (context.mounted) AppUtils.showTopToast(context, s == 'Rejected' ? 'Proposal rejected.' : 'Feedback sent.');
                                onRefresh();
                              } catch (e) {
                                if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
                              }
                            } else {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Confirm Endorsement'),
                                  content: const Text('Are you sure you want to endorse this activity proposal?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Endorse')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                if (context.mounted) {
                                  _updateStatus(context, activity['id'], s);
                                  AppUtils.showTopToast(context, 'GPOA Endorsed successfully!');
                                }
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, dynamic id, String s) async {
    try {
      await Supabase.instance.client.from('activities').update({'status': s}).eq('id', id);
      onRefresh();
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }
}

// Reports View Component
class _SubmitReportView extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final String userRole;
  final VoidCallback onRefresh;

  const _SubmitReportView({required this.activities, required this.userRole, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final completed = activities.where((a) => a['is_archived'] != true && ['Completed', 'Scheduled'].contains(a['status'])).toList();

    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAdviser ? 'Review Accomplishment Reports' : 'Submit Accomplishment Reports',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAdviser ? 'Review and approve submitted activity accomplishment reports.' : 'Upload narrative reports, photos, and proof for completed activities.',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: completed.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.assignment_turned_in_outlined, size: 52, color: Color(0xFF94A3B8)),
                        SizedBox(height: 12),
                        Text('No activities require accomplishment reports at this time.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                      ],
                    ),
                  )
                : FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchReports(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      final reports = snapshot.data ?? [];

                      return ListView.builder(
                        itemCount: completed.length,
                        itemBuilder: (context, index) {
                          final activity = completed[index];
                          final report = reports.cast<Map<String, dynamic>?>().firstWhere((r) => r?['activity_id'] == activity['id'], orElse: () => null);

                          final hasReport = report != null;
                          final reportStatus = report?['status'] ?? 'Pending Submission';
                          final isReportApproved = reportStatus == 'Approved';

                          final eventDateText = activity['proposed_date'] != null
                              ? AppUtils.formatDateTime(activity['proposed_date'])
                              : 'Not selected';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF5FF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.purple.shade100),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.calendar_today_rounded, color: Color(0xFF6366F1), size: 24),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        activity['title'] ?? 'Untitled Activity',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B)),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Text('Current Status: ', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                          StatusBadge(status: hasReport ? reportStatus : 'Approved'),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Date & Time: $eventDateText',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: activity['proposed_date'] == null ? const Color(0xFFDC2626) : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'View Details',
                                      icon: const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 22),
                                      onPressed: () => _showActivityDetails(context, activity),
                                    ),
                                    if (hasReport) ...[
                                      IconButton(
                                        tooltip: 'View Files',
                                        icon: const Icon(Icons.remove_red_eye_rounded, color: Color(0xFF6366F1), size: 22),
                                        onPressed: () async {
                                          final attachments = report['attachments'];
                                          if (attachments is List && attachments.isNotEmpty) {
                                            final url = Uri.parse(attachments.first.toString());
                                            if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                                          } else {
                                            AppUtils.showTopToast(context, 'No attachment file available.');
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (isAdviser && hasReport && !isReportApproved) ...[
                                      ElevatedButton(
                                        onPressed: () => _updateReportStatus(report['id'], 'Approved'),
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, elevation: 0),
                                        child: const Text('Approve', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () => _updateReportStatus(report['id'], 'Needs Revision'),
                                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFDC2626))),
                                        child: const Text('Return', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      ),
                                    ] else if (!isAdviser && !isReportApproved) ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _showSubmitReportModal(context, activity, report),
                                        icon: const Icon(Icons.send_rounded, size: 16),
                                        label: Text(hasReport ? 'Revise Report' : 'Submit'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
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

  void _showActivityDetails(BuildContext context, Map<String, dynamic> activity) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: GPOAActivityDetailsView(
              title: activity['title'] ?? 'Untitled',
              sdgs: activity['sdgs'] ?? '',
              objectives: activity['objectives'] ?? '',
              outcome: activity['outcome'] ?? '',
              participants: activity['participants'] ?? '',
              timeFrame: activity['time_frame'] ?? '',
              delivery: activity['delivery_strategy'] ?? '',
              persons: activity['persons_involved'] ?? '',
              facilities: activity['facilities_materials'] ?? '',
              budget: activity['budget_allocation'] ?? '',
              status: activity['status'] ?? 'Pending',
              createdAt: AppUtils.formatDateTime(activity['created_at']),
              proposedDate: activity['proposed_date'] != null ? AppUtils.formatDateTime(activity['proposed_date']) : null,
            ),
          ),
        ),
      ),
    );
  }

  void _showSubmitReportModal(BuildContext context, Map<String, dynamic> activity, Map<String, dynamic>? existingReport) {
    showDialog(
      context: context,
      builder: (ctx) => _SubmitReportDialog(
        activity: activity,
        existingReport: existingReport,
        onRefresh: onRefresh,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchReports() async {
    final response = await Supabase.instance.client
        .from('accomplishment_reports')
        .select()
        .eq('is_archived', false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _updateReportStatus(dynamic reportId, String status) async {
    try {
      await Supabase.instance.client.from('accomplishment_reports').update({'status': status}).eq('id', reportId);
      onRefresh();
    } catch (e) {
      debugPrint('Error updating report status: $e');
    }
  }
}

class _SubmitReportDialog extends StatefulWidget {
  final Map<String, dynamic> activity;
  final Map<String, dynamic>? existingReport;
  final VoidCallback onRefresh;

  const _SubmitReportDialog({
    required this.activity,
    this.existingReport,
    required this.onRefresh,
  });

  @override
  State<_SubmitReportDialog> createState() => _SubmitReportDialogState();
}

class _SubmitReportDialogState extends State<_SubmitReportDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _summaryController;
  final List<FilePickerResult> _selectedFiles = [];
  final List<String> _existingUrls = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final rep = widget.existingReport;
    _titleController = TextEditingController(text: rep?['title']?.toString() ?? 'Accomplishment Report: ${widget.activity['title']}');
    _summaryController = TextEditingController(text: rep?['summary']?.toString() ?? '');

    final rawAttach = rep?['attachments'];
    if (rawAttach is List) {
      _existingUrls.addAll(rawAttach.map((e) => e.toString()));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'zip', 'jpg', 'png', 'docx'],
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles.add(result);
      });
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final List<String> uploadUrls = List<String>.from(_existingUrls);

      for (var pResult in _selectedFiles) {
        for (var file in pResult.files) {
          final fileName = 'reports/${widget.activity['id']}_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          if (kIsWeb) {
            await Supabase.instance.client.storage.from('documents').uploadBinary(fileName, file.bytes!);
          } else {
            await Supabase.instance.client.storage.from('documents').uploadBinary(fileName, await file.xFile.readAsBytes());
          }
          uploadUrls.add(Supabase.instance.client.storage.from('documents').getPublicUrl(fileName));
        }
      }

      if (widget.existingReport != null) {
        await Supabase.instance.client.from('accomplishment_reports').update({
          'title': _titleController.text.trim(),
          'summary': _summaryController.text.trim(),
          'attachments': uploadUrls,
          'status': 'Pending',
          'report_date': DateTime.now().toIso8601String(),
          'is_archived': false,
        }).eq('id', widget.existingReport!['id']);
      } else {
        await Supabase.instance.client.from('accomplishment_reports').insert({
          'organization_id': widget.activity['organization_id'],
          'activity_id': widget.activity['id'],
          'title': _titleController.text.trim(),
          'summary': _summaryController.text.trim(),
          'attachments': uploadUrls,
          'status': 'Pending',
          'report_date': DateTime.now().toIso8601String(),
        });
      }

      try {
        final orgName = widget.activity['organization_name'] ?? 'Organization';
        await Supabase.instance.client.from('notifications').insert({
          'title': 'Accomplishment Report Submitted',
          'body': '$orgName submitted accomplishment report for "${widget.activity['title']}".',
          'status': 'Pending',
        });
      } catch (_) {}

      if (mounted) {
        Navigator.pop(context);
        AppUtils.showTopToast(context, 'Accomplishment report submitted successfully!');
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppUtils.showTopToast(context, 'Error submitting report: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final actTitle = widget.activity['title'] ?? 'Activity';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.upload_file_rounded, color: Color(0xFF6366F1), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Submit Accomplishment Report', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        Text(actTitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 28),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Report Title',
                          prefixIcon: const Icon(Icons.title_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _summaryController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'Accomplishment Summary & Highlights',
                          alignLabelWithHint: true,
                          prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          hintText: 'Briefly summarize key outcomes, attendance, and impact…',
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Report Attachments & Proofs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickFiles,
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: const Text('Attach Narrative Report / Photos / Vouchers'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6366F1),
                          side: const BorderSide(color: Color(0xFF6366F1)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      if (_selectedFiles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedFiles.expand((res) => res.files).map((f) => Chip(
                            avatar: const Icon(Icons.insert_drive_file_rounded, size: 14, color: Color(0xFF6366F1)),
                            label: Text(f.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitReport,
                  icon: _isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Proposal Tracking View
class _GPOAStatusGridView extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final Function(String) onAction;
  final String userRole;
  final VoidCallback onRefresh;
  const _GPOAStatusGridView({required this.activities, required this.onAction, required this.userRole, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final activeActivities = activities.where((a) => a['is_archived'] != true).toList();
    final archived = activities.where((a) => a['is_archived'] == true).toList();
    final inReview = activeActivities.where((a) => ['Pending', 'Endorsed'].contains(a['status'])).toList();
    final approved = activeActivities.where((a) => a['status'] == 'Approved').toList();
    final revision = activeActivities.where((a) => a['status'] == 'Needs Revision').toList();
    final declined = activeActivities.where((a) => a['status'] == 'Rejected').toList();
    final isAdviser = userRole == 'Adviser';

    return DefaultTabController(
      length: 5,
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Manage GPOA', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                    const Text('Monitor the approval life-cycle of your submitted GPOA activities.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                  ],
                ),
                Row(
                  children: [
                    if (!isAdviser)
                      ElevatedButton.icon(
                        onPressed: () => onAction('GPOA Submission'),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('New Proposal'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => onAction('GPOA Report'),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Generate Report'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
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
                  Tab(child: Text('Under Review (${inReview.length})', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Tab(child: Text('Approved (${approved.length})', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Tab(child: Text('Needs Correction (${revision.length})', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Tab(child: Text('Declined (${declined.length})', style: const TextStyle(fontWeight: FontWeight.bold))),
                  Tab(child: Text('Archived (${archived.length})', style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: TabBarView(
                children: [
                  _buildGrid(inReview, 'No proposals currently under review.'),
                  _buildGrid(approved, 'No approved proposals yet.'),
                  _buildGrid(revision, 'All clear! No revisions requested.'),
                  _buildGrid(declined, 'No declined proposals found.'),
                  _buildGrid(archived, 'No archived GPOA activities.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> list, String emptyText) {
    if (list.isEmpty) return Center(child: Text(emptyText, style: const TextStyle(color: Colors.grey)));
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 1.4),
      itemCount: list.length,
      itemBuilder: (context, index) => _GPOAStatusCard(activity: list[index], onRefresh: onRefresh),
    );
  }
}

class _GPOAStatusCard extends StatelessWidget {
  final Map<String, dynamic> activity;
  final VoidCallback onRefresh;
  const _GPOAStatusCard({required this.activity, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final status = activity['status'] ?? 'Pending';
    Color color = const Color(0xFF64748B);
    IconData icon = Icons.hourglass_empty_rounded;

    if (['Approved', 'Scheduled'].contains(status)) { color = const Color(0xFF10B981); icon = Icons.check_circle_outline_rounded; }
    if (status == 'Completed') { color = const Color(0xFF6366F1); icon = Icons.task_alt_rounded; }
    if (status == 'Rejected') { color = const Color(0xFFEF4444); icon = Icons.cancel_outlined; }
    if (status == 'Needs Revision') { color = const Color(0xFFF97316); icon = Icons.history_edu_rounded; }
    if (status == 'Awaiting Date Approval') { color = const Color(0xFF8B5CF6); icon = Icons.calendar_month_rounded; }
    if (status == 'Endorsed') { color = const Color(0xFF14B8A6); icon = Icons.thumb_up_alt_rounded; }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showActivityDetails(context, activity, onRefresh),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
                    StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 24),
                Text(activity['title'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B), letterSpacing: -0.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(activity['subtitle'] ?? 'GPOA Activity', style: TextStyle(fontSize: 12, color: const Color(0xFF6366F1).withValues(alpha: 0.8), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('Submitted: ${AppUtils.formatDateTime(activity['created_at'])}', style: TextStyle(fontSize: 10, color: Colors.grey[400], fontStyle: FontStyle.italic)),
                if (activity['remarks']?.toString().isNotEmpty ?? false) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.1))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.feedback_rounded, size: 14, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Feedback: ${activity['remarks']}', style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w600, height: 1.4))),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (status == 'Needs Revision' || (activity['remarks']?.toString().isNotEmpty ?? false) || status == 'Pending')
                      Flexible(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => _ReviseActivityDialog(
                                activity: activity,
                                userRole: 'President',
                                onRefreshed: onRefresh,
                              ),
                            );
                          },
                          icon: const Icon(Icons.history_edu_rounded, size: 16),
                          label: const Text('Revise / Edit', overflow: TextOverflow.ellipsis),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF97316),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: activity['is_archived'] == true ? 'Restore' : 'Archive',
                      onPressed: () async {
                        final wasArchived = activity['is_archived'] == true;
                        try {
                          await Supabase.instance.client.from('activities').update({'is_archived': !wasArchived}).eq('id', activity['id']);
                          if (context.mounted) {
                            AppUtils.showTopToast(context, wasArchived ? 'GPOA restored.' : 'GPOA archived.');
                            onRefresh();
                          }
                        } catch (e) {
                          if (context.mounted) AppUtils.showTopToast(context, 'Could not update archive: $e', isError: true);
                        }
                      },
                      icon: Icon(activity['is_archived'] == true ? Icons.unarchive_outlined : Icons.archive_outlined, size: 20, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showActivityDetails(BuildContext context, Map<String, dynamic> activity, VoidCallback onRefresh) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: GPOAActivityDetailsView(
              title: activity['title'] ?? 'Untitled',
              sdgs: activity['sdgs'] ?? 'Not specified',
              objectives: activity['objectives'] ?? 'Not specified',
              outcome: activity['outcome'] ?? 'Not specified',
              participants: activity['participants'] ?? 'Not specified',
              timeFrame: activity['time_frame'] ?? 'Not specified',
              delivery: activity['delivery_strategy'] ?? 'Not specified',
              persons: activity['persons_involved'] ?? 'Not specified',
              facilities: activity['facilities_materials'] ?? 'Not specified',
              budget: activity['budget_allocation'] ?? 'Not specified',
              status: activity['status'] ?? 'Pending',
              createdAt: AppUtils.formatDateTime(activity['created_at']),
              proposedDate: activity['proposed_date'] != null ? AppUtils.formatDateTime(activity['proposed_date']) : null,
              onStatusUpdate: (activity['status'] == 'Needs Revision' || (activity['remarks']?.toString().isNotEmpty ?? false) || activity['status'] == 'Pending') ? (s) async {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (ctx) => _ReviseActivityDialog(
                    activity: activity,
                    userRole: 'President',
                    onRefreshed: onRefresh,
                  ),
                );
              } : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _GPOAReportPrintingView extends StatelessWidget {
  final Map<String, dynamic> orgData;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> profiles;
  final VoidCallback onBack;

  const _GPOAReportPrintingView({
    required this.orgData,
    required this.activities,
    required this.profiles,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to Manage GPOA', style: TextStyle(fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1)),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.print_rounded, size: 64, color: Color(0xFF6366F1)),
                        const SizedBox(height: 24),
                        const Text('Generate GPOA Document', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        const SizedBox(height: 12),
                        const Text(
                          'Generate a professional PDF document of your organization\'s General Plan of Activities following the university template.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 16),
                        ),
                        const SizedBox(height: 40),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryItem(label: 'TOTAL ACTIVITIES', value: activities.length.toString(), icon: Icons.assignment_rounded),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _SummaryItem(label: 'READY FOR PRINT', value: activities.where((a) => a['status'] == 'Approved' || a['status'] == 'Scheduled' || a['status'] == 'Completed').length.toString(), icon: Icons.check_circle_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () => _handlePrint(context),
                            icon: const Icon(Icons.picture_as_pdf_rounded),
                            label: const Text('GENERATE AND PRINT PDF', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePrint(BuildContext context) async {
    final president = profiles.firstWhere(
      (p) => p['role'] == 'President',
      orElse: () => {'full_name': 'Not Assigned'},
    );
    final adviser = profiles.firstWhere(
      (p) => p['role'] == 'Adviser',
      orElse: () => {'full_name': 'Not Assigned'},
    );

    final approvedActivities = activities.where((a) => ['Approved', 'Scheduled', 'Completed'].contains(a['status'])).toList();

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => GPOAPreviewDialog(
          organization: orgData,
          activities: approvedActivities,
          president: president,
          adviser: adviser,
          fileName: 'GPOA_${orgData['name']}.pdf',
        ),
      );
    }
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _SummaryItem({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6366F1)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _OrgEvaluationScoresView extends StatefulWidget {
  final Map<String, dynamic> orgData;
  const _OrgEvaluationScoresView({required this.orgData});

  @override
  State<_OrgEvaluationScoresView> createState() => _OrgEvaluationScoresViewState();
}

class _OrgEvaluationScoresViewState extends State<_OrgEvaluationScoresView> {
  String _schoolYear = '2025-2026';
  Map<String, dynamic>? _eval;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchScore();
  }

  Future<void> _fetchScore() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('organization_evaluations')
          .select('*')
          .eq('organization_id', widget.orgData['id'])
          .eq('school_year', _schoolYear)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _eval = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgName = widget.orgData['name']?.toString().toUpperCase() ?? 'ORGANIZATION';
    final total = (_eval?['grand_total'] as num?)?.toDouble() ?? 0.0;
    final rawRating = (_eval?['adjectival_rating'] ?? 'Pending Evaluation').toString();
    final rating = rawRating.contains('|') ? rawRating.split('|').first : rawRating;

    final subCatScores = [
      ['Item I: Symposium / Seminars Conducted', _eval?['score_i']],
      ['Item II: Activities / Programs Conducted', _eval?['score_ii']],
      ['Item III: Religious Activities', _eval?['score_iii']],
      ['Item IV: Socio-Cultural & Sports Activities', _eval?['score_iv']],
      ['Item V: Clean & Green Activities', _eval?['score_v']],
      ['Item VI: Extension Services', _eval?['score_vi']],
      ['Item VII: Tangible / Physical Projects', _eval?['score_vii']],
      ['Item VIII: Fund Drive / IGP', _eval?['score_viii']],
      ['Item IX: Financial Assistance', _eval?['score_ix']],
      ['Item X: Action Plan Implementation', _eval?['score_x']],
    ];

    return Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Evaluation Score & Breakdown', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  Text(orgName, style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.bold)),
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
                    if (val != null) {
                      setState(() => _schoolYear = val);
                      _fetchScore();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GRAND TOTAL SCORE', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(
                      _isLoading ? 'Loading…' : '${total.toStringAsFixed(2)} PTS',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(100)),
                  child: Text(rating.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text('Sub-Category Score Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _eval == null
                    ? const Center(child: Text('No evaluation score recorded for this school year yet.', style: TextStyle(color: Color(0xFF64748B))))
                    : ListView.builder(
                        itemCount: subCatScores.length,
                        itemBuilder: (ctx, idx) {
                          final item = subCatScores[idx];
                          final pts = (item[1] as num?)?.toDouble() ?? 0.0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item[0].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                                Text('${pts.toStringAsFixed(1)} pts', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF4F46E5))),
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

class _OrgProfileView extends StatefulWidget {
  final Map<String, dynamic> orgData;
  const _OrgProfileView({required this.orgData});
  @override
  State<_OrgProfileView> createState() => _OrgProfileViewState();
}

class _OrgProfileViewState extends State<_OrgProfileView> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _officers = [];
  List<Map<String, dynamic>> _completedActivities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    try {
      final profilesResponse = await _supabase.from('profiles').select().eq('organization_id', widget.orgData['id']);
      final officersResponse = await _supabase.from('org_officers').select().eq('organization_id', widget.orgData['id']);
      final activitiesResponse = await _supabase.from('activities').select().eq('organization_id', widget.orgData['id']).eq('status', 'Completed');

      if (mounted) {
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(profilesResponse);
          _officers = List<Map<String, dynamic>>.from(officersResponse);
          _completedActivities = List<Map<String, dynamic>>.from(activitiesResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: widget.orgData['name']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Organization Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Organization Name')),
              const SizedBox(height: 24),
              const Row(children: [Icon(Icons.groups, size: 20, color: Colors.blue), SizedBox(width: 8), Text('List of Officers', style: TextStyle(fontWeight: FontWeight.bold))]),
              const Text('Add names of your organization officers below.', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const Divider(),
              ..._officers.map((off) => ListTile(
                    title: Text(off['full_name'] ?? 'No Name'),
                    subtitle: Text(off['position'] ?? 'Officer'),
                    trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Remove Officer'),
                              content: Text('Are you sure you want to remove ${off['full_name']} from the list?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Remove')),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _supabase.from('org_officers').delete().eq('id', off['id']);
                            if (context.mounted) _fetchProfileData();
                          }
                        }),
                  )),
              const SizedBox(height: 12),
              TextButton.icon(onPressed: _showAddOfficerDialog, icon: const Icon(Icons.add), label: const Text('Add Officer Row')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () async {
                try {
                  await _supabase.from('organizations').update({'name': nameController.text}).eq('id', widget.orgData['id']);
                  if (context.mounted) {
                    AppUtils.showTopToast(context, 'Changes saved successfully!');
                    _fetchProfileData();
                  }
                } catch (e) {
                  if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
                }
              },
              child: const Text('Save Changes')),
        ],
      ),
    );
  }

  void _showAddOfficerDialog() {
    final nameController = TextEditingController();
    final posController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Officer to List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name'), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))]),
            TextField(controller: posController, decoration: const InputDecoration(labelText: 'Position (e.g. Secretary, Treasurer)'), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () async {
                try {
                  await _supabase.from('org_officers').insert({'full_name': nameController.text, 'position': posController.text, 'organization_id': widget.orgData['id']});
                  if (context.mounted) {
                    AppUtils.showTopToast(context, 'Officer added successfully!');
                    Navigator.pop(context);
                    Navigator.pop(context);
                    _fetchProfileData();
                  }
                } catch (e) {
                  if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
                }
              },
              child: const Text('Add to List')),
        ],
      ),
    );
  }

  Future<void> _uploadLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      setState(() => _isLoading = true);
      final file = result.files.first;
      final fileName = 'org_logos/${widget.orgData['id']}_${DateTime.now().millisecondsSinceEpoch}.png';
      final storage = _supabase.storage.from('documents');
      if (kIsWeb) {
        await storage.uploadBinary(fileName, file.bytes!);
      } else {
        await storage.uploadBinary(fileName, await file.xFile.readAsBytes());
      }
      final url = storage.getPublicUrl(fileName);
      await _supabase.from('organizations').update({'logo_url': url}).eq('id', widget.orgData['id']);
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Profile picture updated!');
      _fetchProfileData();
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Upload failed: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final adviser = _profiles.firstWhere((p) => p['role'] == 'Adviser', orElse: () => {'full_name': 'Not assigned'});
    final president = _profiles.firstWhere((p) => p['role'] == 'President', orElse: () => {'full_name': 'Not assigned'});
    final String? logoUrl = widget.orgData['logo_url'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const SizedBox(width: 48),
                      Stack(children: [
                        CircleAvatar(radius: 60, backgroundColor: const Color(0xFFF3E5F5), backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null, child: logoUrl == null ? const Icon(Icons.business, size: 60, color: Color(0xFF6366F1)) : null),
                        Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _uploadLogo, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20)))),
                      ]),
                      IconButton(onPressed: _showEditProfileDialog, icon: const Icon(Icons.edit_outlined, color: Colors.grey), tooltip: 'Edit Profile'),
                    ]),
                    const SizedBox(height: 24),
                    Text(widget.orgData['name'], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(20)), child: Text(widget.orgData['type'], style: const TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: _ProfileSection(
                      title: 'Leadership',
                      icon: Icons.people_outline,
                      child: Column(
                        children: [
                          _LeadershipTile(label: 'Adviser', name: adviser['full_name'], icon: Icons.person_outline),
                          const Divider(height: 24),
                          _LeadershipTile(label: 'President', name: president['full_name'], icon: Icons.person),
                          if (_officers.isNotEmpty) ...[
                            const Divider(height: 24),
                            const Align(alignment: Alignment.centerLeft, child: Text('Officers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
                            const SizedBox(height: 12),
                            ..._officers.map((o) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(children: [
                                    const Icon(Icons.badge_outlined, size: 16, color: Colors.blue),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(o['full_name'] ?? 'Unknown', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                        Text('${o['position'] ?? 'Officer'} • Added ${AppUtils.formatDateTime(o['created_at'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ]),
                                    ),
                                  ]),
                                )),
                          ]
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 1,
                    child: _ProfileSection(
                      title: 'Performance',
                      icon: Icons.analytics_outlined,
                      child: Column(
                        children: [
                          Row(children: [
                            Expanded(child: _StatBox(label: 'ACCOMPLISHED', value: _completedActivities.length.toString(), icon: Icons.task_alt, color: Colors.green)),
                            const SizedBox(width: 16),
                            Expanded(child: _StatBox(label: 'POINTS', value: _completedActivities.fold<double>(0, (sum, item) => sum + (double.tryParse(item['points']?.toString() ?? '0') ?? 0)).toStringAsFixed(2), icon: Icons.star_outline, color: Colors.orange)),
                          ]),
                          const SizedBox(height: 32),
                          const Align(alignment: Alignment.centerLeft, child: Text('Recent Accomplishments', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
                          const SizedBox(height: 12),
                          if (_completedActivities.isEmpty)
                            const Text('No completed events yet.', style: TextStyle(color: Colors.grey, fontSize: 13))
                          else
                            ..._completedActivities.take(5).map((a) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                  title: Text(a['title'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  subtitle: Text(AppUtils.formatDateTime(a['proposed_date']), style: const TextStyle(fontSize: 11)),
                                )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _ProfileSection({required this.title, required this.icon, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: const Color(0xFF6366F1)),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ]),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _LeadershipTile extends StatelessWidget {
  final String label, name;
  final IconData icon;
  const _LeadershipTile({required this.label, required this.name, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF5F7FB), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 20, color: Colors.grey[600])),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        ]),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.1))),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _ReviseActivityDialog extends StatefulWidget {
  final Map<String, dynamic> activity;
  final String userRole;
  final VoidCallback onRefreshed;

  const _ReviseActivityDialog({
    required this.activity,
    required this.userRole,
    required this.onRefreshed,
  });

  @override
  State<_ReviseActivityDialog> createState() => _ReviseActivityDialogState();
}

class _ReviseActivityDialogState extends State<_ReviseActivityDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _objectivesController;
  late TextEditingController _outcomeController;
  late TextEditingController _timeFrameController;
  late TextEditingController _deliveryController;
  late TextEditingController _facilitiesController;
  late TextEditingController _budgetController;

  String? _selectedType;
  final List<String> _sdgList = const [
    'SDG 1: No Poverty', 'SDG 2: Zero Hunger', 'SDG 3: Good Health and Well-being', 'SDG 4: Quality Education', 'SDG 5: Gender Equality',
    'SDG 6: Clean Water and Sanitation', 'SDG 7: Affordable and Clean Energy', 'SDG 8: Decent Work and Economic Growth', 'SDG 9: Industry, Innovation and Infrastructure',
    'SDG 10: Reduced Inequality', 'SDG 11: Sustainable Cities and Communities', 'SDG 12: Responsible Consumption and Production', 'SDG 13: Climate Action',
    'SDG 14: Life Below Water', 'SDG 15: Life on Land', 'SDG 16: Peace, Justice and Strong Institutions', 'SDG 17: Partnerships for the Goals'
  ];
  final List<String> _selectedSDGs = [];

  final List<String> _participantOptions = const ['1st year Students', '2nd Year Students', '3rd Year Students', '4th Year Students', 'Transferees', 'Officers and Mayors', 'Faculty Staffs', 'All Students', 'All student of CSU Lal-lo'];
  final List<String> _selectedParticipants = [];

  final List<String> _personsOptions = const ['Student Officers', 'Faculty Advisers', 'Campus Directors', 'OSDW Staff', 'Guest Speakers', 'External Partners'];
  final List<String> _selectedPersons = [];

  bool _isSubmitting = false;

  List<String> get _activityTypes {
    final type = (widget.activity['organization_type'] ?? widget.userRole).toString().toLowerCase();
    if (type.contains('specialized') || type.contains('special')) {
      return const [
        'Symposium /Seminars Conducted',
        'Activities Conducted /Sponsored in line with the nature of the organization',
        'Makakalikasan/ Clean and Green Activities and Projects',
        'Extension Services Sponsored/ Conducted',
      ];
    }
    return const [
      'Symposium/ Seminars Conducted',
      'Convocations/ Programs and Literary Activities',
      'Religious Activities',
      'Socio-Cultural and Sports Activities',
      'Makakalikasan/ Clean and Green Activities and Projects',
      'Extension Services Sponsored/ Conducted',
    ];
  }

  String? _normalizeActivityType(String? rawType) {
    if (rawType == null || rawType.trim().isEmpty) return _activityTypes.first;
    final lower = rawType.toLowerCase();

    if (lower.contains('makakalikasan') || lower.contains('green') || lower.contains('clean')) {
      return 'Makakalikasan/ Clean and Green Activities and Projects';
    }
    if (lower.contains('extension')) {
      return 'Extension Services Sponsored/ Conducted';
    }
    if (lower.contains('seminar') || lower.contains('symposium')) {
      return 'Symposium/ Seminars Conducted';
    }
    if (lower.contains('convocation') || lower.contains('literary') || lower.contains('program')) {
      return 'Convocations/ Programs and Literary Activities';
    }
    if (lower.contains('religious') || lower.contains('holy mass') || lower.contains('rosary')) {
      return 'Religious Activities';
    }
    if (lower.contains('sport') || lower.contains('socio') || lower.contains('cultural')) {
      return 'Socio-Cultural and Sports Activities';
    }
    if (lower.contains('nature') || lower.contains('specialized')) {
      return 'Activities Conducted /Sponsored in line with the nature of the organization';
    }

    if (_activityTypes.contains(rawType)) return rawType;

    return _activityTypes.first;
  }

  @override
  void initState() {
    super.initState();
    final act = widget.activity;
    _titleController = TextEditingController(text: act['title']?.toString() ?? '');
    _objectivesController = TextEditingController(text: act['objectives']?.toString() ?? act['description']?.toString() ?? '');
    _outcomeController = TextEditingController(text: act['outcome']?.toString() ?? '');
    _timeFrameController = TextEditingController(text: act['time_frame']?.toString() ?? '');
    _deliveryController = TextEditingController(text: act['delivery_strategy']?.toString() ?? '');
    _facilitiesController = TextEditingController(text: act['facilities_materials']?.toString() ?? '');
    _budgetController = TextEditingController(text: act['budget_allocation']?.toString() ?? '');
    _selectedType = _normalizeActivityType(act['subtitle']?.toString());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _objectivesController.dispose();
    _outcomeController.dispose();
    _timeFrameController.dispose();
    _deliveryController.dispose();
    _facilitiesController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _showSDGSelector() {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Select SDGs Addressed'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _sdgList.map((sdg) {
                  final isSelected = _selectedSDGs.contains(sdg);
                  return CheckboxListTile(
                    title: Text(sdg, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: isSelected,
                    dense: true,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          _selectedSDGs.add(sdg);
                        } else {
                          _selectedSDGs.remove(sdg);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Done'))],
        ),
      ),
    );
  }

  void _showParticipantSelector() {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Select Target Participants'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _participantOptions.map((opt) {
                  final isSelected = _selectedParticipants.contains(opt);
                  return CheckboxListTile(
                    title: Text(opt, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: isSelected,
                    dense: true,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          _selectedParticipants.add(opt);
                        } else {
                          _selectedParticipants.remove(opt);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Done'))],
        ),
      ),
    );
  }

  void _showPersonsSelector() {
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Select Persons Involved'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _personsOptions.map((opt) {
                  final isSelected = _selectedPersons.contains(opt);
                  return CheckboxListTile(
                    title: Text(opt, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    value: isSelected,
                    dense: true,
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          _selectedPersons.add(opt);
                        } else {
                          _selectedPersons.remove(opt);
                        }
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Done'))],
        ),
      ),
    );
  }

  Future<void> _submitRevision() async {
    if (!_formKey.currentState!.validate() || _selectedType == null) {
      if (_selectedType == null) AppUtils.showTopToast(context, 'Please select an activity type.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final actId = widget.activity['id'];
      await Supabase.instance.client.from('activities').update({
        'title': _titleController.text.trim(),
        'subtitle': _selectedType,
        'description': _objectivesController.text.trim(),
        'objectives': _objectivesController.text.trim(),
        'outcome': _outcomeController.text.trim(),
        'time_frame': _timeFrameController.text.trim(),
        'delivery_strategy': _deliveryController.text.trim(),
        'facilities_materials': _facilitiesController.text.trim(),
        'budget_allocation': _budgetController.text.trim(),
        'status': 'Pending',
        'remarks': null,
      }).eq('id', actId);

      try {
        final orgName = widget.activity['organization_name'] ?? 'Organization';
        await Supabase.instance.client.from('notifications').insert({
          'title': 'Proposal Revised - ${_titleController.text.trim()}',
          'body': '$orgName resubmitted the revised activity proposal for review.',
          'status': 'Pending',
        });
      } catch (_) {}

      if (mounted) {
        Navigator.pop(context);
        AppUtils.showTopToast(context, 'Activity proposal revised and resubmitted successfully!');
        widget.onRefreshed();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppUtils.showTopToast(context, 'Error resubmitting revision: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remarks = widget.activity['remarks']?.toString();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 1100,
        constraints: const BoxConstraints(maxHeight: 850),
        padding: const EdgeInsets.all(36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFF97316).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.history_edu_rounded, color: Color(0xFFF97316), size: 32),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Revise Activity Proposal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                            Text('Update your activity proposal details and resubmit for approval.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close_rounded, size: 24), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),
            if (remarks != null && remarks.trim().isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline_rounded, color: Color(0xFFC2410C), size: 20),
                        SizedBox(width: 10),
                        Text('Revision Remarks from Adviser / Admin:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFC2410C))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(remarks, style: const TextStyle(fontSize: 14, color: Color(0xFF7C2D12), height: 1.5, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Section 1: BASIC INFORMATION
                      _buildSectionCard(
                        title: 'BASIC INFORMATION',
                        icon: Icons.info_outline_rounded,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _titleController,
                                decoration: InputDecoration(
                                  labelText: 'Activity Title',
                                  prefixIcon: const Icon(Icons.title_rounded, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _activityTypes.contains(_selectedType) ? _selectedType : _activityTypes.first,
                                decoration: InputDecoration(
                                  labelText: 'Activity Type',
                                  prefixIcon: const Icon(Icons.category_rounded, size: 20),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: _activityTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (val) => setState(() => _selectedType = val),
                                validator: (val) => val == null ? 'Required' : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 2: STRATEGIC ALIGNMENT
                      _buildSectionCard(
                        title: 'STRATEGIC ALIGNMENT',
                        icon: Icons.track_changes_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sustainable Development Goals (SDGs) Addressed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: _showSDGSelector,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: Colors.white),
                                child: Row(
                                  children: [
                                    const Icon(Icons.public_rounded, size: 20, color: Color(0xFF64748B)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _selectedSDGs.isEmpty
                                          ? const Text('Click to select relevant SDGs', style: TextStyle(color: Colors.grey, fontSize: 13))
                                          : Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _selectedSDGs.map((s) => Chip(
                                                    backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                                    side: BorderSide.none,
                                                    label: Text(s.split(':').first, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                                                    onDeleted: () { setState(() => _selectedSDGs.remove(s)); },
                                                    deleteIconColor: const Color(0xFF6366F1),
                                                    deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                                  )).toList(),
                                            ),
                                    ),
                                    const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 3: EXECUTION PLAN & RESOURCES
                      _buildSectionCard(
                        title: 'EXECUTION PLAN & RESOURCES',
                        icon: Icons.rocket_launch_rounded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _TimeFrameInput(controller: _timeFrameController),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: TextFormField(
                                    controller: _budgetController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Budget Allocation (₱)',
                                      prefixIcon: const Icon(Icons.payments_rounded, size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Target Participants', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _showParticipantSelector,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: Colors.white),
                                child: Row(
                                  children: [
                                    const Icon(Icons.groups_rounded, size: 20, color: Color(0xFF64748B)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _selectedParticipants.isEmpty
                                          ? const Text('Who will participate in this activity?', style: TextStyle(color: Colors.grey, fontSize: 13))
                                          : Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _selectedParticipants.map((p) => Chip(
                                                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                                                    side: BorderSide.none,
                                                    label: Text(p, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                                                    onDeleted: () { setState(() => _selectedParticipants.remove(p)); },
                                                    deleteIconColor: const Color(0xFF2563EB),
                                                    deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                                  )).toList(),
                                            ),
                                    ),
                                    const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('Persons Involved', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _showPersonsSelector,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: Colors.white),
                                child: Row(
                                  children: [
                                    const Icon(Icons.people_alt_rounded, size: 20, color: Color(0xFF64748B)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _selectedPersons.isEmpty
                                          ? const Text('Who are the organizers / staff?', style: TextStyle(color: Colors.grey, fontSize: 13))
                                          : Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _selectedPersons.map((p) => Chip(
                                                    backgroundColor: Colors.green.withValues(alpha: 0.1),
                                                    side: BorderSide.none,
                                                    label: Text(p, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                                    onDeleted: () { setState(() => _selectedPersons.remove(p)); },
                                                    deleteIconColor: const Color(0xFF16A34A),
                                                    deleteIcon: const Icon(Icons.close_rounded, size: 14),
                                                  )).toList(),
                                            ),
                                    ),
                                    const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _deliveryController,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: 'Delivery Strategy',
                                prefixIcon: const Icon(Icons.map_rounded, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _facilitiesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Facilities / Materials Required',
                                prefixIcon: const Icon(Icons.business_rounded, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 4: GOALS & OUTCOMES
                      _buildSectionCard(
                        title: 'GOALS & OUTCOMES',
                        icon: Icons.verified_user_rounded,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _objectivesController,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: 'Objectives',
                                prefixIcon: const Icon(Icons.flag_rounded, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _outcomeController,
                              maxLines: 4,
                              decoration: InputDecoration(
                                labelText: 'Expected Outcome',
                                prefixIcon: const Icon(Icons.stars_rounded, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitRevision,
                  icon: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 20),
                  label: const Text('SUBMIT REVISED PROPOSAL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF6366F1)),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6366F1), letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ArchivesView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final Map<String, dynamic>? orgData;
  final String userRole;

  const _ArchivesView({
    required this.activities,
    this.orgData,
    this.userRole = 'Admin',
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

  void _openGPOADialog(List<Map<String, dynamic>> acts, String orgName) {
    showDialog(
      context: context,
      builder: (ctx) => GPOAPreviewDialog(
        organization: widget.orgData ?? {'name': orgName, 'type': 'College Student Council'},
        activities: acts,
        president: const {'full_name': 'Student Leader'},
        adviser: const {'full_name': 'Faculty Adviser'},
        fileName: 'GPOA_${orgName.replaceAll(" ", "_")}.pdf',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgNameFilter = widget.orgData != null ? (widget.orgData!['name'] ?? '').toString().toLowerCase() : '';
    final archivedDocs = <Map<String, dynamic>>[];

    // 1. Process GPOAs - EXACTLY 1 GPOA ENTRY PER ORGANIZATION
    if (_selectedCategory == 'All' || _selectedCategory == 'GPOA') {
      final Map<String, List<Map<String, dynamic>>> orgActsMap = {};
      final Map<String, String> orgNamesMap = {};

      for (var act in widget.activities) {
        final orgId = act['organization_id']?.toString() ?? widget.orgData?['id']?.toString() ?? 'unknown';
        final orgName = (act['organization_name'] ?? widget.orgData?['name'] ?? 'Organization').toString();

        if (orgNameFilter.isNotEmpty && !orgName.toLowerCase().contains(orgNameFilter)) {
          continue;
        }

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
          'is_gpoa': true,
        });
      });
    }

    // 2. Process Approved Event Letters
    for (var act in widget.activities) {
      final actTitle = (act['title'] ?? 'Untitled Activity').toString();
      final orgName = (act['organization_name'] ?? widget.orgData?['name'] ?? 'Organization').toString();

      if (orgNameFilter.isNotEmpty && !orgName.toLowerCase().contains(orgNameFilter)) {
        continue;
      }

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
      final orgName = (rep['organization_name'] ?? widget.orgData?['name'] ?? 'Organization').toString();

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
                                      _openGPOADialog(actsList, doc['org_name'].toString());
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

class _TimeFrameInput extends StatefulWidget {
  final TextEditingController controller;

  const _TimeFrameInput({
    required this.controller,
  });

  @override
  State<_TimeFrameInput> createState() => _TimeFrameInputState();
}

class _TimeFrameInputState extends State<_TimeFrameInput> {
  late TextEditingController _numberController;
  String _unit = 'Hours';

  @override
  void initState() {
    super.initState();
    final raw = widget.controller.text.trim();
    final lower = raw.toLowerCase();

    if (lower.contains('day')) {
      _unit = 'Days';
    } else {
      _unit = 'Hours';
    }

    final match = RegExp(r'(\d+)').firstMatch(raw);
    _numberController = TextEditingController(text: match != null ? match.group(1) : '2');
  }

  void _updateParent() {
    final numVal = int.tryParse(_numberController.text.trim()) ?? 2;
    final formatted = numVal == 1
        ? (_unit == 'Days' ? '1 Day' : '1 Hour')
        : '$numVal $_unit';

    widget.controller.text = formatted;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Time Frame / Duration', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Duration Number',
                  prefixIcon: const Icon(Icons.timer_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => _updateParent(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Hours', child: Text('Hours')),
                  DropdownMenuItem(value: 'Days', child: Text('Days')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _unit = val);
                    _updateParent();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            _buildPresetChip('2 Hours', '2', 'Hours'),
            _buildPresetChip('4 Hours', '4', 'Hours'),
            _buildPresetChip('8 Hours', '8', 'Hours'),
            _buildPresetChip('1 Day', '1', 'Days'),
            _buildPresetChip('2 Days', '2', 'Days'),
            _buildPresetChip('3 Days', '3', 'Days'),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, String numStr, String unit) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      selected: _numberController.text == numStr && _unit == unit,
      onSelected: (s) {
        if (s) {
          setState(() {
            _numberController.text = numStr;
            _unit = unit;
          });
          _updateParent();
        }
      },
      selectedColor: const Color(0xFF6366F1),
      labelStyle: TextStyle(color: (_numberController.text == numStr && _unit == unit) ? Colors.white : const Color(0xFF475569)),
    );
  }
}
