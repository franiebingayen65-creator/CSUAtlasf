import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import 'package:csuatlasf/utils/app_utils.dart';
import 'package:csuatlasf/utils/storage_utils.dart';
import 'package:csuatlasf/utils/pdf_generator.dart';
import 'package:csuatlasf/widgets/common_ui.dart';
import 'package:csuatlasf/widgets/csc_scoring_components.dart';
import 'package:csuatlasf/widgets/gpoa_details.dart';
import 'package:csuatlasf/widgets/pdf_preview_dialog.dart';
import 'package:csuatlasf/widgets/admin_ui_kit.dart';
import 'package:csuatlasf/widgets/admin_shell.dart';
import 'package:csuatlasf/utils/user_archive.dart';
import 'package:csuatlasf/utils/school_year_service.dart';
import 'package:shared_preferences/shared_preferences.dart';


class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}
class _AdminDashboardState extends State<AdminDashboard> {
  final _supabase = Supabase.instance.client;
  bool _isSidebarCollapsed = false;
  String _activePage = 'Dashboard';
  String? _eventsInitialTab;
  String? _eventsOpenId;
  int _eventsNavToken = 0;
  bool _isLoading = true;
  bool _isVerified = false;
  final String _searchQuery = '';
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _profiles = [];
  Timer? _autoCompleteTimer;
  final List<StreamSubscription> _subscriptions = [];
  final Set<String> _completing = {};
  final Set<String> _returning = {};

  @override
  void initState() {
    super.initState();
    UserArchive.changes.addListener(_reapplyArchive);
    _verifyAdmin();
  }

  Future<void> _reapplyArchive() async {
    await UserArchive.decorate(_activities, 'activity');
    if (mounted) setState(() {});
  }


  Future<void> _verifyAdmin() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _redirectToLogin();
      return;
    }

    try {
      final p = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (p?['role'] != 'Admin') {
        await _supabase.auth.signOut();
        _redirectToLogin();
        return;
      }

      if (!mounted) return;
      setState(() => _isVerified = true);

      // Start loading data only after the role is confirmed
      _setupRealtimeSubscriptions();
      await _fetchInitialData();

      _autoCompleteTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) {
          _checkAndReportAutoCompletion();
          setState(() {});
        }
      });
    } catch (_) {
      // Fail closed: if the check fails, do not show the dashboard
      await _supabase.auth.signOut();
      _redirectToLogin();
    }
  }

  void _redirectToLogin() {
    if (mounted) Navigator.pushReplacementNamed(context, '/');
  }
  @override
  void dispose() {
    UserArchive.changes.removeListener(_reapplyArchive);
    _autoCompleteTimer?.cancel();
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
    _subscriptions.add(_supabase.from('activities').stream(primaryKey: ['id']).listen((data) async {
      final acts = List<Map<String, dynamic>>.from(data);
      await UserArchive.decorate(acts, 'activity');
      if (!mounted) return;
      setState(() {
        _activities = acts;
        _isLoading = false;
      });
      _checkAndReportAutoCompletion();
    }));
    _subscriptions.add(_supabase.from('profiles').stream(primaryKey: ['id']).listen((data) {
      if (mounted) {
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(data);
        });
      }
    }));
  }
  /// Events still "Awaiting Date Approval" whose proposed start time has
  /// already passed are sent back to the organization for rescheduling.
  void _returnExpiredPendingDates() {
    final now = DateTime.now();
    for (final item in _activities) {
      if ((item['status'] ?? '').toString() != 'Awaiting Date Approval') continue;
      if (item['is_archived'] == true) continue;
      final raw = item['proposed_date']?.toString().trim() ?? '';
      if (raw.isEmpty) continue;

      try {
        final start = DateTime.parse(raw).toLocal();
        final id = item['id'].toString();
        if (!start.isBefore(now) || !_returning.add(id)) continue;

        const remark =
            'The proposed date passed before it was approved. Please propose a new date for this activity.';

        _supabase
            .from('activities')
            .update({
          'status': 'Reschedule',
          'remarks': remark,
          'revision_by': null,
        })
            .eq('id', item['id'])
            .then((_) {
          if (mounted) {
            setState(() {
              item['status'] = 'Reschedule';
              item['remarks'] = remark;
              item['revision_by'] = null;
            });
          }
          AppUtils.sendNotification(
            title: 'Reschedule Needed 📅',
            body: 'The proposed date for "${item['title']}" passed without approval. Please propose a new date.',
            recipientRole: 'president',
            organizationId: item['organization_id']?.toString(),
          );
          AppUtils.sendNotification(
            title: 'Reschedule Needed 📅',
            body: 'The proposed date for "${item['title']}" passed without approval and was returned to the president.',
            recipientRole: 'adviser',
            organizationId: item['organization_id']?.toString(),
          );
        }).catchError((_) {
          _returning.remove(id); // retry on the next tick
        });
      } catch (_) {}
    }
  }

  void _checkAndReportAutoCompletion() {
    _returnExpiredPendingDates();
    final now = DateTime.now();
    for (var item in _activities) {
      final status = (item['status'] ?? '').toString();
      if (status == 'Scheduled' &&
          item['proposed_date'] != null &&
          item['proposed_date'].toString().trim().isNotEmpty) {
        try {
          final eventDate = DateTime.parse(item['proposed_date'].toString()).toLocal();
          final duration = AppUtils.parseDuration(item['time_frame']);
          final eventEndDate = eventDate.add(duration);
          final id = item['id'].toString();
          if (eventEndDate.isBefore(now) && _completing.add(id)) {
            _supabase
                .from('activities')
                .update({'status': 'Completed'})
                .eq('id', item['id'])
                .then((_) {
              if (mounted) setState(() => item['status'] = 'Completed');
            }).catchError((_) {
              _completing.remove(id); // allow a retry on the next tick
            });
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
        final status = (item['status'] ?? '').toString();
        if (status == 'Scheduled' &&
            item['proposed_date'] != null &&
            item['proposed_date'].toString().trim().isNotEmpty) {
          try {
            final eventDate = DateTime.parse(item['proposed_date'].toString()).toLocal();
            final duration = AppUtils.parseDuration(item['time_frame']);
            final eventEndDate = eventDate.add(duration);
            final id = item['id'].toString();
            if (eventEndDate.isBefore(now) && _completing.add(id)) {
              _supabase
                  .from('activities')
                  .update({'status': 'Completed'})
                  .eq('id', item['id'])
                  .then((_) {
                if (mounted) setState(() => item['status'] = 'Completed');
              }).catchError((_) {
                _completing.remove(id); // allow a retry on the next tick
              });
            }
          } catch (_) {}
        }
      }
      final acts = List<Map<String, dynamic>>.from(activitiesData);
      await UserArchive.decorate(acts, 'activity');
      if (mounted) {
        setState(() {
          _organizations = List<Map<String, dynamic>>.from(orgsData);
          _activities = acts;
          _profiles = List<Map<String, dynamic>>.from(profilesData);
          _isLoading = false;
        });
        _returnExpiredPendingDates();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onPageSelected(String page) {
    // Format: 'Manage Events|ongoing' or 'Manage Events|ongoing|<eventId>'
    if (page.startsWith('Manage Events')) {
      final parts = page.split('|');
      setState(() {
        _activePage = 'Manage Events';
        _eventsInitialTab = parts.length > 1 ? parts[1] : null;
        _eventsOpenId = parts.length > 2 ? parts[2] : null;
        _eventsNavToken++;
      });
      return;
    }
    setState(() {
      _activePage = page;
    });
  }

  Future<void> _addOrganization(String name, String type) async {
    try {
      await _supabase.from('organizations').insert({'name': name, 'type': type});
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Organization added successfully!');
      await _fetchInitialData();
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _editOrganization(String id, String name, String type) async {
    try {
      await _supabase.from('organizations').update({'name': name, 'type': type}).eq('id', id);
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Organization updated successfully!');
      await _fetchInitialData();
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _deleteOrganization(String id) async {
    try {
      await _supabase.from('organizations').delete().eq('id', id);
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Organization deleted.');
      await _fetchInitialData();
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
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
            child: const Text('Log out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _currentUserName() {
    final id = _supabase.auth.currentUser?.id;
    final p = _profiles.firstWhere((p) => p['id'] == id, orElse: () => {});
    return (p['full_name'] ?? 'Administrator').toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVerified || _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final planCount = _activities
        .where((a) => a['status'] == 'Endorsed' && a['is_archived'] != true)
        .length;
    final dateCount = _activities
        .where((a) => a['status'] == 'Awaiting Date Approval' && a['is_archived'] != true)
        .length;

    return Scaffold(
      backgroundColor: UiColors.bg,
      body: Row(
        children: [
          AdminSidebar(
            isCollapsed: _isSidebarCollapsed,
            activePage: _activePage,
            onPageSelected: _onPageSelected,
            onToggleCollapse: () =>
                setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            badges: {'Manage GPOA': planCount, 'Manage Events': dateCount},
          ),
          Expanded(
            child: Column(
              children: [
                AdminTopBar(
                  activePage: _activePage,
                  userName: _currentUserName(),
                  onLogout: _showLogoutDialog,
                  onProfile: () => _onPageSelected('Profile'),
                  notificationButton:
                  NotificationInboxButton(onNotificationTap: _onPageSelected),
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
        return DashboardOverview(
            onNavigate: _onPageSelected, activities: _activities, organizations: _organizations);
      case 'Manage Organization':
        return _ManageOrganizationsView(
            organizations: _organizations,
            activities: _activities,
            profiles: _profiles,
            onAddOrganization: _addOrganization,
            onEditOrganization: _editOrganization,
            onDeleteOrganization: _deleteOrganization,
            searchQuery: _searchQuery);
      case 'Manage GPOA':
        return _ManageGPOAView(
            organizations: _organizations, activities: _activities, onRefresh: _fetchInitialData);
      case 'Manage Events':
        return _ManageEventsView(
          key: ValueKey('events-$_eventsNavToken'),
          activities: _activities,
          organizations: _organizations,
          onRefresh: _fetchInitialData,
          initialTab: _eventsInitialTab,
          openEventId: _eventsOpenId,
        );
      case 'Manage Users':
        return _ManageUsersView(
            organizations: _organizations,
            profiles: _profiles,
            onRefresh: _fetchInitialData,
            searchQuery: _searchQuery);
      case 'Manage Re-Accreditation':
        return const _ManageReAccreditationView();
      case 'Manage Scores':
      case 'Add Scores':
        return _AddScoresView(
            activities: _activities, organizations: _organizations, onRefresh: _fetchInitialData);
      case 'Accomplishment Reports':
        return _AccomplishmentReportsView(
            activities: _activities, organizations: _organizations, onRefresh: _fetchInitialData);
      case 'GPOA Reports':
        return _GPOAReportsView(
            organizations: _organizations, activities: _activities, profiles: _profiles);
      case 'Archives':
        return _ArchivesView(activities: _activities, organizations: _organizations);
      case 'View Ranks':
        return _RankingsView(organizations: _organizations);
      case 'Profile':
        return _ProfileView(onRefresh: _fetchInitialData);
      default:
        return DashboardOverview(
            onNavigate: _onPageSelected, activities: _activities, organizations: _organizations);
    }
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

  bool _adminVisible(Map<String, dynamic> a) {
    final s = a['status'];
    if (s == 'Endorsed') return true;
    return a['revision_by'] == 'Admin' &&
        (s == 'Needs Revision' || s == 'Pending');
  }

  String _adminLabel(Map<String, dynamic> a) {
    final s = (a['status'] ?? 'Pending').toString();
    if (s == 'Endorsed') return 'Endorsed';
    if (a['revision_by'] == 'Admin' &&
        (s == 'Needs Revision' || s == 'Pending')) {
      return 'Pending Revision';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> orgsToDisplay = widget
        .organizations
        .where((o) =>
    _selectedOrgId == null || o['id'].toString() == _selectedOrgId)
        .toList();
    final activeActivities = widget.activities.where((
        a) => a['is_archived'] != true).toList();
    final pendingApprovals = activeActivities.where((a) {
      final matchesOrganization =
          _selectedOrgId == null ||
              a['organization_id']?.toString() == _selectedOrgId;
      return matchesOrganization && _adminVisible(a);
    }).toList();

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
                      Text('Proposal Review Center',
                          style: TextStyle(fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: -1)),
                      Text(
                          'Evaluate and endorse student organization General Plan of Activities (GPOA).',
                          style: TextStyle(color: Color(0xFF64748B),
                              fontSize: 16))
                    ]),
                if (_selectedOrgId != null ||
                    orgsToDisplay.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16),
                    decoration: BoxDecoration(color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(
                              alpha: 0.02), blurRadius: 10)
                        ],
                        border: Border.all(
                            color: Colors.grey.withValues(
                                alpha: 0.1))),
                    child: DropdownButton<String?>(
                      value: _selectedOrgId,
                      hint: const Text('Filter by Organization'),
                      underline: const SizedBox(),
                      icon: const Icon(Icons.filter_list_rounded,
                          color: Color(0xFF6366F1)),
                      onChanged: (val) =>
                          setState(() => _selectedOrgId = val),
                      items: [
                        const DropdownMenuItem(value: null,
                            child: Text('All Organizations',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold))),
                        ...widget.organizations.map((org) =>
                            DropdownMenuItem(value: org['id']
                                .toString(), child: Text(
                                org['name'] ?? 'Unknown Org'))),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10)
                  ]),
              child: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF64748B),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF6366F1)),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                            Icons.rate_review_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('GPOA Evaluation (${pendingApprovals
                            .length})', style: const TextStyle(
                            fontWeight: FontWeight.bold))
                      ])),
                  const Tab(child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Approved GPOA',
                            style: TextStyle(fontWeight: FontWeight
                                .bold))
                      ])),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: TabBarView(
                children: [
                  Builder(builder: (context) {
                    if (pendingApprovals.isEmpty) {
                      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                        SizedBox(height: 16),
                        Text('All clear! No pending approvals.', style: TextStyle(color: Colors.grey)),
                      ]));
                    }
                    final endorsed = pendingApprovals.where((a) => a['status'] == 'Endorsed').toList();
                    return Column(children: [
                      if (endorsed.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ElevatedButton.icon(
                              onPressed: () => _approveAll(endorsed),
                              icon: const Icon(Icons.done_all_rounded, size: 18),
                              label: Text('Approve all (${endorsed.length})'),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                            ),
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: pendingApprovals.length,
                          itemBuilder: (context, index) {
                            final act = pendingApprovals[index];
                            final org = widget.organizations.firstWhere((o) => o['id'].toString() == act['organization_id']?.toString(), orElse: () => {'name': 'Unknown Org'});
                            return _buildGPOAListTile(act, org);
                          },
                        ),
                      ),
                    ]);
                  }),
                  orgsToDisplay.isEmpty
                      ? const Center(
                      child: Text('No organizations found.'))
                      : ListView.builder(
                    itemCount: orgsToDisplay.length,
                    itemBuilder: (context, index) {
                      final org = orgsToDisplay[index];
                      final orgActivities = activeActivities.where((
                          a) =>
                      a['organization_id']?.toString() ==
                          org['id'].toString() &&
                          ['Approved', 'Scheduled', 'Completed']
                              .contains(a['status'])).toList();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: Colors
                            .white, borderRadius: BorderRadius
                            .circular(16), border: Border.all(
                            color: Colors.grey.withValues(
                                alpha: 0.1))),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                              dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            leading: const Icon(Icons.business,
                                color: Color(0xFF6366F1)),
                            title: Text(
                                org['name']?.toUpperCase() ??
                                    'UNKNOWN ORGANIZATION',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                    letterSpacing: 0.5)),
                            subtitle: Text('${orgActivities
                                .length} Proposal(s)',
                                style: const TextStyle(fontSize: 12,
                                    color: Colors.grey)),
                            childrenPadding: const EdgeInsets.all(
                                24),
                            children: orgActivities.isEmpty
                                ? [
                              const Center(child: Text(
                                  'No GPOA proposals submitted.',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13)))
                            ]
                                : [
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 12),
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _archiveAllFor(
                                            orgActivities),
                                    icon: const Icon(
                                        Icons.archive_outlined,
                                        size: 18),
                                    label: const Text(
                                        'Archive all'),
                                  ),
                                ),
                              ),
                              ...orgActivities.map((act) =>
                                  _buildGPOAListTile(act, org)),
                            ],
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

  Future<void> _decide(Map<String, dynamic> act, String s,
      {BuildContext? dialogContext}) async {
    final isReject = s == 'Rejected';
    String remarks = '';
    if (s == 'Needs Revision' || isReject) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) =>
            AlertDialog(
              title: Text(isReject
                  ? 'Decline GPOA'
                  : 'Return for Revision'),
              content: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                Text(isReject
                    ? 'Reason for declining:'
                    : 'Explain changes needed:'),
                const SizedBox(height: 16),
                TextField(controller: c,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Remarks',
                        border: OutlineInputBorder())),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    if (c.text.trim().isNotEmpty) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isReject
                          ? Colors.red
                          : Colors.orange),
                  child: Text(
                      isReject ? 'Decline' : 'Send Feedback'),
                ),
              ],
            ),
      );
      if (ok != true) return;
      remarks = c.text.trim();
    }
    try {
      await Supabase.instance.client.from('activities').update({
        'status': s,
        'remarks': s == 'Approved' ? null : remarks,
        'revision_by': s == 'Needs Revision' ? 'Admin' : null,
      }).eq('id', act['id']);
      for (final role in ['president', 'adviser']) {
        AppUtils.sendNotification(
          title: s == 'Approved' ? 'GPOA Approved ✅' : (isReject
              ? 'GPOA Declined ❌'
              : 'GPOA Needs Revision ✏️'),
          body: s == 'Approved'
              ? '"${act['title']}" was approved by OSDW. Pick an event date and attach the letter under Events & Schedule.'
              : '"${act['title']}" was ${isReject
              ? 'declined'
              : 'returned for revision'} by OSDW. Open GPOA Proposals to read the remarks.',
          recipientRole: role,
          organizationId: act['organization_id']?.toString(),
        );
      }
      if (!mounted) return;
      AppUtils.showTopToast(context, s == 'Approved'
          ? 'GPOA approved and moved to scheduling!'
          : (isReject ? 'Proposal declined.' : 'Feedback sent.'));
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        AppUtils.showTopToast(context, 'Error: $e', isError: true);
      }
    }
  }

  Future<void> _approveAll(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) return;
    final ok = await _confirmBulk(
        context, 'Approve all ${list.length} proposals?',
        'Each organization will be notified and can then pick event dates.',
        'Approve all');
    if (!mounted || !ok) return;
    try {
      await Supabase.instance.client
          .from('activities')
          .update({
        'status': 'Approved',
        'remarks': null,
        'revision_by': null
      })
          .inFilter('id', list.map((a) => a['id']).toList());
      final orgIds = list
          .map((a) =>
          a['organization_id']?.toString())
          .whereType<String>()
          .toSet();
      for (final orgId in orgIds) {
        final n = list
            .where((a) => a['organization_id']?.toString() == orgId)
            .length;
        for (final role in ['president', 'adviser']) {
          AppUtils.sendNotification(
            title: 'GPOA Approved ✅',
            body: '$n proposal${n == 1
                ? ''
                : 's'} approved by OSDW. Pick event dates and attach letters under Events & Schedule.',
            recipientRole: role,
            organizationId: orgId,
          );
        }
      }
      if (!mounted) return;
      AppUtils.showTopToast(
          context, '${list.length} proposals approved.');
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        AppUtils.showTopToast(context, 'Error: $e', isError: true);
      }
    }
  }

  Future<void> _archiveAllFor(List<Map<String, dynamic>> acts) async {
    final ok = await _confirmBulk(context, 'Archive all ${acts.length}?', 'They will move to Archives. You can restore them there.', 'Archive all');
    if (!mounted || !ok) return;
    try {
      await _setArchived('activities', acts.map((a) => a['id']).toList(), true);
      if (!mounted) return;
      AppUtils.showTopToast(context, '${acts.length} GPOA archived.');
      widget.onRefresh();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not archive: $e', isError: true);
    }
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
            Text('Status: ${_adminLabel(act)}'),
            Text('Submitted: ${AppUtils.formatDateTime(act['created_at'])}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (act['status'] == 'Endorsed' && act['is_archived'] != true) ...[
              IconButton(tooltip: 'Approve', icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)), onPressed: () => _decide(act, 'Approved')),
              IconButton(tooltip: 'Revise', icon: const Icon(Icons.edit_note_rounded, color: Colors.orange), onPressed: () => _decide(act, 'Needs Revision')),
              IconButton(tooltip: 'Decline', icon: const Icon(Icons.cancel_rounded, color: Colors.red), onPressed: () => _decide(act, 'Rejected')),
            ],
            IconButton(
              tooltip: act['is_archived'] == true ? 'Restore GPOA' : 'Archive GPOA',
              icon: Icon(act['is_archived'] == true ? Icons.unarchive_outlined : Icons.archive_outlined, color: const Color(0xFF64748B)),
              onPressed: () async {
                final archived = act['is_archived'] == true;
                try {
                  await UserArchive.setArchived('activity', [act['id']], !archived);
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
                    proposedDate: (['Scheduled', 'Completed'].contains(act['status']) && act['proposed_date'] != null && act['proposed_date'].toString().trim().isNotEmpty) ? AppUtils.formatDateTime(act['proposed_date']) : null,
                    onStatusUpdate: act['status'] == 'Endorsed' ? (s) => _decide(act, s, dialogContext: context) : null,
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

const _approvedGpoaStates = ['Approved', 'Reschedule', 'Awaiting Date Approval', 'Scheduled', 'Completed'];

bool _gpoaLocked(List<Map<String, dynamic>> acts, {Map<String, dynamic>? orgData}) {
  if (orgData != null) {
    if (orgData['is_unlocked'] == false) return true;
    if (orgData['is_unlocked'] == true) return false;
  }

  // Automatic lock rule: Locked if org has active proposals and ALL of them are approved.
  final active = acts.where((a) => a['is_archived'] != true).toList();
  return active.isNotEmpty && active.every((a) => _approvedGpoaStates.contains(a['status']));
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
                final orgActs = activities.where((a) => a['organization_id']?.toString() == org['id']?.toString()).toList();
                return StatefulBuilder(builder: (context, setItem) {
                final isLocked = _gpoaLocked(orgActs, orgData: org);
                final isUnlocked = !isLocked;
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
                          Row(
                            children: [
                              Text(org['type'] ?? '', style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isUnlocked ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isUnlocked ? 'Proposals Unlocked 🔓' : 'Proposals Locked 🔒',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isUnlocked ? Colors.green : Colors.orange),
                                ),
                              ),
                            ],
                          ),
                          if (org['created_at'] != null)
                            Text('Registered: ${AppUtils.formatDateTime(org['created_at'])}', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                        ],
                      ),
                    ),

                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: isUnlocked ? 'Lock Proposal Submission' : 'Unlock Proposal Submission',
                        icon: Icon(isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: isUnlocked ? Colors.green : Colors.orange),
                        onPressed: () async {
                          final orgId = org['id']?.toString() ?? '';
                          final newStatus = !isUnlocked;
                          try {
                            // 1. Save to the database first
                            await Supabase.instance.client
                                .from('organizations')
                                .update({'is_unlocked': newStatus})
                                .eq('id', org['id']);
                            // 2. Only after it succeeded, update local state
                            org['is_unlocked'] = newStatus;
                            await OrgUnlockService.setStatus(orgId, newStatus);
                            // 3. Redraw this row
                            setItem(() {});
                            if (context.mounted) {
                              AppUtils.showTopToast(context, newStatus ? '${org['name']} unlocked for new proposals!' : '${org['name']} proposal submission locked.');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              AppUtils.showTopToast(context, 'Could not update lock: $e', isError: true);
                            }
                          }
                        },
                      ),
                      IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue), onPressed: () => _showEditOrgDialog(context, org)),
                      IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red), onPressed: () => _showDeleteConfirm(context, org)),
                    ]),
                  ),
                );
                });
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


