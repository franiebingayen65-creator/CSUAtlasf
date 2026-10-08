import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _NotificationInboxButtonState extends State<NotificationInboxButton> {
  static final Set<String> _dismissedIds = {};

  @override
  void initState() {
    super.initState();
    _loadDismissedIds();
  }

  Future<void> _loadDismissedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('dismissed_notification_ids') ?? [];
      _dismissedIds.addAll(saved);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveDismissedId(String id) async {
    _dismissedIds.add(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_notification_ids', _dismissedIds.toList());
    } catch (_) {}
  }

  Future<void> _saveDismissedIds(List<String> ids) async {
    _dismissedIds.addAll(ids);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_notification_ids', _dismissedIds.toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();

    final stream = client
        .from('notifications')
        .stream(primaryKey: ['id']);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final rawNotifications = List<Map<String, dynamic>>.from(snapshot.data ?? const []);

        final notifications = rawNotifications.where((item) {
          final id = item['id']?.toString();
          if (id != null && _dismissedIds.contains(id)) return false;

          final rId = item['recipient_id']?.toString();
          final rRole = (item['recipient_role'] ?? '').toString().toLowerCase();
          if (rId == userId) return true;
          if (rId == null || rId.isEmpty) return true;
          if (rRole == 'all' || rRole == 'admin' || rRole == 'president' || rRole == 'adviser') return true;
          return false;
        }).toList()
          ..sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));

        final unread = notifications.where((item) => item['read_at'] == null).length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B)),
              onPressed: () => _openInbox(notifications),
            ),
            if (unread > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmClearAll(BuildContext ctx) async {
    final res = await showDialog<bool>(
      context: ctx,
      builder: (confirmCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 10),
            Text('Clear All Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Are you sure you want to clear all notifications? This action cannot be undone.',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(confirmCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<bool> _confirmDeleteSingle(BuildContext ctx, String title) async {
    final res = await showDialog<bool>(
      context: ctx,
      builder: (confirmCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 8),
            Text('Delete Notification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$title"?',
          style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(confirmCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _openInbox(List<Map<String, dynamic>> notifications) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.notifications_active_rounded, color: Color(0xFF6366F1), size: 24),
                SizedBox(width: 10),
                Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            if (notifications.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await _confirmClearAll(dialogContext);
                  if (!confirmed) return;

                  final idsToDismiss = <String>[];
                  for (var item in notifications) {
                    final id = item['id']?.toString();
                    if (id != null) idsToDismiss.add(id);
                    try {
                      await client.from('notifications').delete().eq('id', item['id']);
                    } catch (_) {}
                  }
                  await _saveDismissedIds(idsToDismiss);
                  if (userId != null) {
                    try {
                      await client.from('notifications').delete().eq('recipient_id', userId);
                    } catch (_) {}
                  }
                  if (mounted) setState(() {});
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: Color(0xFFDC2626)),
                label: const Text('Clear all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
              ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: notifications.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No notifications at this time.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ),
                )
              : StatefulBuilder(
                  builder: (ctx, setModalState) {
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifications.length,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                      itemBuilder: (ctx, index) {
                        final item = notifications[index];
                        final id = item['id']?.toString();
                        final title = item['title']?.toString() ?? 'Notification';
                        final color = _statusColor(item['status']?.toString());

                        final isUnread = item['read_at'] == null;

                        return Container(
                          decoration: BoxDecoration(
                            color: isUnread ? color.withAlpha(20) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isUnread ? color.withAlpha(80) : Colors.grey.shade200),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withAlpha(30),
                              child: Icon(Icons.notifications_rounded, color: color, size: 20),
                            ),
                            title: Text(
                              title,
                              style: TextStyle(fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600, fontSize: 14, color: const Color(0xFF1E293B)),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                item['body']?.toString() ?? '',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isUnread)
                                  IconButton(
                                    tooltip: 'Mark as read',
                                    icon: const Icon(Icons.check_circle_outline_rounded, size: 20, color: Color(0xFF10B981)),
                                    onPressed: () async {
                                      if (id != null) {
                                        try {
                                          await client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
                                        } catch (_) {}
                                      }
                                      setModalState(() {
                                        item['read_at'] = DateTime.now().toUtc().toIso8601String();
                                      });
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Delete notification',
                                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                                  onPressed: () async {
                                    final confirmed = await _confirmDeleteSingle(dialogContext, title);
                                    if (!confirmed) return;

                                    if (id != null) await _saveDismissedId(id);
                                    try {
                                      await client.from('notifications').delete().eq('id', item['id']);
                                    } catch (_) {}
                                    setModalState(() {
                                      notifications.removeAt(index);
                                    });
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              if (id != null) {
                                try {
                                  await client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
                                } catch (_) {}
                              }
                              if (dialogContext.mounted) Navigator.pop(dialogContext);

                              if (widget.onNotificationTap != null) {
                                final status = (item['status'] ?? '').toString();
                                final titleLower = title.toLowerCase();
                                final bodyLower = (item['body'] ?? '').toString().toLowerCase();

                                if (status.contains('Scores') || titleLower.contains('score') || titleLower.contains('evaluation') || bodyLower.contains('score')) {
                                  widget.onNotificationTap!('Evaluation Scores');
                                } else if (titleLower.contains('gpoa') || titleLower.contains('proposal') || status.contains('Pending')) {
                                  widget.onNotificationTap!('Manage GPOA');
                                } else if (titleLower.contains('report') || titleLower.contains('accomplishment') || bodyLower.contains('report')) {
                                  widget.onNotificationTap!('Submit Report');
                                } else if (titleLower.contains('event') || titleLower.contains('letter') || titleLower.contains('schedule')) {
                                  widget.onNotificationTap!('Scheduling & Letters');
                                } else {
                                  widget.onNotificationTap!('Dashboard');
                                }
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Color _statusColor(String? status) {
    if (status == 'Scores Posted') return const Color(0xFF15803D);
    return statusColorFor(status ?? '');
  }
}
