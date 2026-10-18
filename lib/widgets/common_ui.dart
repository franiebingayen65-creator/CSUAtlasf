import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

const Color _kTeal = Color(0xFF1FB5AD);
const Color _kBellGrey = Color(0xFF8A9BAA);

class _CaretPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Color statusColorFor(String status) {
  switch (status) {
    case 'Approved':
    case 'Scheduled':
      return const Color(0xFF15803D);
    case 'Completed':
      return const Color(0xFF4338CA);
    case 'Pending':
      return const Color(0xFFB45309);
    case 'Endorsed':
      return const Color(0xFF0F766E);
    case 'Needs Revision':
      return const Color(0xFFC2410C);
    case 'Rejected':
      return const Color(0xFFB91C1C);
    case 'Awaiting Date Approval':
      return const Color(0xFF6D28D9);
    default:
      return const Color(0xFF64748B);
  }
}

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = statusColorFor(status);
    IconData icon = Icons.help_outline_rounded;

    switch (status) {
      case 'Approved':
      case 'Scheduled':
        icon = Icons.check_circle_rounded;
        break;
      case 'Completed':
        icon = Icons.task_alt_rounded;
        break;
      case 'Pending':
        icon = Icons.hourglass_empty_rounded;
        break;
      case 'Endorsed':
        icon = Icons.verified_rounded;
        break;
      case 'Needs Revision':
        icon = Icons.history_edu_rounded;
        break;
      case 'Rejected':
        icon = Icons.cancel_rounded;
        break;
      case 'Awaiting Date Approval':
        icon = Icons.calendar_month_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E293B).withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AlertBadge extends StatelessWidget {
  final String message;
  const AlertBadge({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 10),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFFB91C1C),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationInboxButton extends StatefulWidget {
  final Function(String page)? onNotificationTap;
  const NotificationInboxButton({super.key, this.onNotificationTap});

  @override
  State<NotificationInboxButton> createState() => _NotificationInboxButtonState();
}

class _NotifCategory {
  final String key; // users | reports | gpoa | events | scores | general
  final IconData icon;
  final Color color;
  const _NotifCategory(this.key, this.icon, this.color);
}

class _NotificationInboxButtonState extends State<NotificationInboxButton> {
  final _client = Supabase.instance.client;
  final GlobalKey _bellKey = GlobalKey();
  final ValueNotifier<List<Map<String, dynamic>>> _items = ValueNotifier([]);
  final List<StreamSubscription> _subs = [];
  List<Map<String, dynamic>> _orgRows = [];
  List<Map<String, dynamic>> _personalRows = [];
  List<Map<String, dynamic>> _raw = [];

  String? _userId;
  String _role = ''; // lowercase: admin | adviser | president
  String? _orgId;
  Set<String> _read = {};
  Set<String> _dismissed = {};

  bool get _isAdmin => _role == 'admin';
  String get _readKey => 'notif_read_$_userId';
  String get _dismissedKey => 'notif_dismissed_$_userId';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _items.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    _userId = user.id;

    try {
      final p = await _client
          .from('profiles')
          .select('role, organization_id')
          .eq('id', user.id)
          .maybeSingle();
      _role = (p?['role'] ?? '').toString().toLowerCase();
      _orgId = p?['organization_id']?.toString();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      _read = (prefs.getStringList(_readKey) ?? []).toSet();
      _dismissed = (prefs.getStringList(_dismissedKey) ?? []).toSet();
    } catch (_) {}

    if (!mounted) return;

    final notifs = _client.from('notifications');

    if (_isAdmin || _orgId == null) {
      _subs.add(notifs
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(300)
          .listen((d) {
        _orgRows = List<Map<String, dynamic>>.from(d);
        _merge();
      }, onError: (e) => debugPrint('Notifications stream error: $e')));
    } else {
      // Org-wide rows for my organization.
      _subs.add(notifs
          .stream(primaryKey: ['id'])
          .eq('organization_id', _orgId!)
          .order('created_at', ascending: false)
          .limit(100)
          .listen((d) {
        _orgRows = List<Map<String, dynamic>>.from(d);
        _merge();
      }, onError: (e) => debugPrint('Org stream error: $e')));

      // Rows sent directly to me, whatever their organization_id.
      _subs.add(notifs
          .stream(primaryKey: ['id'])
          .eq('recipient_id', _userId!)
          .order('created_at', ascending: false)
          .limit(100)
          .listen((d) {
        _personalRows = List<Map<String, dynamic>>.from(d);
        _merge();
      }, onError: (e) => debugPrint('Personal stream error: $e')));
    }
  }

  void _merge() {
    final byId = <String, Map<String, dynamic>>{};
    for (final r in [..._orgRows, ..._personalRows]) {
      byId[r['id'].toString()] = r;
    }
    _raw = byId.values.toList();
    _refilter();
  }

  // ── Who may see what ──────────────────────────────────────────────────────
  bool _visible(Map<String, dynamic> n) {
    final id = n['id']?.toString();
    if (id == null || _dismissed.contains(id)) return false;

    final status = (n['status'] ?? '').toString().toLowerCase();
    if (status == 'archived' || status == 'deleted') return false;

    // Sent to one specific person.
    final rid = n['recipient_id']?.toString() ?? '';
    if (rid.isNotEmpty) return rid == _userId;

    final role = (n['recipient_role'] ?? '').toString().toLowerCase();
    final org = n['organization_id']?.toString() ?? '';

    // Admin inbox: only admin / broadcast notifications.
    if (_isAdmin) return role == 'admin' || role == 'all';

    // Org inbox: must match my role AND my organization.
    if (role != _role && role != 'all') return false;
    return org.isNotEmpty && org == _orgId;
  }

  bool _isRead(Map<String, dynamic> n) {
    final id = n['id']?.toString() ?? '';
    final personal = (n['recipient_id']?.toString() ?? '') == _userId;
    return _read.contains(id) || (personal && n['read_at'] != null);
  }

  void _refilter() {
    final list = _raw.where(_visible).toList()
      ..sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    if (mounted) _items.value = list;
  }

  Future<void> _persist() async {
    try {
      // Drop ids of notifications that no longer exist so storage doesn't grow forever.
      if (_raw.isNotEmpty) {
        final live = _raw.map((n) => n['id'].toString()).toSet();
        _read.retainWhere(live.contains);
        _dismissed.retainWhere(live.contains);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_readKey, _read.toList());
      await prefs.setStringList(_dismissedKey, _dismissed.toList());
    } catch (_) {}
  }

  void _markRead(Iterable<String> ids) {
    _read.addAll(ids);
    _persist();
    _refilter();
  }

  void _dismiss(Iterable<String> ids) {
    _dismissed.addAll(ids);
    _persist();
    _refilter();
  }

  // ── Presentation ──────────────────────────────────────────────────────────
  _NotifCategory _category(String title) {
    final t = title.toLowerCase(); // title only: activity names in the body could mislead
    if (t.contains('account') || t.contains('password')) {
      return const _NotifCategory('users', Icons.manage_accounts_rounded, Color(0xFF6366F1));
    }
    if (t.contains('report') || t.contains('accomplishment')) {
      return const _NotifCategory('reports', Icons.assignment_turned_in_rounded, Color(0xFF0D9488));
    }
    if (t.contains('gpoa') || t.contains('proposal')) {
      return const _NotifCategory('gpoa', Icons.description_rounded, Color(0xFF4F46E5));
    }
    if (t.contains('event') || RegExp(r'\bdate\b').hasMatch(t) || t.contains('schedule')) {
      return const _NotifCategory('events', Icons.event_rounded, Color(0xFFB45309));
    }
    if (t.contains('score') || t.contains('evaluation')) {
      return const _NotifCategory('scores', Icons.stars_rounded, Color(0xFF15803D));
    }
    return const _NotifCategory('general', Icons.notifications_rounded, Color(0xFF64748B));
  }

  /// Role-aware destination, so a tap never lands on a page that doesn't exist.
  String _pageFor(String key) {
    switch (key) {
      case 'users':
        return _isAdmin ? 'Manage Users' : 'Dashboard';
      case 'reports':
        return _isAdmin ? 'Accomplishment Reports' : 'Submit Report';
      case 'gpoa':
        return 'Manage GPOA';
      case 'events':
        return 'Manage Events';
      case 'scores':
        return _isAdmin ? 'Manage Scores' : 'Evaluation Scores';
      default:
        return 'Dashboard';
    }
  }

  String _timeAgo(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<bool> _confirm(BuildContext ctx, {required String title, required String message, required String action}) async {
    final res = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 14, color: Color(0xFF475569))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(action),
          ),
        ],
      ),
    );
    return res == true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _items,
      builder: (context, items, child) {
        final unread = items.where((n) => !_isRead(n)).length;
        return Stack(
          key: _bellKey,
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: unread > 0 ? '$unread unread notification${unread == 1 ? '' : 's'}' : 'Notifications',
              icon: const Icon(Icons.notifications_none_rounded, color: _kBellGrey, size: 26),
              onPressed: _openInbox,
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: IgnorePointer(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _kTeal,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openInbox() async {
    final box = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final bellPos = box.localToGlobal(Offset.zero);
    final bellSize = box.size;
    final screen = MediaQuery.of(context).size;

    const double w = 380;
    final bellCenter = bellPos.dx + bellSize.width / 2;
    final maxLeft = screen.width - w - 12 < 12 ? 12.0 : screen.width - w - 12;
    final double left = (bellCenter - w / 2).clamp(12.0, maxLeft).toDouble();
    final double caretX = (bellCenter - left).clamp(24.0, w - 24).toDouble();
    final double top = bellPos.dy + bellSize.height + 2;
    final double maxListHeight = (screen.height - top - 150).clamp(160.0, 420.0).toDouble();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.03), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, a, b) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: w,
              child: Material(
                color: Colors.transparent,
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _items,
                  builder: (ctx, items, child) =>
                      _buildPopover(dialogContext, items, caretX, maxListHeight),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPopover(BuildContext dialogContext, List<Map<String, dynamic>> items, double caretX, double maxListHeight) {
    final unreadIds = items.where((n) => !_isRead(n)).map((n) => n['id'].toString()).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // little arrow pointing at the bell
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: caretX - 9),
            child: CustomPaint(size: const Size(18, 9), painter: _CaretPainter()),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF6B7C8D))),
                    if (unreadIds.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: _kTeal, shape: BoxShape.circle),
                        child: Text('${unreadIds.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFDCE4EA)),

              // list
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListHeight),
                child: items.isEmpty
                    ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 36, color: Color(0xFFB4C0CB)),
                      SizedBox(height: 10),
                      Text('You are all caught up', style: TextStyle(color: Color(0xFF7D8E9E), fontSize: 14, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('No notifications at this time.', style: TextStyle(color: Color(0xFFA3B1BE), fontSize: 12.5)),
                    ],
                  ),
                )
                    : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (c, i) => const Divider(height: 1, color: Color(0xFFDCE4EA)),
                  itemBuilder: (c, index) {
                    final item = items[index];
                    final id = item['id'].toString();
                    final title = item['title']?.toString() ?? 'Notification';
                    final body = item['body']?.toString() ?? '';
                    final cat = _category(title);
                    final isUnread = !_isRead(item);

                    return InkWell(
                      onTap: () {
                        _markRead([id]);
                        Navigator.pop(dialogContext);
                        widget.onNotificationTap?.call(_pageFor(cat.key));
                      },
                      child: Container(
                        color: isUnread ? const Color(0xFFEAF0F4) : const Color(0xFFF7F9FB),
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: cat.color.withValues(alpha: 0.15),
                              child: Icon(cat.icon, color: cat.color, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                                      color: const Color(0xFF4A5A6A),
                                    ),
                                  ),
                                  if (body.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(body, style: const TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500, color: Color(0xFF8394A4))),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      if (isUnread) ...[
                                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: _kTeal, shape: BoxShape.circle)),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(_timeAgo(item['created_at']), style: const TextStyle(fontSize: 11.5, color: Color(0xFFA3B1BE))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Dismiss',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFB4C0CB)),
                              onPressed: () => _dismiss([id]),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // footer actions
              if (items.isNotEmpty) ...[
                const Divider(height: 1, color: Color(0xFFDCE4EA)),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: unreadIds.isEmpty ? null : () => _markRead(unreadIds),
                        child: const Text('Mark all as read', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kTeal)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final ok = await _confirm(
                            dialogContext,
                            title: 'Clear all notifications?',
                            message: 'This clears your inbox only. Other users keep their own notifications.',
                            action: 'Clear all',
                          );
                          if (!ok) return;
                          final mineIds = items
                              .where((n) => (n['recipient_id']?.toString() ?? '') == _userId)
                              .map<Object>((n) => n['id'] as Object)
                              .toList();
                          _dismiss(items.map((n) => n['id'].toString()));
                          if (mineIds.isNotEmpty) {
                            try {
                              await _client.from('notifications').delete().inFilter('id', mineIds);
                            } catch (_) {}
                          }
                        },
                        child: const Text('Clear all', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF8394A4))),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}