class _ManageUsersView extends StatefulWidget {
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> profiles;
  final VoidCallback onRefresh;
  final String searchQuery;

  const _ManageUsersView({
    required this.organizations,
    required this.profiles,
    required this.onRefresh,
    this.searchQuery = '',
  });

  @override
  State<_ManageUsersView> createState() => _ManageUsersViewState();
}

class _ManageUsersViewState extends State<_ManageUsersView> {
  List<Map<String, dynamic>> _localProfiles = [];

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  Future<void> _fetchProfiles() async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('*, organizations(*)');
      if (mounted) {
        setState(() {
          _localProfiles = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  String _getNormalizedEmail(Map<String, dynamic> user) {
    final rawEmail = (user['email'] ?? '').toString().trim();
    if (rawEmail.isNotEmpty && rawEmail.contains('@')) return rawEmail;
    return rawEmail.isNotEmpty ? '$rawEmail@csu.edu.ph' : 'user@csu.edu.ph';
  }

  Map<String, dynamic> _getAssignedOrg(Map<String, dynamic> user) {
    final orgId = user['organization_id']?.toString();
    if (orgId != null && orgId.isNotEmpty) {
      final match = widget.organizations.firstWhere(
            (o) => o['id']?.toString() == orgId,
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) return match;
    }

    return {'name': 'System / Independent'};
  }

  @override
  Widget build(BuildContext context) {
    final activeProfiles = _localProfiles.isNotEmpty ? _localProfiles : widget.profiles;

    final filtered = activeProfiles.where((p) {
      final normEmail = _getNormalizedEmail(p);
      final query = widget.searchQuery.toLowerCase();
      if (query.isEmpty) return true;

      final name = (p['full_name'] ?? '').toString().toLowerCase().contains(query);
      final email = normEmail.toLowerCase().contains(query);
      final role = (p['role'] ?? '').toString().toLowerCase().contains(query);
      final org = _getAssignedOrg(p);
      final orgNameMatches = (org['name'] ?? '').toString().toLowerCase().contains(query);

      return name || email || role || orgNameMatches;
    }).toList();

    return Padding(
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
                  const Text('User Accounts', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                  const SizedBox(height: 4),
                  Text('Managing ${activeProfiles.length} system accounts across all roles (Admin, Adviser, President).', style: const TextStyle(color: Color(0xFF64748B), fontSize: 15, fontWeight: FontWeight.w500)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddUserDialog(context),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Provision New Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No user accounts found.'))
                : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (c, i) {
                final user = filtered[i];
                final role = user['role'] ?? 'User';
                final email = _getNormalizedEmail(user);
                final org = _getAssignedOrg(user);

                Color avatarColor = const Color(0xFF6366F1);
                IconData avatarIcon = Icons.person_rounded;
                if (role == 'Admin') { avatarColor = const Color(0xFFDC2626); avatarIcon = Icons.admin_panel_settings_rounded; }
                if (role == 'Adviser') { avatarColor = const Color(0xFF0284C7); avatarIcon = Icons.verified_user_rounded; }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF1F5F9))),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    leading: CircleAvatar(
                      backgroundColor: avatarColor.withValues(alpha: 0.1),
                      child: Icon(avatarIcon, color: avatarColor, size: 22),
                    ),
                    title: Text(user['full_name'] ?? 'Unknown User', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B))),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('$email • $role • ${org['name']}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                        if (user['created_at'] != null)
                          Text('Provisioned: ${AppUtils.formatDateTime(user['created_at'])}', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit User',
                          icon: const Icon(Icons.edit_rounded, color: Color(0xFF0284C7)),
                          onPressed: () => _showEditUserDialog(context, user),
                        ),
                        IconButton(
                          tooltip: 'Reset Password',
                          icon: const Icon(Icons.lock_reset_rounded, color: Color(0xFFD97706)),
                          onPressed: () => _showResetPasswordDialog(context, user),
                        ),
                        if (user['is_super_admin'] == true)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Tooltip(
                              message: 'Super admin cannot be deleted',
                              child: Icon(Icons.lock_rounded, color: Color(0xFF94A3B8)),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Delete Account',
                            icon: const Icon(Icons.person_remove_rounded, color: Color(0xFFDC2626)),
                            onPressed: () => _showDeleteConfirm(context, user),
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

  void _showDeleteConfirm(BuildContext context, Map<String, dynamic> user) {
    final userId = user['id']?.toString();
    final userEmail = _getNormalizedEmail(user);

    if (user['is_super_admin'] == true) {
      AppUtils.showTopToast(context, 'The super admin account cannot be deleted.', isError: true);
      return;
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 10),
            Text('Delete Account?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text('Are you sure you want to permanently delete the account for "${user['full_name']}" ($userEmail)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (userId == null || userId.isEmpty) {
                AppUtils.showTopToast(c, 'This account has no ID and cannot be deleted.', isError: true);
                return;
              }
              try {
                await UserAdminService.deleteUser(userId);

                AppUtils.sendNotification(
                  title: 'Account Deleted 🗑️',
                  body: 'Account for ${user['full_name']} has been permanently deleted.',
                  recipientRole: 'admin',
                );

                if (c.mounted) {
                  setState(() {
                    _localProfiles.removeWhere((p) => p['id']?.toString() == userId);
                  });
                  AppUtils.showTopToast(c, 'Account $userEmail permanently deleted.');
                  Navigator.pop(c);
                  widget.onRefresh();
                  _fetchProfiles();
                }
              } catch (e) {
                if (c.mounted) {
                  AppUtils.showTopToast(c, e.toString().replaceFirst('Exception: ', ''), isError: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, Map<String, dynamic> user) {
    final userId = user['id']?.toString();
    final isSelf = userId != null && userId == Supabase.instance.client.auth.currentUser?.id;
    final isSuper = user['is_super_admin'] == true;

    final name = TextEditingController(text: (user['full_name'] ?? '').toString());
    final emailCtrl = TextEditingController(text: (user['email'] ?? '').toString());
    String role = ['Admin', 'Adviser', 'President'].contains(user['role']) ? user['role'] as String : 'President';
    String? orgId = user['organization_id']?.toString();
    if (!widget.organizations.any((o) => o['id'].toString() == orgId)) orgId = null;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.edit_rounded, color: Color(0xFF0284C7), size: 24),
              const SizedBox(width: 10),
              Text(isSuper ? 'Edit Super Admin' : 'Edit Account',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSuper)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'This is the super admin account. You can only change its name, email and password. It cannot be deleted.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                      ),
                    ),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: 'Full Name *',
                      prefixIcon: const Icon(Icons.person_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isSuper)
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email Address *',
                        prefixIcon: const Icon(Icons.email_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: isSelf ? 'Account Role (cannot change your own)' : 'Account Role *',
                        prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Admin', child: Text('System Administrator')),
                        DropdownMenuItem(value: 'Adviser', child: Text('Faculty Adviser')),
                        DropdownMenuItem(value: 'President', child: Text('Student Leader / President')),
                      ],
                      onChanged: isSelf ? null : (v) { if (v != null) setDialogState(() => role = v); },
                    ),
                    const SizedBox(height: 16),
                    if (role != 'Admin')
                      DropdownButtonFormField<String?>(
                        initialValue: orgId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Assigned Organization',
                          prefixIcon: const Icon(Icons.business_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('No Organization')),
                          ...widget.organizations.map((e) => DropdownMenuItem<String?>(
                            value: e['id'].toString(),
                            child: Text(e['name'] ?? 'Organization', overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) => setDialogState(() => orgId = v),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                final newName = name.text.trim();
                final newEmail = emailCtrl.text.trim().toLowerCase();
                if (newName.isEmpty) {
                  AppUtils.showTopToast(c, 'Full Name is required.', isError: true);
                  return;
                }
                if (userId == null || userId.isEmpty) {
                  AppUtils.showTopToast(c, 'This account has no ID and cannot be edited.', isError: true);
                  return;
                }
                if (isSuper && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(newEmail)) {
                  AppUtils.showTopToast(c, 'Enter a valid email address.', isError: true);
                  return;
                }
                if (!isSuper && role != 'Admin' && orgId == null) {
                  AppUtils.showTopToast(c, 'Please assign an organization for this role.', isError: true);
                  return;
                }

                setDialogState(() => isSaving = true);
                try {
                  if (isSuper) {
                    await UserAdminService.updateAccount(
                      id: userId,
                      fullName: newName,
                      email: newEmail,
                    );
                  } else {
                    await Supabase.instance.client.from('profiles').update({
                      'full_name': newName,
                      'role': role,
                      'organization_id': role == 'Admin' ? null : orgId,
                    }).eq('id', userId);
                  }

                  if (c.mounted) {
                    AppUtils.showTopToast(c, 'Account updated successfully!');
                    Navigator.pop(c);
                  }
                  widget.onRefresh();
                  _fetchProfiles();
                } catch (e) {
                  if (c.mounted) {
                    setDialogState(() => isSaving = false);
                    AppUtils.showTopToast(c, e.toString().replaceFirst('Exception: ', ''), isError: true);
                  }
                }
              },
              icon: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext context, Map<String, dynamic> user) {
    final userId = user['id']?.toString();
    final userEmail = _getNormalizedEmail(user);
    final pass = TextEditingController();
    final confirm = TextEditingController();
    bool obscure = true;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.lock_reset_rounded, color: Color(0xFFD97706), size: 24),
              SizedBox(width: 10),
              Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Set a new password for "${user['full_name'] ?? 'this user'}" ($userEmail).',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pass,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password * (min. 8 characters)',
                      prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirm,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password *',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                if (userId == null || userId.isEmpty) {
                  AppUtils.showTopToast(c, 'This account has no ID.', isError: true);
                  return;
                }
                if (pass.text.length < 8) {
                  AppUtils.showTopToast(c, 'Password must be at least 8 characters.', isError: true);
                  return;
                }
                if (pass.text != confirm.text) {
                  AppUtils.showTopToast(c, 'Passwords do not match.', isError: true);
                  return;
                }

                setDialogState(() => isSaving = true);
                try {
                  await adminResetPassword(userId, pass.text);

                  AppUtils.sendNotification(
                    title: 'Password Reset 🔑',
                    body: 'The password for ${user['full_name']} was reset by OSDW Admin.',
                    recipientRole: 'admin',
                  );

                  if (c.mounted) {
                    AppUtils.showTopToast(c, 'Password for $userEmail reset successfully!');
                    Navigator.pop(c);
                  }
                } catch (e) {
                  if (c.mounted) {
                    setDialogState(() => isSaving = false);
                    AppUtils.showTopToast(c, e.toString().replaceFirst('Exception: ', ''), isError: true);
                  }
                }
              },
              icon: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Reset Password'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  List<Map<String, dynamic>> get _allProfiles =>
      _localProfiles.isNotEmpty ? _localProfiles : widget.profiles;

  /// Adviser/President roles already assigned in this org
  List<String> _takenRoles(String orgId) => _allProfiles
      .where((p) =>
  p['organization_id']?.toString() == orgId &&
      ['Adviser', 'President'].contains(p['role']))
      .map((p) => p['role'].toString())
      .toList();

  /// Orgs that still have room (fewer than 2 assigned users)
  List<Map<String, dynamic>> get _orgsWithRoom =>
      widget.organizations.where((o) => _takenRoles(o['id'].toString()).length < 2).toList();

  /// Role choices depend on the org type and on which roles are still free
  List<DropdownMenuItem<String>> _roleItemsFor(String? orgId) {
    if (orgId == null) {
      return const [DropdownMenuItem(value: 'Admin', child: Text('System Administrator'))];
    }
    final org = widget.organizations.firstWhere(
          (o) => o['id'].toString() == orgId,
      orElse: () => <String, dynamic>{},
    );
    final isCollege = (org['type'] ?? '').toString().toLowerCase().contains('college');
    final taken = _takenRoles(orgId);
    return [
      if (!taken.contains('Adviser'))
        const DropdownMenuItem(value: 'Adviser', child: Text('Adviser')),
      if (!taken.contains('President'))
        DropdownMenuItem(
          value: 'President',
          child: Text(isCollege ? 'Governor (President)' : 'President'),
        ),
    ];
  }
  void _showAddUserDialog(BuildContext context) {
    final name = TextEditingController();
    final email = TextEditingController();
    final pass = TextEditingController();
    String role = 'Admin';
    String? orgId;
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.person_add_rounded, color: Color(0xFF6366F1), size: 24),
              SizedBox(width: 10),
              Text('Provision New Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: 'Full Name *',
                      prefixIcon: const Icon(Icons.person_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: email,
                    decoration: InputDecoration(
                      labelText: 'Email Address *',
                      prefixIcon: const Icon(Icons.email_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pass,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Initial Password * (min. 8 characters)',
                      prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 20,
                          color: const Color(0xFF64748B),
                        ),
                        onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 1) Organization first (full orgs are hidden)
                  DropdownButtonFormField<String?>(
                    initialValue: orgId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Assigned Organization',
                      prefixIcon: const Icon(Icons.business_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('System Administrator (No Org)')),
                      ..._orgsWithRoom.map((e) => DropdownMenuItem<String?>(
                        value: e['id'].toString(),
                        child: Text(e['name'] ?? 'Organization', overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() {
                      orgId = v;
                      final items = _roleItemsFor(v);
                      role = items.isEmpty ? 'Admin' : items.first.value!;
                    }),
                  ),
                  const SizedBox(height: 16),
                  // 2) Role choices depend on the org
                  DropdownButtonFormField<String>(
                    key: ValueKey('role-$orgId-$role'),
                    initialValue: role,
                    decoration: InputDecoration(
                      labelText: 'Account Role *',
                      prefixIcon: const Icon(Icons.badge_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _roleItemsFor(orgId),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => role = v);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () async {
                final newName = name.text.trim();
                final newEmail = email.text.trim().toLowerCase();
                final newPass = pass.text; // do not trim passwords

                if (newName.isEmpty || newEmail.isEmpty || newPass.isEmpty) {
                  AppUtils.showTopToast(c, 'Full Name, Email Address, and Initial Password are required.', isError: true);
                  return;
                }
                if (newPass.length < 8) {
                  AppUtils.showTopToast(c, 'Password must be at least 8 characters.', isError: true);
                  return;
                }
                if (orgId != null && !_roleItemsFor(orgId).any((i) => i.value == role)) {
                  AppUtils.showTopToast(c, 'That role is already taken in this organization.', isError: true);
                  return;
                }

                final targetEmail = newEmail.contains('@') ? newEmail : '$newEmail@csu.edu.ph';

                try {
                  await UserAdminService.createUser(
                    fullName: newName,
                    email: targetEmail,
                    password: newPass,
                    role: role,
                    organizationId: orgId,
                  );

                  AppUtils.sendNotification(
                    title: 'New Account Provisioned 👤',
                    body: 'Account for $newName has been provisioned.',
                    recipientRole: 'admin',
                  );

                  widget.onRefresh();
                  _fetchProfiles();

                  if (c.mounted) {
                    AppUtils.showTopToast(c, 'Account $targetEmail created successfully!');
                    Navigator.pop(c);
                  }
                } catch (e) {
                  if (c.mounted) {
                    AppUtils.showTopToast(c, e.toString().replaceFirst('Exception: ', ''), isError: true);
                  }
                }
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Provision Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageEventsView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  final VoidCallback onRefresh;
  final String? initialTab;
  final String? openEventId;
  const _ManageEventsView({
    super.key,
    required this.activities,
    required this.organizations,
    required this.onRefresh,
    this.initialTab,
    this.openEventId,
  });
  @override
  State<_ManageEventsView> createState() => _ManageEventsViewState();
}


class _ManageEventsViewState extends State<_ManageEventsView> {
  String? _selectedOrgId;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    final id = widget.openEventId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final act = widget.activities.firstWhere(
              (a) => a['id']?.toString() == id,
          orElse: () => <String, dynamic>{},
        );
        if (act.isEmpty) return;
        final org = widget.organizations.firstWhere(
              (o) => o['id'].toString() == act['organization_id']?.toString(),
          orElse: () => {'name': 'Unknown Org'},
        );
        _showEventDetails(context, act, org);
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeActivities = widget.activities.where((a) => a['is_archived'] != true).toList();
    DateTime requestedAt(Map<String, dynamic> a) =>
        DateTime.tryParse(a['date_requested_at']?.toString() ?? '') ??
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.now();

    final awaiting = activeActivities.where((a) => a['status'] == 'Awaiting Date Approval').toList()
      ..sort((a, b) => requestedAt(a).compareTo(requestedAt(b)));

    DateTime? startOf(Map<String, dynamic> a) {
      final raw = a['proposed_date']?.toString().trim() ?? '';
      if (raw.isEmpty) return null;
      try {
        return DateTime.parse(raw).toLocal();
      } catch (_) {
        return null;
      }
    }

    final ongoing = activeActivities.where((a) {
      final status = a['status']?.toString();
      if (status != 'Scheduled') return false;
      if (_selectedOrgId != null && a['organization_id']?.toString() != _selectedOrgId) return false;
      final start = startOf(a);
      return start != null;
    }).toList()
      ..sort((a, b) => startOf(a)!.compareTo(startOf(b)!));

    final conflictRequests = awaiting.where((event) =>
    (_selectedOrgId == null || event['organization_id']?.toString() == _selectedOrgId) &&
        _findScheduleConflicts(event, activeActivities).isNotEmpty).toList();

    final List<Map<String, dynamic>> orgsToDisplay = widget.organizations
        .where((o) => _selectedOrgId == null || o['id'].toString() == _selectedOrgId)
        .toList();

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab == 'ongoing' ? 1 : 0,
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
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.pending_actions_rounded, size: 18), const SizedBox(width: 8), Text('Awaiting Approval (${awaiting.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.play_circle_fill_rounded, size: 18), const SizedBox(width: 8), Text('Scheduled & Ongoing (${ongoing.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
                  const Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_month_rounded, size: 18), SizedBox(width: 8), Text('Organizations Schedule', style: TextStyle(fontWeight: FontWeight.bold))])),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.warning_amber_rounded, size: 18), const SizedBox(width: 8), Text('Schedule Conflicts (${conflictRequests.length})', style: const TextStyle(fontWeight: FontWeight.bold))])),
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
                  // Ongoing events
                  ongoing.isEmpty
                      ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy_rounded, size: 48, color: Color(0xFF94A3B8)),
                        SizedBox(height: 16),
                        Text('No scheduled events found.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                      : ListView.builder(
                    itemCount: ongoing.length,
                    itemBuilder: (context, index) {
                      final act = ongoing[index];
                      final org = widget.organizations.firstWhere(
                            (o) => o['id'].toString() == act['organization_id']?.toString(),
                        orElse: () => {'name': 'Unknown Org'},
                      );
                      return _buildEventCard(context, act, org);
                    },
                  ),
                  // Tab 2: Organization-based groupings
                  ListView.builder(
                    itemCount: orgsToDisplay.length,
                    itemBuilder: (context, index) {
                      final org = orgsToDisplay[index];
                      final orgActs = activeActivities.where((a) => a['organization_id']?.toString() == org['id'].toString() && ['Approved', 'Scheduled', 'Completed', 'Awaiting Date Approval', 'Needs Revision', 'Reschedule'].contains(a['status'])).toList();

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
                  // Schedule conflicts are warnings only. Admin can approve each request even when it overlaps another event.
                  conflictRequests.isEmpty
                      ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline_rounded, size: 44, color: Colors.green), SizedBox(height: 12), Text('No schedule conflicts detected.', style: TextStyle(color: Colors.grey))]))
                      : ListView.builder(
                    itemCount: conflictRequests.length,
                    itemBuilder: (context, index) {
                      final event = conflictRequests[index];
                      final eventOrg = widget.organizations.firstWhere((o) => o['id']?.toString() == event['organization_id']?.toString(), orElse: () => {'name': 'Unknown Organization'});
                      final conflicts = _findScheduleConflicts(event, activeActivities);
                      final start = DateTime.tryParse(event['proposed_date']?.toString() ?? '')?.toLocal();
                      final end = start?.add(AppUtils.parseDuration(event['time_frame']));
                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFCA5A5))),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)), const SizedBox(width: 8), Expanded(child: Text('${eventOrg['name'] ?? 'Unknown Organization'} — ${event['title'] ?? 'Untitled Event'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(20)), child: Text('${conflicts.length} conflict(s)', style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.bold, fontSize: 12)))]),
                            const SizedBox(height: 12),
                            Text('Date: ${start == null ? 'Not set' : AppUtils.formatDateTime(start.toIso8601String())}'),
                            Text('Start time: ${start == null ? '—' : _fmt12(start)}'),
                            Text('End time: ${end == null ? '—' : _fmt12(end)}'),
                            Text('Facilities and materials: ${(event['facilities_materials'] ?? 'Not specified').toString()}'),
                            const SizedBox(height: 12),
                            const Text('Conflicting event schedules', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF991B1B))),
                            const SizedBox(height: 6),
                            ...conflicts.map((other) {
                              final otherOrg = widget.organizations.firstWhere((o) => o['id']?.toString() == other['organization_id']?.toString(), orElse: () => {'name': 'Unknown Organization'});
                              final otherStart = DateTime.tryParse(other['proposed_date']?.toString() ?? '')?.toLocal();
                              final otherEnd = otherStart?.add(AppUtils.parseDuration(other['time_frame']));
                              return Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF7F7), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Organization: ${otherOrg['name'] ?? 'Unknown Organization'}', style: const TextStyle(fontWeight: FontWeight.w700)), Text('Event: ${other['title'] ?? 'Untitled Event'}'), Text('Date: ${otherStart == null ? 'Not set' : AppUtils.formatDateTime(otherStart.toIso8601String())}'), Text('Start: ${otherStart == null ? '—' : _fmt12(otherStart)}   End: ${otherEnd == null ? '—' : _fmt12(otherEnd)}'), Text('Facilities and materials: ${(other['facilities_materials'] ?? 'Not specified').toString()}'), Text('Status: ${other['status']}', style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), fontWeight: FontWeight.w700))]));
                            }),
                            const SizedBox(height: 16),
                            const Text('This is a warning only. You may approve this event even if another event overlaps.', style: TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              OutlinedButton.icon(onPressed: () => _declineConflictEvent(event), icon: const Icon(Icons.close_rounded), label: const Text('Reject'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red)),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(onPressed: () => _approveConflictEvent(event, conflicts.length), icon: const Icon(Icons.check_rounded), label: const Text('Approve'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white)),
                            ]),
                          ]),
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

  List<Map<String, dynamic>> _findScheduleConflicts(Map<String, dynamic> event, List<Map<String, dynamic>> candidates) {
    final rawStart = event['proposed_date']?.toString().trim() ?? '';
    if (rawStart.isEmpty) return [];
    final start = DateTime.tryParse(rawStart)?.toLocal();
    if (start == null) return [];
    final end = start.add(AppUtils.parseDuration(event['time_frame']));
    return candidates.where((other) {
      if (other['id']?.toString() == event['id']?.toString() || other['is_archived'] == true) return false;
      if (!['Awaiting Date Approval', 'Scheduled'].contains(other['status'])) return false;
      final otherRaw = other['proposed_date']?.toString().trim() ?? '';
      if (otherRaw.isEmpty) return false;
      final otherStart = DateTime.tryParse(otherRaw)?.toLocal();
      if (otherStart == null) return false;
      final otherEnd = otherStart.add(AppUtils.parseDuration(other['time_frame']));

      final sameDay = start.year == otherStart.year && start.month == otherStart.month && start.day == otherStart.day;
      final timeOverlap = start.isBefore(otherEnd) && end.isAfter(otherStart);
      return sameDay || timeOverlap;
    }).toList();
  }

  Future<void> _approveConflictEvent(Map<String, dynamic> event, int conflictCount) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Approve Event Date?'),
      content: Text(conflictCount > 0 ? 'Warning: this event overlaps with $conflictCount other event(s). This is only a warning. Do you still want to approve it?' : 'Approve this event date?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve anyway'))],
    ));
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.from('activities').update({'status': 'Scheduled', 'remarks': null}).eq('id', event['id']);
      for (final role in ['president', 'adviser']) {
        AppUtils.sendNotification(title: 'Event Date Confirmed 📅', body: 'Proposed date for "${event['title']}" confirmed for ${AppUtils.formatEventRange(event['proposed_date'], event['time_frame'])}.', recipientRole: role, organizationId: event['organization_id']?.toString());
      }
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Event date approved. Conflict warning does not block approval.');
      widget.onRefresh();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not approve event: $e', isError: true);
    }
  }

  Future<void> _declineConflictEvent(Map<String, dynamic> event) async {
    final remarks = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reject Event Date'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Provide feedback so the organization can propose another date.'), const SizedBox(height: 12), TextField(controller: remarks, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason / feedback', border: OutlineInputBorder()))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Reject'))],
    ));
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.from('activities').update({'status': 'Reschedule', 'remarks': remarks.text.trim()}).eq('id', event['id']);
      for (final role in ['president', 'adviser']) {
        AppUtils.sendNotification(title: 'Event Date Rejected ⚠️', body: 'The proposed date for "${event['title']}" was rejected. Please review the feedback and propose a new date.', recipientRole: role, organizationId: event['organization_id']?.toString());
      }
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Event date rejected; rescheduling requested.');
      widget.onRefresh();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not reject event: $e', isError: true);
    }
  }

  int _queueRank(Map<String, dynamic> act) {
    DateTime t(Map<String, dynamic> a) =>
        DateTime.tryParse(a['date_requested_at']?.toString() ?? '') ??
            DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
    final q = widget.activities
        .where((a) => a['status'] == 'Awaiting Date Approval' && a['is_archived'] != true)
        .toList()
      ..sort((a, b) => t(a).compareTo(t(b)));
    return q.indexWhere((a) => a['id'] == act['id']) + 1;
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
                if (isAwaiting) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('#${_queueRank(act)} in queue', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6366F1))),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(Icons.access_time_rounded, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(AppUtils.formatEventRange(act['proposed_date'], act['time_frame']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((act['letter_url'] ?? '').toString().isNotEmpty)
              IconButton(
                tooltip: 'View attached letter',
                icon: const Icon(Icons.file_present_rounded, color: Color(0xFF6366F1)),
                onPressed: () async {
                  final ok = await StorageUtils.open(act['letter_url'].toString());
                  if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the letter.', isError: true);
                },
              ),
            if ((act['concept_paper_url'] ?? '').toString().isNotEmpty)
              IconButton(
                tooltip: 'View concept paper',
                icon: const Icon(Icons.description_outlined, color: Color(0xFF6366F1)),
                onPressed: () async {
                  final ok = await StorageUtils.open(act['concept_paper_url'].toString());
                  if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the concept paper.', isError: true);
                },
              ),
            if ((act['letter_url'] ?? '').toString().isNotEmpty || (act['concept_paper_url'] ?? '').toString().isNotEmpty)
              const SizedBox(width: 8),
            if (isAwaiting)
              ElevatedButton(
                onPressed: () => _showEventDetails(context, act, org),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, elevation: 0),
                child: const Text('Review Date'),
              )
            else
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
          ],
        ),
        onTap: () => _showEventDetails(context, act, org),
      ),
    );
  }

  void _showEventDetails(BuildContext context, Map<String, dynamic> act, Map<String, dynamic> org) {
    final conflictingEvents = _findScheduleConflicts(act, widget.activities);

    conflictingEvents.sort((a, b) {
      DateTime t(Map<String, dynamic> x) =>
          DateTime.tryParse(x['date_requested_at']?.toString() ?? '') ??
              DateTime.tryParse(x['created_at']?.toString() ?? '') ?? DateTime.now();
      if (a['status'] == 'Scheduled' && b['status'] != 'Scheduled') return -1;
      if (b['status'] == 'Scheduled' && a['status'] != 'Scheduled') return 1;
      return t(a).compareTo(t(b));
    });

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
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
                const Divider(height: 36, color: Color(0xFFF1F5F9)),
                if (conflictingEvents.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                            SizedBox(width: 10),
                            Text(
                              'SCHEDULE CONFLICT DETECTED!',
                              style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFDC2626), fontSize: 14, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'There are ${conflictingEvents.length} conflicting event(s) scheduled on the same date/time window. The earliest request is listed first.',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          children: conflictingEvents.map((cAct) {
                            final cOrg = widget.organizations.firstWhere(
                                  (o) => o['id']?.toString() == cAct['organization_id']?.toString(),
                              orElse: () => {'name': 'Organization'},
                            );
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_busy_rounded, color: Color(0xFFDC2626), size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(cAct['title'] ?? 'Untitled Event', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                                        Text('${cOrg['name']} • ${AppUtils.formatEventRange(cAct['proposed_date'], cAct['time_frame'])}',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                        if ((cAct['facilities_materials'] ?? '').toString().trim().isNotEmpty)
                                          Text('Facilities: ${cAct['facilities_materials']}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                        Text(
                                          cAct['status'] == 'Scheduled'
                                              ? 'Already approved'
                                              : 'Requested ${AppUtils.formatDateTime(cAct['date_requested_at'] ?? cAct['created_at'])}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusBadge(status: cAct['status'] ?? 'Scheduled'),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                if (act['status'] != 'Awaiting Date Approval')
                  Builder(builder: (_) {
                    final n = DateTime.now();
                    DateTime? s;
                    try {
                      s = DateTime.parse(act['proposed_date'].toString()).toLocal();
                    } catch (_) {}
                    String live = 'Scheduled';
                    Color liveColor = const Color(0xFF6366F1);
                    if (s != null) {
                      final e = s.add(AppUtils.parseDuration(act['time_frame']));
                      if (n.isBefore(s)) {
                        live = 'Upcoming';
                      } else if (n.isBefore(e)) {
                        live = 'Happening now';
                        liveColor = const Color(0xFF10B981);
                      } else {
                        live = 'Ended';
                        liveColor = const Color(0xFF64748B);
                      }
                    }
                    return Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: liveColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded, color: liveColor),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('EVENT DATE & TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1)),
                                const SizedBox(height: 4),
                                Text(AppUtils.formatEventRange(act['proposed_date'], act['time_frame']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: liveColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(live, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: liveColor)),
                          ),
                        ],
                      ),
                    );
                  }),
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
                                title: Row(
                                  children: [
                                    Icon(conflictingEvents.isNotEmpty ? Icons.warning_amber_rounded : Icons.event_available_rounded, color: conflictingEvents.isNotEmpty ? const Color(0xFFDC2626) : const Color(0xFF10B981)),
                                    const SizedBox(width: 10),
                                    Text(conflictingEvents.isNotEmpty ? 'Schedule Conflict Warning' : 'Approve Event Date'),
                                  ],
                                ),
                                content: Text(
                                  conflictingEvents.isNotEmpty
                                      ? 'WARNING: There are ${conflictingEvents.length} conflicting event(s) scheduled on this exact date/time window. Are you sure you want to approve this schedule anyway?'
                                      : 'Are you sure you want to approve this schedule? The organization will be notified.',
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: conflictingEvents.isNotEmpty ? const Color(0xFFDC2626) : const Color(0xFF10B981)),
                                    child: Text(conflictingEvents.isNotEmpty ? 'Approve Despite Conflict' : 'Confirm Approval'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                await Supabase.instance.client.from('activities').update({'status': 'Scheduled'}).eq('id', act['id']);

                                AppUtils.sendNotification(
                                  title: 'Event Date Confirmed 📅',
                                  body: 'Proposed date for "${act['title']}" confirmed for ${AppUtils.formatEventRange(act['proposed_date'], act['time_frame'])}.',
                                  recipientRole: 'president',
                                  organizationId: act['organization_id']?.toString(),
                                );
                                AppUtils.sendNotification(
                                  title: 'Event Date Confirmed 📅',
                                  body: 'Proposed date for "${act['title']}" confirmed for ${AppUtils.formatEventRange(act['proposed_date'], act['time_frame'])}.',
                                  recipientRole: 'adviser',
                                  organizationId: act['organization_id']?.toString(),
                                );

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
                                title: const Text('Reject Event Date'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Explain why this proposed date is rejected:'),
                                    const SizedBox(height: 16),
                                    TextField(controller: remarkController, decoration: const InputDecoration(labelText: 'Feedback for Organization', border: OutlineInputBorder()), maxLines: 3),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(rtx, false), child: const Text('Cancel')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(rtx, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                                    child: const Text('Reject Date'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              try {
                                await Supabase.instance.client.from('activities').update({'status': 'Reschedule', 'remarks': remarkController.text}).eq('id', act['id']);
                                for (final role in ['president', 'adviser']) {
                                  AppUtils.sendNotification(
                                    title: 'Event Date Rejected ⚠️',
                                    body: '"${act['title']}": Proposed date rejected by OSDW. Read the feedback and propose a new date.',
                                    recipientRole: role,
                                    organizationId: act['organization_id']?.toString(),
                                  );
                                }
                                if (ctx.mounted) {
                                  AppUtils.showTopToast(ctx, 'Event date rejected; rescheduling requested.');
                                  Navigator.pop(ctx);
                                }
                                widget.onRefresh();
                              } catch (e) {
                                if (ctx.mounted) AppUtils.showTopToast(ctx, 'Error: $e', isError: true);
                              }
                            }
                          },
                          icon: const Icon(Icons.cancel_outlined, size: 18),
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
                if ((act['letter_url'] ?? '').toString().isNotEmpty || (act['concept_paper_url'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if ((act['letter_url'] ?? '').toString().isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await StorageUtils.open(act['letter_url'].toString());
                              if (!ok && ctx.mounted) AppUtils.showTopToast(ctx, 'Could not open the letter.', isError: true);
                            },
                            icon: const Icon(Icons.file_present_rounded, size: 18),
                            label: const Text('View Attached Letter'),
                          ),
                        if ((act['concept_paper_url'] ?? '').toString().isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await StorageUtils.open(act['concept_paper_url'].toString());
                              if (!ok && ctx.mounted) AppUtils.showTopToast(ctx, 'Could not open the concept paper.', isError: true);
                            },
                            icon: const Icon(Icons.description_outlined, size: 18),
                            label: const Text('View Concept Paper'),
                          ),
                      ],
                    ),
                  ),
                GPOAActivityDetailsView(
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
                  proposedDate: (['Scheduled', 'Completed'].contains(act['status']) && act['proposed_date'] != null && act['proposed_date'].toString().trim().isNotEmpty)
                      ? AppUtils.formatEventRange(act['proposed_date'], act['time_frame']) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccomplishmentReportsView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> organizations;
  final VoidCallback onRefresh;

  const _AccomplishmentReportsView({
    required this.activities,
    required this.organizations,
    required this.onRefresh,
  });

  @override
  State<_AccomplishmentReportsView> createState() => _AccomplishmentReportsViewState();
}

class _AccomplishmentReportsViewState extends State<_AccomplishmentReportsView> {
  bool _showApprovedFilter = false;
  String? _selectedOrgId;
  List<Map<String, dynamic>> _reportsList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    try {
      final res = await Supabase.instance.client
          .from('accomplishment_reports')
          .select('*, activities(*)')
          .order('report_date', ascending: false);

      final reps = await UserArchive.decorate(List<Map<String, dynamic>>.from(res), 'report');
      if (mounted) {
        setState(() {
          _reportsList = reps;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final awaitingCount = _reportsList.where((rep) {
      if (rep['is_archived'] == true) return false;
      final orgId = rep['organization_id']?.toString() ?? rep['activities']?['organization_id']?.toString() ?? 'unknown';
      if (_selectedOrgId != null && orgId != _selectedOrgId) return false;

      final repStatusLower = (rep['status'] ?? 'Pending').toString().toLowerCase();
      return !['approved', 'completed', 'verified', 'passed'].contains(repStatusLower);
    }).length;

    final approvedCount = _reportsList.where((rep) {
      if (rep['is_archived'] == true) return false;
      final orgId = rep['organization_id']?.toString() ?? rep['activities']?['organization_id']?.toString() ?? 'unknown';
      if (_selectedOrgId != null && orgId != _selectedOrgId) return false;

      final repStatusLower = (rep['status'] ?? 'Pending').toString().toLowerCase();
      return ['approved', 'completed', 'verified', 'passed'].contains(repStatusLower);
    }).length;

    // Categorize / Group reports by Organization
    final Map<String, List<Map<String, dynamic>>> groupedReports = {};

    for (var rep in _reportsList) {
      if (rep['is_archived'] == true) continue;

      final act = rep['activities'] as Map<String, dynamic>? ?? {};
      final orgId = rep['organization_id']?.toString() ?? act['organization_id']?.toString() ?? 'unknown';

      if (_selectedOrgId != null && orgId != _selectedOrgId) {
        continue;
      }

      final repStatusLower = (rep['status'] ?? 'Pending').toString().toLowerCase();
      final isReportApproved = ['approved', 'completed', 'verified', 'passed'].contains(repStatusLower);

      if (_showApprovedFilter && !isReportApproved) continue;
      if (!_showApprovedFilter && isReportApproved) continue;

      final org = widget.organizations.firstWhere(
            (o) => o['id'].toString() == orgId,
        orElse: () => {'name': rep['organization_name'] ?? act['organization_name'] ?? 'College Organization'},
      );

      final orgName = (org['name'] ?? 'College Organization').toString();
      groupedReports.putIfAbsent(orgName, () => []).add(rep);
    }

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Accomplishment Reports', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
                    Text('Review, categorize, and approve accomplishment reports by organization.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButton<String?>(
                    value: _selectedOrgId,
                    hint: const Text('Filter by Organization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.business_rounded, color: Color(0xFF6366F1)),
                    onChanged: (val) => setState(() => _selectedOrgId = val),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Organizations', style: TextStyle(fontWeight: FontWeight.bold))),
                      ...widget.organizations.map((org) => DropdownMenuItem<String?>(
                        value: org['id'].toString(),
                        child: Text(org['name'] ?? 'Organization', style: const TextStyle(fontWeight: FontWeight.w600)),
                      )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF6366F1),
                ),
                dividerColor: Colors.transparent,
                onTap: (idx) {
                  setState(() {
                    _showApprovedFilter = (idx == 1);
                  });
                },

                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_late_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('Awaiting Approval ($awaitingCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.verified_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('Approved Reports ($approvedCount)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_showApprovedFilter && approvedCount > 0)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: _archiveAllApproved,
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: Text('Archive all approved ($approvedCount)'),
                  ),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : groupedReports.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8)),
                    SizedBox(height: 12),
                    Text('No accomplishment reports match the selected criteria.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: groupedReports.keys.length,
                itemBuilder: (context, groupIdx) {
                  final orgName = groupedReports.keys.elementAt(groupIdx);
                  final reportsList = groupedReports[orgName]!;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.business_rounded, color: Color(0xFF6366F1), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(orgName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(12)),
                                child: Text('${reportsList.length} Reports', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: reportsList.map((rep) {
                              final act = rep['activities'] as Map<String, dynamic>? ?? {};
                              final actTitle = (rep['title'] ?? act['title'] ?? 'Accomplishment Report').toString();
                              final status = (rep['status'] ?? 'Pending').toString();
                              final statusLower = status.toLowerCase();
                              final isApproved = ['approved', 'completed', 'verified', 'passed'].contains(statusLower);
                              final displayStatus = isApproved ? 'Approved' : (statusLower.contains('revision') ? 'Needs Revision' : status);
                              final attachments = rep['attachments'] ?? rep['file_urls'] ?? rep['report_url'];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF5FF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.purple.shade100),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: const Color(0xFF0D9488).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                      child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF0D9488), size: 24),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(actTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F172A))),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Text('Status: ', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                              StatusBadge(status: displayStatus),
                                              const SizedBox(width: 12),
                                              if (rep['report_date'] != null)
                                                Text('Submitted: ${AppUtils.formatDateTime(rep['report_date'])}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Row(
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () => _viewReport(attachments),
                                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                          label: const Text('View File'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF6366F1),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 0,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (!isApproved) ...[
                                          ElevatedButton.icon(
                                            onPressed: () => _approveReport(context, rep, act['id']),
                                            icon: const Icon(Icons.check_circle_rounded, size: 16),
                                            label: const Text('Approve'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF10B981),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              elevation: 0,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        if (isApproved) IconButton(
                                          tooltip: 'Archive report',
                                          icon: const Icon(Icons.archive_outlined, color: Color(0xFF64748B)),
                                          onPressed: () => _setReportArchived(context, rep['id'], true),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
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
      ),
    );
  }
  Future<void> _archiveAllApproved() async {
    final ids = _reportsList.where((rep) {
      if (rep['is_archived'] == true) return false;
      final act = rep['activities'] as Map<String, dynamic>? ?? {};
      final orgId = rep['organization_id']?.toString() ?? act['organization_id']?.toString() ?? 'unknown';
      if (_selectedOrgId != null && orgId != _selectedOrgId) return false;
      return ['approved', 'completed', 'verified', 'passed'].contains((rep['status'] ?? '').toString().toLowerCase());
    }).map((r) => r['id']).toList();
    if (ids.isEmpty) return;
    final ok = await _confirmBulk(context, 'Archive all ${ids.length} approved reports?', 'They will move to Archives. You can restore them there.', 'Archive all');
    if (!mounted || !ok) return;
    try {
      await _setArchived('accomplishment_reports', ids, true);
      if (!mounted) return;
      AppUtils.showTopToast(context, '${ids.length} reports archived.');
      await _fetchReports();
      widget.onRefresh();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not archive: $e', isError: true);
    }
  }
  Future<void> _setReportArchived(BuildContext context, dynamic reportId, bool archived) async {
    try {
      await UserArchive.setArchived('report', [reportId], archived);
      if (context.mounted) {
        AppUtils.showTopToast(context, archived ? 'Report archived.' : 'Report restored.');
        await _fetchReports(); // reload so the archived report disappears right away
        widget.onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Could not update archive: $e', isError: true);
    }
  }

  Future<void> _viewReport(dynamic attachments) async {
    String? url;
    if (attachments is List && attachments.isNotEmpty) {
      url = attachments.first.toString();
    } else if (attachments is String) {
      url = attachments;
    }
    if (url == null || url.isEmpty) return;

    final ok = await StorageUtils.open(url);
    if (!ok && mounted) AppUtils.showTopToast(context, 'Could not open the file.', isError: true);
  }

  Future<void> _approveReport(BuildContext context, Map<String, dynamic> rep, dynamic activityId) async {
    final reportId = rep['id']?.toString();
    final actId = (activityId ?? rep['activity_id'])?.toString();
    final act = rep['activities'] as Map<String, dynamic>? ?? {};
    final actTitle = (rep['title'] ?? act['title'] ?? 'Activity').toString();
    final orgId = rep['organization_id'] ?? act['organization_id'];

    try {
      final client = Supabase.instance.client;

      // 1. Try status values in loop to handle check constraint
      bool updated = false;
      if (reportId != null && reportId.isNotEmpty) {
        for (final val in ['Approved', 'approved', 'Completed', 'Verified']) {
          try {
            await client
                .from('accomplishment_reports')
                .update({'status': val})
                .eq('id', reportId);
            updated = true;
            break;
          } catch (_) {}
        }
      }
      if (!updated) throw Exception('Could not update report status.');

      // 2. Update associated activity status in activities table
      if (actId != null && actId.isNotEmpty) {
        for (var actStatusVal in ['Completed', 'COMPLETED', 'Approved']) {
          try {
            await client
                .from('activities')
                .update({'status': actStatusVal})
                .eq('id', actId);
            break;
          } catch (_) {}
        }
      }

      // 3. Insert real-time notification into Supabase 'notifications' table for President & Adviser
      AppUtils.sendNotification(
        title: 'Accomplishment Report Approved 🎉',
        body: 'The accomplishment report for "$actTitle" has been approved by OSDW Admin!',
        recipientRole: 'president',
        organizationId: orgId?.toString(),
      );
      AppUtils.sendNotification(
        title: 'Accomplishment Report Approved 🎉',
        body: 'The accomplishment report for "$actTitle" has been approved by OSDW Admin!',
        recipientRole: 'adviser',
        organizationId: orgId?.toString(),
      );

      // 4. Update local in-memory model and trigger UI refresh
      setState(() {
        rep['status'] = 'Approved';
      });

      widget.onRefresh();

      if (context.mounted) {
        AppUtils.showTopToast(context, 'Accomplishment Report approved successfully!');
      }
    } catch (e) {
      if (context.mounted) {
        AppUtils.showTopToast(context, 'Error approving report: $e', isError: true);
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
  String _schoolYear = '2025-2026';
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
    final keys = _isSpec
        ? ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii']
        : _controllers.keys.toList();
    double total = 0;
    for (final k in keys) {
      total += double.tryParse(_controllers[k]?.text ?? '') ?? 0;
    }
    return total;
  }
  String get adjectivalRating => getAdjectivalRating(grandTotal);

  @override
  void initState() {
    super.initState();
    SchoolYearService.current().then((sy) {
      if (mounted) setState(() => _schoolYear = sy);
    });
    _initLevelGridControllers();
    for (var controller in _controllers.values) {
      controller.addListener(() { if (mounted) setState(() {}); });
    }
  }

  void _initLevelGridControllers() {
    final levels = ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];
    final itemMaxes = {'i': 7, 'ii': 10, 'iii': 10, 'iv': 10, 'v': 10, 'vi': 5};

    itemMaxes.forEach((item, maxActs) {
      for (int act = 1; act <= maxActs; act++) {
        for (final lvl in levels) {
          _levelGridControllers['${item}_${act}_${lvl}_sdg'] ??= TextEditingController();
          _levelGridControllers['${item}_${act}_${lvl}_pts'] ??= TextEditingController();
          _levelGridControllers['${item}_${act}_$lvl'] ??= TextEditingController();
        }
      }
    });
    _resetNotedDefaults();
  }

  static const Map<String, String> _notedDefaults = {
    'noted_name': 'LORAINE SUYU-TATTAO, Ph.D.',
    'noted_title': 'University Director',
    'noted_office': 'Office of the Student Services and Welfare',
  };

  void _resetNotedDefaults() {
    _notedDefaults.forEach((k, v) {
      (_levelGridControllers[k] ??= TextEditingController()).text = v;
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

  bool get _isSpec => (_selectedOrgType ?? '').toLowerCase().contains('special');
  bool get _isCampusType => (_selectedOrgType ?? '').toLowerCase().contains('campus');

  Map<String, int> get _itemMaxActs => _isSpec
      ? {'i': 7, 'ii': 10, 'iii': 10, 'iv': 5}
      : {'i': 4, 'ii': 4, 'iii': 5, 'iv': 10, 'v': _isCampusType ? 5 : 10, 'vi': 5};

  double _itemMaxPoints(String key) {
    if (_isSpec) return key == 'i' ? 20.0 : (key == 'ii' ? 30.0 : 10.0);
    return key == 'iii' ? 5.0 : 10.0;
  }

  List<String> get _activeLevels => _isCampusType
      ? ['intl', 'natl', 'regl', 'univ', 'camp']
      : ['intl', 'natl', 'regl', 'univ', 'camp', 'coll'];

  void _selectAll(TextEditingController? c) {
    if (c == null) return;
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }
  double _cellMax(String key, String lvl) => (key == 'i' || key == 'ii')
      ? calculateSDGPoints(lvl, 99, _selectedOrgType)
      : getCategoricalLevelUnitPoints(lvl, _selectedOrgType);

  void _onGridInputChanged(String key, int act, String lvl, int maxActs) {
    final limit = _itemMaxActs[key] ?? maxActs;

    int totalActiveSlots = 0;
    for (int a = 1; a <= maxActs; a++) {
      for (final l in _activeLevels) {
        final pVal = double.tryParse(_levelGridControllers['${key}_${a}_${l}_pts']?.text.trim() ?? '');
        final vVal = double.tryParse(_levelGridControllers['${key}_${a}_$l']?.text.trim() ?? '');
        final sVal = int.tryParse(_levelGridControllers['${key}_${a}_${l}_sdg']?.text.trim() ?? '');
        if ((pVal != null && pVal > 0) || (vVal != null && vVal > 0) || (sVal != null && sVal > 0)) {
          totalActiveSlots++;
        }
      }
    }

    if (totalActiveSlots > limit) {
      _levelGridControllers['${key}_${act}_${lvl}_pts']?.clear();
      _levelGridControllers['${key}_${act}_$lvl']?.clear();
      _levelGridControllers['${key}_${act}_${lvl}_sdg']?.clear();
      _recalculateItemFromGrid(key);
      setState(() {});
      AppUtils.showTopToast(context, 'Maximum limit of $limit activities reached for this category.', isError: true);
      return;
    }

    _recalculateItemFromGrid(key);
  }

  void _recalculateItemFromGrid(String key) {
    final maxActs = _itemMaxActs[key];
    if (maxActs == null) return;

    double total = 0;
    for (int act = 1; act <= maxActs; act++) {
      for (final lvl in _activeLevels) {
        final ptsController = _levelGridControllers['${key}_${act}_${lvl}_pts'];
        final lvlController = _levelGridControllers['${key}_${act}_$lvl'];
        final sdgController = _levelGridControllers['${key}_${act}_${lvl}_sdg'];

        final ptsVal = double.tryParse(ptsController?.text ?? '') ??
            double.tryParse(lvlController?.text ?? '');
        final sdgVal = int.tryParse(sdgController?.text ?? '');
        final cellMax = _cellMax(key, lvl);

        if (ptsVal != null && ptsVal > 0) {
          total += ptsVal > cellMax ? cellMax : ptsVal;
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

    final maxAllowed = _itemMaxPoints(key);
    if (total > maxAllowed) total = maxAllowed;
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

      if (!mounted) return;

      for (var c in _levelGridControllers.values) {
        c.clear();
      }
      _resetNotedDefaults();

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
          Text(
            'Select a classification to score, manage evaluations, or review sheets for SY $_schoolYear',
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
              ElevatedButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('Save to PDF'),
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

  Widget _buildFolioPage(int num, Widget content) => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'FormSans'),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'FormSans'),
      child: _folioPageBox(num, content),
    ),
  );
  Widget _folioPageBox(int num, Widget content) {
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
                      'Search for the Most Outstanding ${_selectedOrgType ?? 'College Student Council'} Organization SY $_schoolYear',
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

  static const String _sans = 'FormSans';
  static const String _serif = 'FormSerif';
  static const BorderSide _bs = BorderSide(color: Colors.black, width: 0.5);
  static const List<List<String>> _specAmountRows = [
    ['2,000 and below', '1.0'], ['2,001 – 3,000', '1.5'], ['3,001 – 4,000', '2.0'],
    ['4,001 – 5,000', '2.5'], ['5,001 – 6,000', '3.0'], ['6,001 – 7,000', '3.5'],
    ['7,001 – 8,000', '4.0'], ['8,001 – 9,000', '4.5'], ['9,001 – 10,000', '5.0'],
    ['10,001 – 11,000', '5.5'], ['11,001 – 12,000', '6.0'], ['12,001 – 13,000', '6.5'],
    ['13,001 – 14,000', '7.0'], ['14,001 – 15,000', '7.5'], ['15,001 – 16,000', '8.0'],
    ['16,001 – 17,000', '8.5'], ['17,001 – 18,000', '9.0'], ['18,001 – 19,000', '9.5'],
    ['19,001 – above', '10.0'],
  ];
  static const String _docsSeminar =
      '• Approved letter\n• Program\n• Sample Certificate\n• Attendance Sheet\n• Documentation\n• Narrative Report\n• Evaluation Result\n• Concept Paper';

  TextStyle _g(double size, {FontWeight w = FontWeight.normal, FontStyle s = FontStyle.normal}) =>
      TextStyle(fontFamily: _sans, fontSize: size, fontWeight: w, fontStyle: s, color: Colors.black, height: 1.15);

  String get _profileKey {
    final t = (_selectedOrgType ?? '').toLowerCase();
    if (t.contains('special')) return 'spec';
    if (t.contains('campus')) return 'campus';
    return 'college';
  }

  Widget _cellBox({required Widget child, double? width, double? height,
    EdgeInsets padding = EdgeInsets.zero}) =>
      Container(
        width: width, height: height, padding: padding, alignment: Alignment.center,
        decoration: const BoxDecoration(border: Border(right: _bs, bottom: _bs)),
        child: child,
      );

  List<TextSpan> _digitSpans(String s) {
    final out = <TextSpan>[];
    s.splitMapJoin(RegExp(r'\d+'),
        onMatch: (m) { out.add(TextSpan(text: m[0], style: _g(8.5, w: FontWeight.bold))); return ''; },
        onNonMatch: (t) { if (t.isNotEmpty) out.add(TextSpan(text: t, style: _g(8.5))); return ''; });
    return out;
  }

  Widget _buildFolioHeader() {
    final typeLower = (_selectedOrgType ?? '').toLowerCase();
    final isCampus = typeLower.contains('campus');
    final isSpecialized = typeLower.contains('specialized') || typeLower.contains('special');

    final campusHeader = isSpecialized ? 'ANDREWS CAMPUS' : (isCampus ? 'Central Administration' : 'LAL-LO CAMPUS');
    final locationHeader = isSpecialized || isCampus ? 'Caritan, Tuguegarao City, Cagayan' : 'Sta. Maria, Lal-lo, Cagayan';
    final emailHeader = isSpecialized || isCampus ? 'osdw@csu.edu.ph' : 'osdw.lallo@csu.edu.ph';
    final fbHeader = isSpecialized ? 'Ossw Andrews' : (isCampus ? 'CSU Office of Student Development & Welfare' : 'Osdw Lallo');

    const red = Color(0xFFB71C1C);
    TextStyle s(double z, {bool b = false, bool i = false, bool u = false}) => TextStyle(
      fontFamily: _serif, fontSize: z, color: red,
      fontWeight: b ? FontWeight.bold : FontWeight.normal,
      fontStyle: i ? FontStyle.italic : FontStyle.normal,
      decoration: u ? TextDecoration.underline : TextDecoration.none,
      decorationColor: red,
    );

    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('REPUBLIC OF THE PHILIPPINES', style: s(10)),
          Text('CAGAYAN STATE UNIVERSITY', style: s(12, b: true)),
          Text(campusHeader, style: s(10)),
          Text(locationHeader, style: s(10, i: true)),
        ]),
        Expanded(
          child: Center(
            child: Image.asset('assets/images/csulogo.png', height: 60,
                errorBuilder: (c, e, st) => const Icon(Icons.school, size: 60, color: red)),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          RichText(text: TextSpan(children: [
            TextSpan(text: 'Email Address: ', style: s(9.5, i: true)),
            TextSpan(text: emailHeader, style: s(9.5, i: true, u: true)),
          ])),
          RichText(text: TextSpan(children: [
            TextSpan(text: 'Website: ', style: s(9.5, i: true)),
            TextSpan(text: 'www.csu.edu.ph', style: s(9.5, i: true, u: true)),
          ])),
          Text('Facebook Page: $fbHeader', style: s(9.5, i: true)),
        ]),
      ]),
      const SizedBox(height: 10),
      const Text('OFFICE OF STUDENT DEVELOPMENT AND WELFARE',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: _serif, fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black)),
      const SizedBox(height: 6),
      const Divider(color: Colors.black, thickness: 1.5, height: 1),
    ]);
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
              'CRITERIA FOR THE SEARCH FOR OUTSTANDING SPECIALIZED ORGANIZATION SY $_schoolYear',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
            'CRITERIA FOR THE SEARCH FOR OUTSTANDING ${(_selectedOrgType ?? 'COLLEGE STUDENT COUNCIL').toUpperCase()} SY $_schoolYear',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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

  Widget _buildSpecializedPage1Matrix() => Column(children: [
    _buildSdgLegend(),
    _buildActivityCategoryTable(
        title: 'I. Symposium/ Seminars Conducted (20 points)\nMax. No. of Activities: 7',
        docs: _docsSeminar, key: 'i', maxActs: 7, isSDGMatrix: true),
    _buildActivityCategoryTable(
        title: 'II. Activities Conducted/ Sponsored in line with the nature of the organization (30 points)\nMax. No. of Activities: 10',
        docs: _docsSeminar, key: 'ii', maxActs: 10, isSDGMatrix: true),
  ]);
  Widget _buildInfoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 2),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black))),
              child: Text(value, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage1Matrix() => Column(children: [
    _buildSdgLegend(),
    _buildActivityCategoryTable(
        title: 'I. Symposium/ Seminars Conducted (10 points)\nMax. No. of Activities: 4',
        docs: _docsSeminar, key: 'i', maxActs: 4, isSDGMatrix: true),
    _buildActivityCategoryTable(
        title: 'II. Convocations/ Programs and Literary Activities (10 points)\nMax. No. of Activities: 4',
        docs: _docsSeminar, key: 'ii', maxActs: 4, isSDGMatrix: true),
  ]);

  Widget _buildSdgLegend() {
    final profile = _profileKey;
    final tiers = kSdgTiers[profile]!;
    final n = profile == 'campus' ? 5 : 6;
    var maxRows = 0;
    for (var i = 0; i < n; i++) {
      if (tiers[i].length > maxRows) maxRows = tiers[i].length;
    }
    final noteStart = maxRows > 3 ? 3 : maxRows - 1;
    const h1 = 64.0, h2 = 46.0, rh = 28.0;
    final topH = h1 + h2 + noteStart * rh;

    Widget split(double h, Widget a, Widget b) => Row(children: [
      Expanded(child: _cellBox(height: h, child: a)),
      Expanded(child: _cellBox(height: h, child: b)),
    ]);

    return Container(
      decoration: const BoxDecoration(border: Border(left: _bs, top: _bs)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 250,
          child: Column(children: [
            Row(children: [
              _cellBox(width: 125, height: topH, child: Text('Activities', style: _g(13, w: FontWeight.bold))),
              _cellBox(width: 125, height: topH,
                  child: Text('Supporting\nDocuments', textAlign: TextAlign.center, style: _g(13, w: FontWeight.bold))),
            ]),
            _cellBox(
              width: 250, height: (maxRows - noteStart) * rh, padding: const EdgeInsets.all(4),
              child: Text('Attendance should be 50%+1 of the total target participants.',
                  textAlign: TextAlign.center, style: _g(8, s: FontStyle.italic)),
            ),
          ]),
        ),
        for (var i = 0; i < n; i++)
          Expanded(
            child: Column(children: [
              _cellBox(
                height: h1, padding: const EdgeInsets.all(3),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(kLevelTitles[i], textAlign: TextAlign.center, style: _g(10, w: FontWeight.bold)),
                  if (i == 0) Text(kIntlNote, textAlign: TextAlign.center, style: _g(7.5, s: FontStyle.italic)),
                ]),
              ),
              split(h2,
                  Text('No.\nof\nSDGs', textAlign: TextAlign.center, style: _g(8.5)),
                  Text('Pts', style: _g(9.5, w: FontWeight.bold))),
              for (var r = 0; r < maxRows; r++)
                r < tiers[i].length
                    ? split(rh,
                    Text(formatTier(tiers[i][r][0]), style: _g(10)),
                    Text(formatTier(tiers[i][r][1]), style: _g(10, w: FontWeight.bold)))
                    : split(rh, const SizedBox(), const SizedBox()),
            ]),
          ),
      ]),
    );
  }

  Widget _buildCategoricalHeader() {
    final n = _profileKey == 'campus' ? 5 : 6;
    return Container(
      height: 78,
      decoration: const BoxDecoration(border: Border(left: _bs, top: _bs)),
      child: Row(children: [
        _cellBox(width: 125, child: Text('Activities', style: _g(13, w: FontWeight.bold))),
        _cellBox(width: 125,
            child: Text('Supporting\nDocuments', textAlign: TextAlign.center, style: _g(13, w: FontWeight.bold))),
        for (var i = 0; i < n; i++)
          Expanded(
            child: _cellBox(
              padding: const EdgeInsets.all(3),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(kLevelTitles[i], textAlign: TextAlign.center, style: _g(10, w: FontWeight.bold)),
                if (i == 0) Text(kIntlNote, textAlign: TextAlign.center, style: _g(7.5, s: FontStyle.italic)),
                const SizedBox(height: 2),
                Text(pointsLabel(getCategoricalLevelUnitPoints(kLevelKeys[i], _selectedOrgType)),
                    textAlign: TextAlign.center, style: _g(10, w: FontWeight.bold)),
              ]),
            ),
          ),
      ]),
    );
  }

  List<Widget> _categoryLeftCells(String title, String docs) {
    final lines = title.split('\n');
    final m = RegExp(r'^([IVX]+\.)\s*(.*?)\s*(\(\d+ points\))\s*$').firstMatch(lines.first);
    final parts = m == null ? [lines.first] : [m.group(1)!, m.group(2)!, m.group(3)!];
    final maxLine = lines.length > 1 ? lines.sublist(1).join(' ') : '';
    const pad = EdgeInsets.symmetric(horizontal: 6, vertical: 8);
    const deco = BoxDecoration(border: Border(right: _bs));
    return [
      SizedBox(
        width: 125,
        child: Container(
          padding: pad, decoration: deco,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final p in parts)
                Text(p, textAlign: TextAlign.center, style: _g(11.5, w: FontWeight.bold)),
              if (maxLine.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: RichText(textAlign: TextAlign.center, text: TextSpan(children: _digitSpans(maxLine))),
                ),
            ]),
          ),
        ),
      ),
      SizedBox(
        width: 125,
        child: Container(
          padding: pad, decoration: deco,
          child: Center(child: Text(docs, textAlign: TextAlign.left, style: _g(8.5))),
        ),
      ),
    ];
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
            ..._categoryLeftCells(title, docs),
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
                                          onTap: () => _selectAll(_levelGridControllers['${key}_${act}_${lvl}_sdg']),
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2), MaxDecimalFormatter(17, decimals: 0)],
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
                                        onTap: () => _selectAll(_levelGridControllers['${key}_${act}_${lvl}_pts']),
                                        textAlign: TextAlign.center,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [MaxDecimalFormatter(_cellMax(key, lvl))],
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
                                  onTap: () => _selectAll(_levelGridControllers['${key}_${act}_$lvl'] ?? _levelGridControllers['${key}_${act}_${lvl}_pts']),
                                  textAlign: TextAlign.center,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [MaxDecimalFormatter(_cellMax(key, lvl))],
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
    if (_isSpec) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoricalHeader(),
          _buildActivityCategoryTable(
            title: 'IV. Extension Services Sponsored/ Conducted (10 points)\nMax. No. of Activities: 5',
            docs: '• Approved letter\n• Office Order/ Special Order\n• MOA/MOU/ Resolution from the barangay/ Excerpts from the minutes of the meeting\n• Consent letter/Invitation Letter\n• Narrative report\n• Certificate signed by the partner agency/ organization/ institution\n• Attendance Sheet\n• Documentation',
            key: 'iv',
            maxActs: 5,
            isSDGMatrix: false,
          ),
          const SizedBox(height: 12),
          const Text('Note: For activities conducted with co-sponsor, the points will be divided equally. Any Regional Activity conducted should have CHED Endorsement.', style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic)),
          const SizedBox(height: 24),
          const Text('V. Tangible/ Physical Projects (10 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const Text('• Computation is accumulated amount. Consumables not included. Office equipment/equipment for the CSC use alone are not credited.', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const Text('• Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          _buildMappingTable(_specAmountRows.sublist(0, 14), headerLabel: 'Amount (Php)'),
        ],
      );
    }
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
    if (_isSpec) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMappingTable(_specAmountRows.sublist(14), headerLabel: 'Amount (Php)', scoreKey: 'v'),
          const SizedBox(height: 24),
          const Text('VI. Fund Drive/ IGP (10 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const Text('• Supporting Documents: Approved letter, Project Proposal/Concept Paper, Disbursement Voucher, Project Income Statement, receipts and photo Documentation', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          _buildMappingTable(_specAmountRows, headerLabel: 'Amount (Php)', scoreKey: 'vi'),
        ],
      );
    }
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
    if (_isSpec) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VII. Percentage of Implementation of the Approved Action Plan (10 points)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          const Text('• Supporting Documents: Copy of the approved Action Plan, Summary of Accomplishment Report', style: TextStyle(fontSize: 8.5, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          _buildMappingTable([
            ['94% - 100%', '10.0'], ['88% - 93%', '9.0'],
            ['82% - 87%', '8.0'], ['76% - 81%', '7.0'],
            ['70% - 75%', '6.0'], ['64% - 69%', '5.0'],
            ['58% - 63%', '4.0'], ['52% - 57%', '3.0'],
            ['46% - 51%', '2.0'], ['40% - 45%', '1.0'],
          ], headerLabel: 'Percentage of Implementation', scoreKey: 'vii'),
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
    if (_isSpec) {
      return Table(
        border: TableBorder.all(color: Colors.black, width: 1.5),
        columnWidths: const {0: FlexColumnWidth(4), 1: FixedColumnWidth(100)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade300),
            children: const [
              Padding(padding: EdgeInsets.all(8), child: Text('Sub Categories', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Score', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
            ],
          ),
          ...[
            ['I. Symposium/ Seminars Conducted (20 points)', 'i'],
            ['II. Activities Conducted/ Sponsored in line with the nature of the organization (30 points)', 'ii'],
            ['III. Maka-kalikasan/ Clean and Green Activities and Projects (10 points)', 'iii'],
            ['IV. Extension Services Sponsored/Conducted (10 points)', 'iv'],
            ['V. Tangible/ Physical Projects (10 points)', 'v'],
            ['VI. Fund Drive/ IGP (10 points)', 'vi'],
            ['VII. Percentage of Implementation of the Approved Action Plan (10 points)', 'vii'],
          ].map((s) => TableRow(children: [
            Padding(padding: const EdgeInsets.all(8), child: Text(s[0], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
            TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: _buildIntegratedInput(s[1])),
          ])),
        ],
      );
    }
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

  Widget _notedField(String key, TextStyle style, {String hint = ''}) {
    return SizedBox(
      width: 460,
      child: TextField(
        controller: _levelGridControllers[key],
        style: style,
        onTap: () => _selectAll(_levelGridControllers[key]),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(vertical: 3),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF6366F1), width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildNotedBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _notedField(
          'noted_name',
          const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, decoration: TextDecoration.underline, letterSpacing: 0.5, color: Colors.black),
          hint: 'Name',
        ),
        const SizedBox(height: 2),
        _notedField('noted_title', const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black), hint: 'Position'),
        _notedField('noted_office', const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black), hint: 'Office'),
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
    final controller = _controllers[key]!;

    return Container(
      height: 40,
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [MaxDecimalFormatter(maxScore)],
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6366F1)),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
        onTap: () {
          // select the whole value so typing replaces the 0
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        },
        onChanged: (_) {
          if (mounted) setState(() {});
        },
      ),
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

