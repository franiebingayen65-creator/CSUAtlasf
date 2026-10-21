import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csuatlasf/utils/app_utils.dart';

const _red = Color(0xFFDC2626);
const _primary = Color(0xFF4F46E5);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);
const _border = Color(0xFFE2E8F0);

class ScheduleEvent {
  final String id, orgName, title, status, facilities;
  final DateTime start, end;
  final DateTime? requestedAt;
  const ScheduleEvent({
    required this.id, required this.orgName, required this.title, required this.status,
    required this.facilities, required this.start, required this.end, this.requestedAt,
  });

  bool get approved => status == 'Scheduled';

  static ScheduleEvent? fromJson(Map<String, dynamic> j) {
    final start = DateTime.tryParse(j['proposed_date']?.toString() ?? '')?.toLocal();
    if (start == null) return null;
    return ScheduleEvent(
      id: j['id'].toString(),
      orgName: (j['organization_name'] ?? 'Organization').toString(),
      title: (j['title'] ?? 'Untitled').toString(),
      status: (j['status'] ?? '').toString(),
      facilities: (j['facilities_materials'] ?? '').toString(),
      start: start,
      end: start.add(AppUtils.parseDuration(j['time_frame'])),
      requestedAt: DateTime.tryParse(j['date_requested_at']?.toString() ?? '')?.toLocal(),
    );
  }

  bool overlaps(DateTime s, DateTime e) => s.isBefore(end) && e.isAfter(start);

  bool occursOn(DateTime day) {
    final d0 = DateTime(day.year, day.month, day.day);
    return start.isBefore(d0.add(const Duration(days: 1))) && end.isAfter(d0);
  }
}

Future<List<ScheduleEvent>> fetchScheduleOverview() async {
  final res = await Supabase.instance.client.rpc('get_schedule_overview');
  return (res as List)
      .map((e) => ScheduleEvent.fromJson(Map<String, dynamic>.from(e as Map)))
      .whereType<ScheduleEvent>()
      .toList();
}

String formatClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String formatRange(ScheduleEvent e) {
  final sameDay = e.start.year == e.end.year && e.start.month == e.end.month && e.start.day == e.end.day;
  return sameDay
      ? '${formatClock(e.start)} – ${formatClock(e.end)}'
      : '${formatClock(e.start)} – ${e.end.month}/${e.end.day} ${formatClock(e.end)}';
}

/// Opens the calendar. Returns the chosen date + start time, or null if cancelled.
Future<DateTime?> showScheduleCalendar(
    BuildContext context, {
      required DateTime initial,
      required DateTime firstDate,
      required Duration duration,
      String? excludeId,
    }) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _ScheduleCalendarDialog(initial: initial, firstDate: firstDate, duration: duration, excludeId: excludeId),
  );
}

class _ScheduleCalendarDialog extends StatefulWidget {
  final DateTime initial, firstDate;
  final Duration duration;
  final String? excludeId;
  const _ScheduleCalendarDialog({required this.initial, required this.firstDate, required this.duration, this.excludeId});

  @override
  State<_ScheduleCalendarDialog> createState() => _ScheduleCalendarDialogState();
}