class _RankCategory {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _RankCategory(this.key, this.label, this.icon, this.color);
}

class _RankingsView extends StatefulWidget {
  final List<Map<String, dynamic>> organizations;
  const _RankingsView({required this.organizations});

  @override
  State<_RankingsView> createState() => _RankingsViewState();
}

class _RankingsViewState extends State<_RankingsView> {
  String _schoolYear = '2025-2026';
  String _filter = 'all'; // all | campus | college | specialized
  List<Map<String, dynamic>> _evaluations = [];
  bool _isLoading = true;

  static const _ink = Color(0xFF1E293B);
  static const _muted = Color(0xFF64748B);
  static const _gold = Color(0xFFB45309);

  static const List<_RankCategory> _categories = [
    _RankCategory('campus', 'Campus Student Council', Icons.domain_rounded, Color(0xFF0F766E)),
    _RankCategory('college', 'College Student Council', Icons.account_balance_rounded, Color(0xFF4338CA)),
    _RankCategory('specialized', 'Specialized Organization', Icons.stars_rounded, Color(0xFFB45309)),
  ];

  @override
  void initState() {
    super.initState();
    SchoolYearService.current().then((sy) {
      if (!mounted) return;
      setState(() => _schoolYear = sy);
      _fetchRankings();
    });
  }