class _ScheduleCalendarDialogState extends State<_ScheduleCalendarDialog> {
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);
  late DateTime _selected = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);
  List<ScheduleEvent> _events = [];
  bool _loading = true, _failed = false;

  static const _months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  static const _weekdays = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

  @override
  void initState() {
    super.initState();
    fetchScheduleOverview().then((list) {
      if (!mounted) return;
      setState(() {
        _events = list.where((e) => e.id != widget.excludeId).toList();
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    });
  }

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  // The first organization to request is listed first.
  List<ScheduleEvent> _eventsOn(DateTime d) {
    final list = _events.where((e) => e.occursOn(d)).toList();
    list.sort((a, b) => (a.requestedAt ?? a.start).compareTo(b.requestedAt ?? b.start));
    return list;
  }

  Future<void> _confirm() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(widget.initial));
    if (t == null || !mounted) return;
    final start = DateTime(_selected.year, _selected.month, _selected.day, t.hour, t.minute);
    final end = start.add(widget.duration);
    final clashes = _events.where((e) => e.overlaps(start, end)).toList();

    if (clashes.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: _red),
            SizedBox(width: 10),
            Expanded(child: Text('Schedule conflict')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${formatClock(start)} – ${formatClock(end)} overlaps with:'),
            const SizedBox(height: 10),
            for (final c in clashes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• ${c.orgName} (${formatRange(c)}) – ${c.approved ? 'approved' : 'requested'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            const Text('You can still send your request. OSDW decides, and the earlier request has priority.',
                style: TextStyle(color: _muted, fontSize: 13)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Change time')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
              child: const Text('Request anyway'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    Navigator.pop(context, start);
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsOn(_selected);
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = first.weekday % 7; // Sunday = 0
    final cells = <DateTime?>[
      for (var i = 0; i < offset; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(_month.year, _month.month, d),
    ];
    while (cells.length % 7 != 0) { cells.add(null); }

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${_months[_month.month - 1]} ${_month.year}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _ink)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (final w in _weekdays)
                Expanded(child: Center(child: Text(w, style: const TextStyle(fontSize: 12, color: _faint)))),
            ]),
            const Divider(height: 12, color: _border),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else
              for (var r = 0; r < cells.length; r += 7)
                Row(children: [for (final d in cells.sublist(r, r + 7)) _cell(d)]),
            const SizedBox(height: 8),
            Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: _red, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text('Has requested / approved events', style: TextStyle(fontSize: 12, color: _muted)),
            ]),
            if (_failed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Could not load other schedules. You can still pick a date.', style: TextStyle(fontSize: 12, color: _red)),
              ),
            const Divider(height: 28, color: _border),
            Text(
              '${_weekdays[_selected.weekday % 7]}, ${_months[_selected.month - 1]} ${_selected.day}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: dayEvents.isEmpty
                  ? const Text('No events on this date. It is free.', style: TextStyle(color: _muted, fontSize: 13))
                  : ListView(shrinkWrap: true, children: [
                for (var i = 0; i < dayEvents.length; i++) _eventTile(dayEvents[i], i + 1),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.access_time_rounded, size: 18),
                label: const Text('Choose time'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary, foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _cell(DateTime? d) {
    if (d == null) return const Expanded(child: SizedBox(height: 52));
    final disabled = d.isBefore(widget.firstDate);
    final selected = _same(d, _selected);
    final today = _same(d, DateTime.now());
    final busy = !disabled && _eventsOn(d).isNotEmpty;

    Color textColor = _ink;
    if (disabled) {
      textColor = const Color(0xFFCBD5E1);
    } else if (selected) {
      textColor = Colors.white;
    } else if (busy) {
      textColor = _red;
    } else if (today) {
      textColor = _primary;
    }

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : () => setState(() => _selected = d),
        child: SizedBox(
          height: 52,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 34, height: 34, alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _primary : (busy ? _red.withValues(alpha: 0.08) : null),
                border: busy && !selected ? Border.all(color: _red, width: 1.5) : null,
              ),
              child: Text('${d.day}',
                  style: TextStyle(fontSize: 15, color: textColor, fontWeight: (today || busy || selected) ? FontWeight.w700 : FontWeight.w500)),
            ),
            const SizedBox(height: 3),
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(color: busy ? _red : Colors.transparent, shape: BoxShape.circle),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _eventTile(ScheduleEvent e, int order) {
    final color = e.approved ? const Color(0xFF059669) : const Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(e.orgName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(e.approved ? 'Scheduled (approved)' : 'Requested',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(e.title, style: const TextStyle(fontSize: 12.5, color: _muted)),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 14, color: _muted),
          const SizedBox(width: 6),
          Text(formatRange(e), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink)),
        ]),
        if (e.facilities.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.inventory_2_outlined, size: 14, color: _muted),
            const SizedBox(width: 6),
            Expanded(child: Text(e.facilities, style: const TextStyle(fontSize: 12, color: _muted))),
          ]),
        ],
      ]),
    );
  }
}