  List<String> get _years =>
      {'2024-2025', '2025-2026', '2026-2027', _schoolYear}.toList()..sort();
  Future<void> _fetchRankings() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('organization_evaluations')
          .select('*, organizations(name, type)')
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

  String? _categoryOf(Map<String, dynamic> eval) {
    final type = (eval['organizations']?['type'] ?? '').toString().toLowerCase();
    if (type.contains('campus')) return 'campus';
    if (type.contains('college')) return 'college';
    if (type.contains('special')) return 'specialized';
    return null;
  }

  double _scoreOf(Map<String, dynamic> eval) => (eval['grand_total'] as num?)?.toDouble() ?? 0.0;

  String _ratingOf(Map<String, dynamic> eval) {
    final raw = (eval['adjectival_rating'] ?? 'N/A').toString();
    return raw.contains('|') ? raw.split('|').first : raw;
  }

  @override
  Widget build(BuildContext context) {
    // Group the evaluations by category and sort each group by score.
    final grouped = {for (final c in _categories) c.key: <Map<String, dynamic>>[]};
    for (final e in _evaluations) {
      final key = _categoryOf(e);
      if (key != null) grouped[key]!.add(e);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => _scoreOf(b).compareTo(_scoreOf(a)));
    }

    final visible = _categories.where((c) => _filter == 'all' || _filter == c.key).toList();

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Leaderboard & Rankings', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -1)),
                    Text('Top performing organizations per category based on annual evaluations.', style: TextStyle(color: _muted, fontSize: 16)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
                child: DropdownButton<String>(
                  value: _schoolYear,
                  underline: const SizedBox(),
                  items: _years.map((sy) => DropdownMenuItem(value: sy, child: Text('SY $sy'))).toList(),
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
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            children: [
              _filterChip('all', 'All Categories'),
              for (final c in _categories) _filterChip(c.key, c.label),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _evaluations.isEmpty
                ? const Center(child: Text('No evaluations found for this school year.'))
                : ListView(
              children: [
                for (final c in visible) _buildCategory(c, grouped[c.key]!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = key),
      selectedColor: const Color(0xFF4338CA),
      labelStyle: TextStyle(color: selected ? Colors.white : _ink, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildCategory(_RankCategory cat, List<Map<String, dynamic>> list) {
    // Competition ranking: equal scores share the same rank.
    int rankOf(Map<String, dynamic> e) => 1 + list.where((o) => _scoreOf(o) > _scoreOf(e)).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: Icon(cat.icon, color: cat.color, size: 24),
            ),
            const SizedBox(width: 14),
            Text(cat.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cat.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: Text('${list.length} ranked', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cat.color)),
            ),
          ]),
          const SizedBox(height: 20),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No evaluations yet for this category.', style: TextStyle(color: _muted))),
            )
          else
            for (final e in list) _buildRankRow(e, rankOf(e), cat),
        ],
      ),
    );
  }

  Widget _buildRankRow(Map<String, dynamic> eval, int rank, _RankCategory cat) {
    final isTop = rank == 1;
    final orgName = (eval['organizations']?['name'] ?? 'Unknown Org').toString();
    final total = _scoreOf(eval);
    final rating = _ratingOf(eval);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isTop ? 24 : 18),
      decoration: BoxDecoration(
        color: isTop ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isTop ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0), width: isTop ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: isTop ? 56 : 44,
            height: isTop ? 56 : 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isTop ? _gold.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: isTop
                ? const Icon(Icons.emoji_events_rounded, color: _gold, size: 30)
                : Text('$rank', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _muted)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isTop)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: _gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: Text('TOP 1 · ${cat.label.toUpperCase()}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _gold, letterSpacing: 0.6)),
                  ),
                Text(orgName.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: isTop ? 18 : 15, color: _ink)),
                const SizedBox(height: 2),
                Text(rating, style: TextStyle(fontSize: 12.5, color: cat.color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TOTAL SCORE', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w800)),
              Text(total.toStringAsFixed(2), style: TextStyle(fontSize: isTop ? 28 : 22, fontWeight: FontWeight.w800, color: isTop ? _gold : const Color(0xFF0F172A))),
            ],
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


    final president = widget.profiles.firstWhere(
          (p) => p['organization_id']?.toString() == orgId && p['role'] == 'President',
      orElse: () => <String, dynamic>{},
    );
    final adviser = widget.profiles.firstWhere(
          (p) => p['organization_id']?.toString() == orgId && p['role'] == 'Adviser',
      orElse: () => <String, dynamic>{},
    );


    final presidentName = president.isNotEmpty ? (president['full_name'] ?? 'Not Assigned').toString() : 'Not Assigned';
    final adviserName = adviser.isNotEmpty ? (adviser['full_name'] ?? 'Not Assigned').toString() : 'Not Assigned';

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
              _AdminOrgDetailItem(label: 'Adviser', value: adviserName, icon: Icons.person_outline),
              _AdminOrgDetailItem(label: 'President', value: presidentName, icon: Icons.person),
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
// ════════════════════════════════════════════════════════════════════════════
//  ACTIVITY PLAN REPORTS  (GPOA progress per organization)
// ════════════════════════════════════════════════════════════════════════════

class _PlanStats {
  final Map<String, dynamic> org;
  final List<Map<String, dynamic>> events; // approved GPOA events of this organization
  final int completed;
  final int notScheduled;
  const _PlanStats({
    required this.org,
    required this.events,
    required this.completed,
    required this.notScheduled,
  });

  int get total => events.length;
  int get percent => total == 0 ? 0 : ((completed / total) * 100).round();
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

  // Every event that is part of an organization's approved GPOA.
  static const _inGpoa = ['Approved', 'Awaiting Date Approval', 'Reschedule', 'Scheduled', 'Completed'];
  // Approved events that still have no confirmed date.
  static const _notScheduled = ['Approved', 'Awaiting Date Approval', 'Reschedule'];

  // Column widths, shared by the header, the rows and the totals so everything lines up.
  static const _wName = 4, _wDone = 3, _wTotal = 3, _wPending = 3, _wPercent = 3, _wAction = 4;

  // Soft, professional palette: deep tones on light backgrounds keep good
  // contrast (WCAG AA) without the glare of bright pure colors.
  static const _ink = Color(0xFF1E293B); // slate 800: main text
  static const _muted = Color(0xFF64748B); // slate 500: secondary text
  static const _line = UiColors.border;
  static const _green = Color(0xFF047857); // deep emerald: completed
  static const _amber = Color(0xFFB45309); // burnt amber: pending / warning
  static const _red = Color(0xFFB91C1C); // muted crimson: low progress
  static const _indigo = UiColors.primary;

  @override
  Widget build(BuildContext context) {
    final rows = organizations.map((org) {
      final orgId = org['id'].toString();
      final events = activities
          .where((a) =>
      a['is_archived'] != true &&
          a['organization_id']?.toString() == orgId &&
          _inGpoa.contains(a['status']))
          .toList();
      return _PlanStats(
        org: org,
        events: events,
        completed: events.where((a) => a['status'] == 'Completed').length,
        notScheduled: events.where((a) => _notScheduled.contains(a['status'])).length,
      );
    }).toList()
      ..sort((a, b) => (a.org['name'] ?? '').toString().toLowerCase().compareTo((b.org['name'] ?? '').toString().toLowerCase()));

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Activity Plan Reports', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          const Text("Progress of each organization's approved General Plan of Activities (GPOA).", style: TextStyle(fontSize: 18, color: _muted)),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: LayoutBuilder(builder: (context, box) {
                final width = box.maxWidth < 1060 ? 1060.0 : box.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, child: _table(context, rows)),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<_PlanStats> rows) {
    // Overall totals across all organizations.
    final totalDone = rows.fold<int>(0, (sum, r) => sum + r.completed);
    final totalAll = rows.fold<int>(0, (sum, r) => sum + r.total);
    final totalNotDone = totalAll - totalDone;
    final totalPercent = totalAll == 0 ? 0 : ((totalDone / totalAll) * 100).round();
    final percentColor = totalPercent >= 75 ? _green : (totalPercent >= 40 ? _amber : _red);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF1F5F9),
            child: Row(children: [
              _cell(_wName, _headerText('Organization', align: TextAlign.left), align: Alignment.centerLeft),
              _cell(_wDone, _headerText('Completed Events')),
              _cell(_wTotal, _headerText('Total GPOA Events')),
              _cell(_wPending, _headerText('Unscheduled Events')),
              _cell(_wPercent, _headerText('Completion Rate (%)')),
              _cell(_wAction, _headerText('Action')),
            ]),
          ),
          const Divider(height: 1, color: _line),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Text('No organizations found.', style: TextStyle(fontSize: 17, color: _muted)),
            )
          else
            for (final r in rows) ...[
              _row(context, r),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
            ],
          Container(
            decoration: const BoxDecoration(color: Color(0xFFF8FAFC), border: Border(top: BorderSide(color: _line))),
            child: Column(children: [
              _totalRow('Total GPOA Events :', '$totalAll', _ink),
              _totalRow('Total Completed Events :', '$totalDone', _green),
              _totalRow('Total Pending Events :', '$totalNotDone', _amber),
              _totalRow(
                'Overall Completion Rate :',
                totalAll == 0 ? '—' : '$totalPercent%',
                totalAll == 0 ? _muted : percentColor,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _PlanStats s) {
    final canPrint = s.total > 0;
    final name = (s.org['name'] ?? 'Unknown Org').toString();
    final type = (s.org['type'] ?? '').toString();

    return Row(children: [
      _cell(
        _wName,
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _indigo.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
            child: Text(_initials(name), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _indigo)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
                if (type.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(type, style: const TextStyle(fontSize: 13.5, color: _muted)),
                  ),
              ],
            ),
          ),
        ]),
        align: Alignment.centerLeft,
      ),
      _cell(_wDone, _pill(s.completed, _green)),
      _cell(_wTotal, _pill(s.total, _ink)),
      _cell(_wPending, _pill(s.notScheduled, s.notScheduled > 0 ? _amber : _muted)),
      _cell(_wPercent, _percentBar(s)),
      _cell(
        _wAction,
        Tooltip(
          message: canPrint ? 'Open the printable GPOA' : 'No approved events to print yet',
          child: ElevatedButton.icon(
            onPressed: canPrint ? () => _printGPOA(context, s) : null,
            icon: const Icon(Icons.print_rounded, size: 20),
            label: const Text('Print GPOA', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _indigo,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF94A3B8),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    ]);
  }

  // value is a String so it can show plain numbers as well as percentages.
  Widget _totalRow(String label, String value, Color color) => Row(children: [
    _cell(
      _wName,
      Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink, letterSpacing: 0.3)),
      align: Alignment.centerLeft,
    ),
    _cell(_wDone, Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color))),
    const Spacer(flex: _wTotal + _wPending + _wPercent + _wAction),
  ]);

  Widget _cell(int flex, Widget child, {Alignment align = Alignment.center}) => Expanded(
    flex: flex,
    child: Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: child,
    ),
  );

  Widget _headerText(String text, {TextAlign align = TextAlign.center}) => Text(
    text,
    textAlign: align,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink, height: 1.3),
  );

  // Rounded number badge
  Widget _pill(int n, Color color) => Container(
    width: 64,
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
    child: Text('$n', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
  );

  Widget _percentBar(_PlanStats s) {
    if (s.total == 0) {
      return const Text('—', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _muted));
    }
    final color = s.percent >= 75 ? _green : (s.percent >= 40 ? _amber : _red);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${s.percent}%', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 8),
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: s.percent / 100,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final second = parts.length > 1 ? parts[1][0] : '';
    return (parts.first[0] + second).toUpperCase();
  }

  Future<void> _printGPOA(BuildContext context, _PlanStats s) async {
    final orgId = s.org['id'].toString();
    final president = profiles.firstWhere(
          (p) => p['organization_id']?.toString() == orgId && p['role'] == 'President',
      orElse: () => {'full_name': 'Not Assigned'},
    );
    final adviser = profiles.firstWhere(
          (p) => p['organization_id']?.toString() == orgId && p['role'] == 'Adviser',
      orElse: () => {'full_name': 'Not Assigned'},
    );

    await _openGPOAWithSignatories(
      context,
      org: s.org,
      acts: s.events,
      president: president,
      adviser: adviser,
      fileName: 'GPOA_${s.org['name']}.pdf',
    );
  }
}


class _ProfileView extends StatefulWidget {
  final VoidCallback onRefresh;
  const _ProfileView({required this.onRefresh});

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  final _supabase = Supabase.instance.client;
  String _schoolYear = SchoolYearService.fallback;
  Map<String, dynamic> _profile = {};
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sy = await SchoolYearService.current();
    Map<String, dynamic> p = {};
    try {
      final id = _supabase.auth.currentUser?.id;
      if (id != null) {
        p = await _supabase.from('profiles').select().eq('id', id).maybeSingle() ?? {};
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _schoolYear = sy;
      _profile = p;
    });
  }

  Future<bool> _confirmReset() async {
    final ctrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Reset all for new school year?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This will move everything for SY $_schoolYear to Archives and start '
                    'SY ${SchoolYearService.next(_schoolYear)} with a clean slate:'),
                const SizedBox(height: 10),
                const Text('• All GPOA proposals'),
                const Text('• All events and schedules'),
                const Text('• All accomplishment reports'),
                const Text('• All evaluation scores and rankings'),
                const SizedBox(height: 10),
                const Text('Nothing is deleted. You can still open and download everything from Archives.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  onChanged: (_) => setD(() {}),
                  decoration: const InputDecoration(labelText: 'Type RESET to confirm', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: ctrl.text.trim() == 'RESET' ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
              child: const Text('Reset All'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return res == true;
  }

  Future<void> _resetAll() async {
    if (!await _confirmReset() || !mounted) return;
    setState(() => _isResetting = true);
    try {
      final closing = _schoolYear;
      final next = SchoolYearService.next(closing);
      final client = _supabase;

      // 1. Scores and rankings
      await client
          .from('organization_evaluations')
          .update({'is_archived': true})
          .eq('school_year', closing);
      // 2. GPOA and events: shared flag, applies to ALL users
      await client.from('activities').update({'is_archived': true}).not('id', 'is', null);

      // 3. Accomplishment reports: shared flag, applies to ALL users
      await client.from('accomplishment_reports').update({'is_archived': true}).not('id', 'is', null);

      // 4. Unlock proposal submissions for ALL organizations for the new school year
      await client.from('organizations').update({'is_unlocked': true}).not('id', 'is', null);
      await OrgUnlockService.resetAll(); // drop stale local lock/unlock overrides

      // 5. Start the new school year (last, so a failed reset can simply be retried)
      await SchoolYearService.set(next);

      if (!mounted) return;
      setState(() => _schoolYear = next);
      AppUtils.showTopToast(context, 'Archived SY $closing. Everything is reset for SY $next.');
      widget.onRefresh();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not reset: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _restoreAll() async {
    final current = _schoolYear;
    final prev = SchoolYearService.previous(current);
    final ok = await _confirmBulk(
      context,
      'Undo the reset?',
      'This brings back SY $prev for ALL users: GPOA, events, accomplishment reports, scores and rankings.',
      'Restore',
    );
    if (!mounted || !ok) return;
    setState(() => _isResetting = true);
    try {
      final client = _supabase;

      // Scores and rankings of the previous year
      await client.from('organization_evaluations').update({'is_archived': false}).eq('school_year', prev);

      // GPOA, events and reports, for ALL users
      await client.from('activities').update({'is_archived': false}).not('id', 'is', null);
      await client.from('accomplishment_reports').update({'is_archived': false}).not('id', 'is', null);

      // The admin's own archive
      final acts = await client.from('activities').select('id');
      final actIds = (acts as List).map((a) => a['id']).toList();
      if (actIds.isNotEmpty) await UserArchive.setArchived('activity', actIds, false);
      final reps = await client.from('accomplishment_reports').select('id');
      final repIds = (reps as List).map((r) => r['id']).toList();
      if (repIds.isNotEmpty) await UserArchive.setArchived('report', repIds, false);

      // Back to the previous school year (last)
      await SchoolYearService.set(prev);

      if (!mounted) return;
      setState(() => _schoolYear = prev);
      AppUtils.showTopToast(context, 'Restored SY $prev for all users.');
      widget.onRefresh();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not restore: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final name = (_profile['full_name'] ?? 'Administrator').toString();
    final email = _supabase.auth.currentUser?.email ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profile', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -1)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF6366F1), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                        Text(email, style: const TextStyle(color: Color(0xFF64748B))),
                        const Text('Administrator', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('New School Year', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF991B1B))),
                    const SizedBox(height: 6),
                    Text(
                      'Current school year: SY $_schoolYear. Reset moves all GPOA, events, accomplishment reports '
                          'and evaluation scores to Archives and starts SY ${SchoolYearService.next(_schoolYear)} from zero.',
                      style: const TextStyle(color: Color(0xFF7F1D1D), fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isResetting ? null : _resetAll,
                      icon: _isResetting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Reset All (New School Year)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFDC2626)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isResetting ? null : _restoreAll,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Restore (Undo Reset)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFF4F46E5)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  List<Map<String, dynamic>> _archivedEvals = [];
  bool _isLoadingReports = true;
  List<String> get _years =>
      {'2024-2025', '2025-2026', '2026-2027', _schoolYear}.toList()..sort();
  @override
  void initState() {
    super.initState();
    UserArchive.changes.addListener(_fetchAccomplishmentReports);
    _fetchAccomplishmentReports();
  }

  @override
  void dispose() {
    UserArchive.changes.removeListener(_fetchAccomplishmentReports);
    super.dispose();
  }

  Future<void> _fetchAccomplishmentReports() async {
    try {
      final res = await Supabase.instance.client
          .from('accomplishment_reports')
          .select('*, activities(*)');
      final reps = await UserArchive.decorate(List<Map<String, dynamic>>.from(res), 'report');
      try {
        final evals = await Supabase.instance.client
            .from('organization_evaluations')
            .select('*, organizations(*)')
            .eq('is_archived', true);
        _archivedEvals = List<Map<String, dynamic>>.from(evals);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _accomplishmentReports = reps;
          _isLoadingReports = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingReports = false);
    }
  }
  Future<void> _restoreDocs(List<Map<String, dynamic>> docs) async {
    final actIds = <dynamic>{};
    final repIds = <dynamic>{};
    for (final d in docs) {
      if (d['type'] == 'Accomplishment Report') {
        if (d['report_id'] != null) repIds.add(d['report_id']);
      } else if (d['is_gpoa'] == true) {
        for (final a in (d['acts'] as List)) { actIds.add(a['id']); }
      } else if (d['act'] != null) {
        actIds.add(d['act']['id']);
      }
    }
    if (actIds.isEmpty && repIds.isEmpty) return;
    final ok = await _confirmBulk(context, docs.length == 1 ? 'Restore this item?' : 'Restore ${docs.length} items?', 'They will move back to their normal pages.', 'Restore');
    if (!mounted || !ok) return;
    try {
      await _setArchived('activities', actIds.toList(), false);
      await _setArchived('accomplishment_reports', repIds.toList(), false);
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Restored.');
      _fetchAccomplishmentReports();
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not restore: $e', isError: true);
    }
  }
  void _openGPOADialog(List<Map<String, dynamic>> acts, String orgName, String? orgId) {
    final org = widget.organizations?.firstWhere(
          (o) => o['id'].toString() == orgId?.toString(),
      orElse: () => {'id': orgId, 'name': orgName, 'type': 'College Student Council'},
    ) ?? {'id': orgId, 'name': orgName, 'type': 'College Student Council'};

    _openGPOAWithSignatories(
      context,
      org: org,
      acts: acts,
      president: const {'full_name': 'Student Leader'},
      adviser: const {'full_name': 'Faculty Adviser'},
      fileName: 'GPOA_${orgName.replaceAll(" ", "_")}.pdf',
    );
  }

  Future<void> _openEvaluationPreview(Map<String, dynamic> eval) async {
    final org = Map<String, dynamic>.from(eval['organizations'] ?? {});
    final scores = <String, double>{
      for (final k in ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x'])
        k: (eval['score_$k'] as num?)?.toDouble() ?? 0,
    };
    final raw = (eval['adjectival_rating'] ?? '').toString();
    final grid = <String, String>{};
    if (raw.contains('|')) {
      try {
        (jsonDecode(raw.substring(raw.indexOf('|') + 1)) as Map)
            .forEach((k, v) => grid[k.toString()] = v.toString());
      } catch (_) {}
    }
    await CSCEvaluationPdfGenerator.showPdfPreviewDialog(
      context,
      organization: org,
      schoolYear: eval['school_year'].toString(),
      scores: scores,
      gridValues: grid,
      grandTotal: (eval['grand_total'] as num?)?.toDouble() ?? 0,
      adjectivalRating: raw.contains('|') ? raw.split('|').first : raw,
      orgType: (org['type'] ?? 'College Student Council').toString(),
    );
  }

  void _openAccomplishmentReportDialog(BuildContext context, Map<String, dynamic> doc) {
    showDialog(
      context: context,
      builder: (ctx) => AccomplishmentReportDetailsDialog(report: doc),
    );
  }

  @override
  Widget build(BuildContext context) {
    const String orgNameFilter = '';
    final archivedDocs = <Map<String, dynamic>>[];
    final archivedActs = widget.activities.where((a) => a['is_archived'] == true).toList();

    String resolveOrgName(dynamic orgId, dynamic rawName) {
      if (orgId != null && widget.organizations != null) {
        final match = widget.organizations!.firstWhere(
              (o) => o['id'].toString() == orgId.toString(),
          orElse: () => {'name': ''},
        );
        if (match['name'] != null && match['name'].toString().isNotEmpty) {
          return match['name'].toString();
        }
      }
      if (rawName != null && rawName.toString().isNotEmpty && rawName.toString() != 'Organization') {
        return rawName.toString();
      }
      return 'Campus Student Council';
    }

    // 1. Process GPOAs - EXACTLY 1 GPOA ENTRY PER ORGANIZATION
    if (_selectedCategory == 'All' || _selectedCategory == 'GPOA') {
      final Map<String, List<Map<String, dynamic>>> orgActsMap = {};
      final Map<String, String> orgNamesMap = {};

      for (var act in archivedActs) {
        final orgId = act['organization_id']?.toString() ?? 'unknown';
        final orgName = resolveOrgName(orgId, act['organization_name'] ?? act['organization']?['name']);

        orgNamesMap[orgId] = orgName;
        orgActsMap.putIfAbsent(orgId, () => []).add(act);
      }

      orgActsMap.forEach((orgId, acts) {
        final orgName = orgNamesMap[orgId] ?? 'Campus Student Council';

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
    for (var act in archivedActs) {
      final actTitle = (act['title'] ?? 'Untitled Activity').toString();
      final orgName = resolveOrgName(act['organization_id'], act['organization_name'] ?? act['organization']?['name']);

      final query = _searchQuery.toLowerCase();
      if (query.isNotEmpty && !actTitle.toLowerCase().contains(query) && !orgName.toLowerCase().contains(query)) {
        continue;
      }

      if (act['letter_url'] != null && act['letter_url'].toString().isNotEmpty) {
        if (_selectedCategory == 'All' || _selectedCategory == 'Approved Letter') {
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

    // 2. Process ONLY Approved Accomplishment Reports from Supabase
    for (var rep in _accomplishmentReports) {
      final repStatusLower = (rep['status'] ?? '').toString().toLowerCase();
      final isReportApproved = ['approved', 'completed', 'verified', 'passed'].contains(repStatusLower);
      if (!isReportApproved || rep['is_archived'] != true) continue;

      final act = rep['activities'] ?? {};
      final actTitle = (rep['title'] ?? act['title'] ?? 'Activity Report').toString();
      final orgName = resolveOrgName(rep['organization_id'] ?? act['organization_id'], rep['organization_name'] ?? act['organization_name']);

      if (orgNameFilter.isNotEmpty && !orgName.toLowerCase().contains(orgNameFilter)) {
        continue;
      }

      final query = _searchQuery.toLowerCase();
      if (query.isNotEmpty && !actTitle.toLowerCase().contains(query) && !orgName.toLowerCase().contains(query)) {
        continue;
      }

      final rawUrls = rep['attachments'] ?? rep['file_urls'] ?? rep['report_url'] ?? rep['attachment_url'];
      String? fileUrl;
      if (rawUrls is List && rawUrls.isNotEmpty) {
        fileUrl = rawUrls.first.toString();
      } else if (rawUrls is String && rawUrls.isNotEmpty) {
        fileUrl = rawUrls;
      }

      if (_selectedCategory == 'All' || _selectedCategory == 'Accomplishment Report') {
        archivedDocs.add({
          'type': 'Accomplishment Report',
          'title': 'Accomplishment Report - $actTitle',
          'org_name': orgName,
          'date': rep['created_at']?.toString().split('T').first ?? 'SY $_schoolYear',
          'color': const Color(0xFF0D9488),
          'icon': Icons.assignment_turned_in_rounded,
          'file_url': fileUrl,
          'attachments': rep['attachments'],
          'summary': rep['summary'],
          'report_id': rep['id'],
          'act': act,
          'is_gpoa': false,
        });
      }
    }

    if (_selectedCategory == 'All' || _selectedCategory == 'Evaluation') {
      for (final e in _archivedEvals) {
        if (e['school_year']?.toString() != _schoolYear) continue;
        final orgName = (e['organizations']?['name'] ?? 'Organization').toString();
        final q = _searchQuery.toLowerCase();
        if (q.isNotEmpty && !orgName.toLowerCase().contains(q)) continue;
        final raw = (e['adjectival_rating'] ?? '').toString();
        final rating = raw.contains('|') ? raw.split('|').first : raw;
        archivedDocs.add({
          'type': 'Evaluation',
          'title': 'Evaluation Score - $orgName (${((e['grand_total'] as num?) ?? 0).toStringAsFixed(2)} pts, $rating)',
          'org_name': orgName,
          'date': 'SY ${e['school_year']}',
          'color': const Color(0xFFD97706),
          'icon': Icons.emoji_events_rounded,
          'eval': e,
          'is_gpoa': false,
        });
      }
    }

    // Group archived documents by Organization
    final Map<String, List<Map<String, dynamic>>> groupedDocs = {};

    for (var doc in archivedDocs) {
      final orgName = (doc['org_name'] ?? 'College Organization').toString();
      groupedDocs.putIfAbsent(orgName, () => []).add(doc);
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
                      Text('Centralized repository of GPOAs, Accomplishment Reports, and Approved Letters', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
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
                  items: _years.map((sy) => DropdownMenuItem(value: sy, child: Text('SY $sy'))).toList(),
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
                children: ['All', 'GPOA', 'Accomplishment Report', 'Approved Letter', 'Evaluation'].map((cat) {
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
          if (archivedDocs.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () => _restoreDocs(archivedDocs),
                  icon: const Icon(Icons.unarchive_outlined, size: 18),
                  label: Text('Restore all (${archivedDocs.length})'),
                ),
              ),
            ),
          Expanded(
            child: _isLoadingReports
                ? const Center(child: CircularProgressIndicator())
                : groupedDocs.isEmpty
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
              itemCount: groupedDocs.keys.length,
              itemBuilder: (ctx, groupIdx) {
                final orgName = groupedDocs.keys.elementAt(groupIdx);
                final docsList = groupedDocs[orgName]!;

                return Container(
                  margin: const EdgeInsets.only(bottom: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.business_rounded, color: Color(0xFF6366F1), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(orgName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(12)),
                              child: Text('${docsList.length} Documents', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: docsList.map((doc) {
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
                                  IconButton(
                                    tooltip: 'Restore (unarchive)',
                                    icon: const Icon(Icons.unarchive_outlined, color: Color(0xFF64748B)),
                                    onPressed: () => _restoreDocs([doc]),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      if (isGPOA && doc['acts'] != null) {
                                        final actsList = List<Map<String, dynamic>>.from(doc['acts'] as List);
                                        _openGPOADialog(actsList, doc['org_name'].toString(), doc['org_id']?.toString());
                                      } else if (doc['type'] == 'Evaluation') {
                                        _openEvaluationPreview(Map<String, dynamic>.from(doc['eval']));
                                      } else if (doc['type'] == 'Accomplishment Report') {
                                        _openAccomplishmentReportDialog(context, doc);
                                      } else if (doc['file_url'] != null && doc['file_url'].toString().isNotEmpty) {
                                        final ok = await StorageUtils.open(doc['file_url'].toString());
                                        if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the file.', isError: true);
                                      } else {
                                        AppUtils.showTopToast(context, 'Viewing ${doc['title']}...');
                                      }
                                    },
                                    icon: Icon(isGPOA ? Icons.picture_as_pdf_rounded : Icons.remove_red_eye_rounded, size: 16),
                                    label: Text(isGPOA ? 'Preview plan' : (doc['type'] == 'Evaluation' ? 'Preview PDF' : (doc['type'] == 'Accomplishment Report' ? 'View report' : 'Open file'))),
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
                          }).toList(),
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
class AccomplishmentReportDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> report;
  const AccomplishmentReportDetailsDialog({super.key, required this.report});

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg')) return Icons.image_rounded;
    if (n.endsWith('.doc') || n.endsWith('.docx')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Future<void> _open(BuildContext context, String url) async {
    final opened = await StorageUtils.open(url);
    if (!opened && context.mounted) {
      AppUtils.showTopToast(
        context,
        "We couldn't open this file. Check your internet connection and try again.",
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = report['title']?.toString() ?? 'Accomplishment report';
    final orgName = report['org_name']?.toString() ?? 'Organization';
    final date = report['date']?.toString() ?? '';
    final act = report['act'] as Map<String, dynamic>? ?? {};
    final summary = (report['summary'] ?? report['description'] ?? '').toString().trim();

    final files = <String>{};
    if (report['file_url'] != null && report['file_url'].toString().isNotEmpty) {
      files.add(report['file_url'].toString());
    }
    final raw = report['attachments'] ?? act['attachments'] ?? act['report_url'];
    if (raw is List) {
      files.addAll(raw.map((e) => e.toString()).where((e) => e.isNotEmpty));
    } else if (raw is String && raw.isNotEmpty) {
      files.add(raw);
    }

    return Dialog(
      backgroundColor: UiColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: UiColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_turned_in_rounded, color: UiColors.success, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: UiColors.text)),
                        const SizedBox(height: 2),
                        Text(date.isEmpty ? orgName : '$orgName · $date',
                            style: const TextStyle(fontSize: 13, color: UiColors.muted)),
                        const SizedBox(height: 8),
                        const StatusChip('Approved'),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: UiColors.muted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Panel(
                        title: 'Summary',
                        icon: Icons.notes_rounded,
                        child: Text(
                          summary.isEmpty ? 'No summary was written for this report.' : summary,
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: summary.isEmpty ? UiColors.muted : UiColors.text),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Panel(
                        title: 'Files (${files.length})',
                        icon: Icons.attach_file_rounded,
                        child: files.isEmpty
                            ? const EmptyState(
                            icon: Icons.folder_off_outlined,
                            title: 'No files attached',
                            message: 'The organization did not upload a file for this report.')
                            : Column(
                          children: files.map((url) {
                            final name = StorageUtils.fileName(url);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: UiColors.bg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(_iconFor(name), color: UiColors.primary, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => _open(context, url),
                                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                    label: const Text('Open'),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openGPOAWithSignatories(
    BuildContext context, {
      required Map<String, dynamic> org,
      required List<Map<String, dynamic>> acts,
      required Map<String, dynamic> president,
      required Map<String, dynamic> adviser,
      required String fileName,
    }) async {
  final orgId = org['id'].toString();
  final saved = await _loadSignatories(orgId);
  final initial = {...GPOAPdfGenerator.signatoryDefaults(president: president, adviser: adviser), ...saved};
  if (!context.mounted) return;

  final edited = await _showSignatoriesDialog(context, initial, president: president, adviser: adviser);
  if (edited == null || !context.mounted) return;
  await _saveSignatories(orgId, edited);
  if (!context.mounted) return;

  GPOAPdfGenerator.customSignatories = edited;

  showDialog(
    context: context,
    builder: (_) => GPOAPreviewDialog(
      organization: {...org, 'gpoa_signatories': edited},
      activities: acts,
      president: president,
      adviser: adviser,
      fileName: fileName,
    ),
  );
}

Future<Map<String, String>> _loadSignatories(String orgId) async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString('gpoa_sig_$orgId');
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return {};
  }
}

Future<void> _saveSignatories(String orgId, Map<String, String> v) async {
  try {
    await (await SharedPreferences.getInstance()).setString('gpoa_sig_$orgId', jsonEncode(v));
  } catch (_) {}
}

Future<Map<String, String>?> _showSignatoriesDialog(
    BuildContext context,
    Map<String, String> initial, {
      Map<String, dynamic>? president,
      Map<String, dynamic>? adviser,
    }) {
  const rows = [
    ('Prepared by', 'prepared'),
    ('Attested by', 'attested'),
    ('Noted by', 'noted'),
    ('Approved by', 'approved'),
  ];
  final ctrls = {
    for (final r in rows) ...{
      '${r.$2}_name': TextEditingController(text: initial['${r.$2}_name']),
      '${r.$2}_title': TextEditingController(text: initial['${r.$2}_title']),
    }
  };
  InputDecoration deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('GPOA signatories', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('These names and positions will appear on the printed GPOA.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              for (final r in rows) ...[
                const SizedBox(height: 18),
                Text('${r.$1}:', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: ctrls['${r.$2}_name'], decoration: deco('Full name', Icons.person_rounded))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: ctrls['${r.$2}_title'], decoration: deco('Position', Icons.badge_rounded))),
                ]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, GPOAPdfGenerator.signatoryDefaults(president: president, adviser: adviser)),
          child: const Text('Reset'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, {for (final e in ctrls.entries) e.key: e.value.text.trim()}),
          child: const Text('Continue to preview'),
        ),
      ],
    ),
  );
}

Future<void> adminResetPassword(String targetUserId, String newPassword) =>
    UserAdminService.resetPassword(targetUserId, newPassword);
String _fmt12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

Future<bool> _confirmBulk(BuildContext context, String title, String message, String action) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return res == true;
}

Future<void> _setArchived(String table, List<dynamic> ids, bool archived) async {
  if (ids.isEmpty) return;
  await UserArchive.setArchived(table == 'activities' ? 'activity' : 'report', ids, archived);
}
