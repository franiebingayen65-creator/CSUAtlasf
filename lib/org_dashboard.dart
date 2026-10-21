import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:csuatlasf/utils/app_utils.dart';
import 'package:csuatlasf/utils/storage_utils.dart';
import 'package:csuatlasf/widgets/common_ui.dart';
import 'package:csuatlasf/widgets/gpoa_details.dart';
import 'package:csuatlasf/widgets/pdf_preview_dialog.dart';
import 'package:csuatlasf/utils/user_archive.dart';
import 'package:csuatlasf/utils/school_year_service.dart';
import 'package:csuatlasf/utils/pdf_generator.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csuatlasf/widgets/schedule_calendar.dart';

// cspell:ignore OSDW
// ════════════════════════════════════════════════════════════════════════════
//  DESIGN SYSTEM  (one place to change colors, spacing and shared widgets)
// ════════════════════════════════════════════════════════════════════════════

class _C {
  static const bg = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const primary = Color(0xFF4F46E5);
  static const primarySoft = Color(0xFFEEF2FF);
  static const text = Color(0xFF0F172A);
  static const body = Color(0xFF334155);
  static const muted = Color(0xFF64748B);
  static const faint = Color(0xFF94A3B8);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
}

const _sdgOptions = [
  'SDG 1: No Poverty', 'SDG 2: Zero Hunger', 'SDG 3: Good Health and Well-being', 'SDG 4: Quality Education', 'SDG 5: Gender Equality',
  'SDG 6: Clean Water and Sanitation', 'SDG 7: Affordable and Clean Energy', 'SDG 8: Decent Work and Economic Growth', 'SDG 9: Industry, Innovation and Infrastructure',
  'SDG 10: Reduced Inequality', 'SDG 11: Sustainable Cities and Communities', 'SDG 12: Responsible Consumption and Production', 'SDG 13: Climate Action',
  'SDG 14: Life Below Water', 'SDG 15: Life on Land', 'SDG 16: Peace, Justice and Strong Institutions', 'SDG 17: Partnerships for the Goals',
];


const _participantGroups = <String, List<String>>{
  'By year level': ['1st year Students', '2nd Year Students', '3rd Year Students', '4th Year Students', 'Transferees'],
  'Specific groups': ['COLSC Officers', 'Faculty and Staffs'],
  'Open to everyone': ['All College Students', 'All student of CSU Lal-lo'],
};

const _participantHelp = <String, String>{
  '1st year Students': 'Freshmen only',
  '2nd Year Students': 'Second-year students only',
  '3rd Year Students': 'Third-year students only',
  '4th Year Students': 'Fourth-year students only',
  'Transferees': 'Students who transferred from another school',
  'COLSC Officers': 'Student council officers and class mayors',
  'Faculty and Staffs': 'Teachers and school staff',
  'All College Students': 'Every student in your college or program',
  'All student of CSU Lal-lo': 'Every student on the whole CSU Lal-lo campus',
};

const _personsGroups = <String, List<String>>{
  'Students': ['Student Officers'],
  'Faculty and staff': ['Faculty Advisers', 'OSDW'],
  'Outside people': ['Guest Speakers'],
};

const _personsHelp = <String, String>{
  'Student Officers': 'Officers of your organization who will run the activity',
  'Faculty Advisers': 'Teachers who guide or supervise your organization',
  'OSDW': 'OSDW (Donna Macadangdang)',
  'Guest Speakers': 'Invited speakers or resource persons',
};

List<String> _splitList(dynamic raw) => (raw?.toString() ?? '')
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty && e != 'Not specified')
    .toList();

String _fmt12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

List<String> _activityTypesFor(String? orgType) {
  final type = (orgType ?? '').toLowerCase();
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

/// Returns the options that appear in a saved comma-separated string.
List<String> _matchOptions(dynamic raw, List<String> options) {
  final s = raw?.toString() ?? '';
  return options.where((o) => s.contains(o)).toList();
}

BoxDecoration _box({Color? color, Color? border, double radius = 12}) => BoxDecoration(
  color: color ?? Colors.white,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: border ?? _C.border),
);

OutlineInputBorder _outline(Color c, [double w = 1]) =>
    OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c, width: w));

InputDecoration _input(String label, {IconData? icon, String? hint}) => InputDecoration(
  labelText: label,
  hintText: hint,
  hintStyle: const TextStyle(color: _C.faint, fontSize: 13),
  labelStyle: const TextStyle(color: _C.muted, fontSize: 14),
  prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _C.muted),
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  border: _outline(_C.border),
  enabledBorder: _outline(_C.border),
  focusedBorder: _outline(_C.primary, 1.5),
  errorBorder: _outline(_C.danger),
  focusedErrorBorder: _outline(_C.danger, 1.5),
);

ButtonStyle _filledBtn([Color color = _C.primary]) => ElevatedButton.styleFrom(
  backgroundColor: color,
  foregroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
);

ButtonStyle _outlineBtn([Color color = _C.primary]) => OutlinedButton.styleFrom(
  foregroundColor: color,
  side: BorderSide(color: color.withValues(alpha: 0.4)),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
);

Text _meta(String text, {Color color = _C.muted, bool bold = false}) =>
    Text(text, style: TextStyle(fontSize: 12.5, color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.w400));

Widget _statusLine(dynamic status) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Text('Status: ', style: TextStyle(fontSize: 12.5, color: _C.muted)),
    StatusBadge(status: status),
  ],
);

class _PageHeader extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  const _PageHeader({required this.title, required this.subtitle, this.actions = const [], this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null) ...[
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, color: _C.body),
            style: IconButton.styleFrom(backgroundColor: Colors.white, side: const BorderSide(color: _C.border)),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _C.text, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 14, color: _C.muted)),
            ],
          ),
        ),
        if (actions.isNotEmpty) Wrap(spacing: 12, runSpacing: 8, children: actions),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  final List<String> labels;
  final ValueChanged<int>? onTap;
  const _Tabs({required this.labels, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: _box(),
      child: TabBar(
        onTap: onTap,
        labelColor: _C.primary,
        unselectedLabelColor: _C.muted,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: _C.primarySoft, borderRadius: BorderRadius.circular(8)),
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: labels.map((l) => Tab(height: 40, child: Text(l, overflow: TextOverflow.ellipsis))).toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  const _EmptyState({required this.icon, required this.text, this.hint});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: _C.faint),
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _C.body, fontSize: 14, fontWeight: FontWeight.w500)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!, textAlign: TextAlign.center, style: const TextStyle(color: _C.muted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard list row: icon · title + details · actions
class _ItemCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> body;
  final List<Widget> actions;
  final VoidCallback? onTap;
  const _ItemCard({required this.icon, this.color = _C.primary, required this.title, this.body = const [], this.actions = const [], this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _box(),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: _C.text)),
                    for (final w in body) Padding(padding: const EdgeInsets.only(top: 6), child: w),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistChip extends StatelessWidget {
  final String label;
  final bool done;
  const _ChecklistChip(this.label, this.done);

  @override
  Widget build(BuildContext context) {
    final c = done ? _C.success : _C.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 14, color: c),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  const _FormSection({required this.title, this.subtitle, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20, color: _C.primary),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.only(left: 30), child: Text(subtitle!, style: const TextStyle(fontSize: 13, color: _C.muted))),
          ],
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Tap-to-choose field that shows the picked items as chips.
class _MultiSelectField extends StatelessWidget {
  final String label, hint;
  final IconData icon;
  final List<String> items;
  final VoidCallback onTap;
  final void Function(String) onRemove;
  final String Function(String)? chipText;
  const _MultiSelectField({required this.label, required this.hint, required this.icon, required this.items, required this.onTap, required this.onRemove, this.chipText});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _C.body)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            constraints: const BoxConstraints(minHeight: 50),
            decoration: _box(radius: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: _C.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: items.isEmpty
                      ? Text(hint, style: const TextStyle(color: _C.faint, fontSize: 13))
                      : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: items
                        .map((s) => Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _C.primarySoft,
                      side: BorderSide.none,
                      label: Text(chipText?.call(s) ?? s, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _C.primary)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 14),
                      deleteIconColor: _C.primary,
                      onDeleted: () => onRemove(s),
                    ))
                        .toList(),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: _C.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
/// Grouped picker with a short explanation under every choice.
/// Grouped picker with a short explanation under every choice
/// and an "Others, please specify" box.
Future<void> _pickGrouped(
    BuildContext context, {
      required String title,
      required String intro,
      required Map<String, List<String>> groups,
      required Map<String, String> help,
      required List<String> selected,
      required VoidCallback onChanged,
      bool allowOther = true,
      String otherHint = 'e.g. Barangay officials',
    }) {
  final otherCtrl = TextEditingController();
  final known = groups.values.expand((e) => e).toSet();

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        void toggle(String o, bool on) {
          setD(() {
            if (on) {
              if (!selected.contains(o)) selected.add(o);
            } else {
              selected.remove(o);
            }
          });
          onChanged();
        }

        void addOther() {
          final t = otherCtrl.text.trim().replaceAll(',', ' ');
          if (t.isEmpty) return;
          setD(() {
            if (!selected.contains(t)) selected.add(t);
            otherCtrl.clear();
          });
          onChanged();
        }

        final customs = selected.where((s) => !known.contains(s)).toList();

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              _meta('${selected.length} selected', color: _C.primary, bold: true),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _C.primarySoft, borderRadius: BorderRadius.circular(10)),
                    child: Text(intro, style: const TextStyle(fontSize: 12.5, color: _C.primary, height: 1.4)),
                  ),
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                      child: Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _C.faint, letterSpacing: 1)),
                    ),
                    for (final o in entry.value)
                      CheckboxListTile(
                        title: Text(o, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _C.text)),
                        subtitle: help[o] == null ? null : Text(help[o]!, style: const TextStyle(fontSize: 12.5, color: _C.muted)),
                        value: selected.contains(o),
                        dense: true,
                        activeColor: _C.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => toggle(o, v == true),
                      ),
                  ],
                  if (allowOther) ...[
                    const Divider(height: 28),
                    const Text('Others (not in the list)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.text)),
                    const SizedBox(height: 2),
                    const Text('If nothing in the list fits, please specify.', style: TextStyle(fontSize: 12.5, color: _C.muted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: otherCtrl,
                            decoration: _input('Please specify', hint: otherHint),
                            onSubmitted: (_) => addOther(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(onPressed: addOther, style: _filledBtn(), child: const Text('Add')),
                      ],
                    ),
                    if (customs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: customs
                            .map((c) => Chip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          backgroundColor: _C.primarySoft,
                          side: BorderSide.none,
                          onDeleted: () => toggle(c, false),
                        ))
                            .toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: selected.isEmpty ? null : () { setD(() => selected.clear()); onChanged(); },
              child: const Text('Clear all'),
            ),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), style: _filledBtn(), child: const Text('Done')),
          ],
        );
      },
    ),
  );
}
Future<void> _pickSingle(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((o) {
                final isSelected = selected.contains(o);
                return ListTile(
                  title: Text(o, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400, color: isSelected ? _C.primary : _C.text)),
                  trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: _C.primary, size: 20) : null,
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    selected..clear()..add(o);
                    onChanged();
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _C.muted)),
          ),
        ],
      ),
    ),
  );
}

Future<void> _pickMultiple(
  BuildContext context, {
  required String title,
  required List<String> options,
  required List<String> selected,
  required VoidCallback onChanged,
  bool allowCustom = true,
}) {
  final customCtrl = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        void addCustom() {
          final val = customCtrl.text.trim().replaceAll(',', ' ');
          if (val.isNotEmpty) {
            setD(() {
              if (!selected.contains(val)) selected.add(val);
              customCtrl.clear();
            });
            onChanged();
          }
        }

        final customs = selected.where((s) => !options.contains(s)).toList();

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...options.map((o) {
                    return CheckboxListTile(
                      title: Text(o, style: const TextStyle(fontSize: 13.5)),
                      value: selected.contains(o),
                      dense: true,
                      activeColor: _C.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) {
                        setD(() {
                          if (v == true) {
                            if (!selected.contains(o)) selected.add(o);
                          } else {
                            selected.remove(o);
                          }
                        });
                        onChanged();
                      },
                    );
                  }),
                  if (allowCustom) ...[
                    const Divider(height: 24),
                    const Text('Specify if not in the list:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.text)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customCtrl,
                            decoration: _input('Specify item', hint: 'Type custom item...'),
                            onSubmitted: (_) => addCustom(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: addCustom,
                          style: _filledBtn(),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    if (customs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: customs
                            .map((c) => Chip(
                                  label: Text(c, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  backgroundColor: _C.primarySoft,
                                  side: BorderSide.none,
                                  deleteIconColor: _C.primary,
                                  onDeleted: () {
                                    setD(() => selected.remove(c));
                                    onChanged();
                                  },
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    ),
  );
}

/// Shared dialog shell: header · scrollable body · optional action footer.
class _DialogFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final double maxWidth;
  final Widget child;
  final List<Widget> actions;
  const _DialogFrame({
    required this.title,
    this.subtitle,
    this.icon = Icons.description_rounded,
    this.color = _C.primary,
    this.maxWidth = 800,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.text)),
                        if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _C.muted)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close_rounded, color: _C.muted), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1, color: _C.border),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: child)),
            if (actions.isNotEmpty) ...[
              const Divider(height: 1, color: _C.border),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

GPOAActivityDetailsView _detailsView(Map<String, dynamic> a, {dynamic onStatusUpdate, bool timeOnly = false}) {
  final status = (a['status'] ?? 'Pending').toString();
  final isFinalDate = status == 'Scheduled' || status == 'Completed';
  final hasDate = isFinalDate && a['proposed_date'] != null && a['proposed_date'].toString().trim().isNotEmpty;
  return GPOAActivityDetailsView(
    title: a['title'] ?? 'Untitled',
    sdgs: a['sdgs'] ?? 'Not specified',
    objectives: a['objectives'] ?? 'Not specified',
    outcome: a['outcome'] ?? 'Not specified',
    participants: a['participants'] ?? 'Not specified',
    timeFrame: a['time_frame'] ?? 'Not specified',
    delivery: a['delivery_strategy'] ?? 'Not specified',
    persons: a['persons_involved'] ?? 'Not specified',
    facilities: a['facilities_materials'] ?? 'Not specified',
    budget: a['budget_allocation'] ?? 'Not specified',
    status: status,
    createdAt: AppUtils.formatDateTime(a['created_at']),
    proposedDate: !hasDate ? null : (timeOnly ? AppUtils.formatDateTime(a['proposed_date']) : AppUtils.formatEventRange(a['proposed_date'], a['time_frame'])),
    onStatusUpdate: onStatusUpdate,
  );
}

void _showActivityDialog(BuildContext context, Map<String, dynamic> activity) {
  showDialog(
    context: context,
    builder: (_) => _DialogFrame(
      title: 'Proposal details',
      subtitle: activity['title']?.toString(),
      maxWidth: 900,
      child: _detailsView(activity),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  SHELL: state, sidebar, top bar
// ════════════════════════════════════════════════════════════════════════════

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
  StreamSubscription? _orgSubscription;

  @override
  void initState() {
    super.initState();
    UserArchive.changes.addListener(_reapplyArchive);
    _fetchOrgData();
  }

  Future<void> _reapplyArchive() async {
    await UserArchive.decorate(_myActivities, 'activity');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    UserArchive.changes.removeListener(_reapplyArchive);
    _activitySubscription?.cancel();
    _orgSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrgData() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('id, full_name, email, role, organization_id, organizations(*)')
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) return;

      final org = profile['organizations'];
      if (org is! Map) return;
      _userRole = profile['role']?.toString();
      _orgData = Map<String, dynamic>.from(org);
      final orgId = _orgData!['id'].toString();

      final results = await Future.wait([
        _supabase.from('profiles').select('id, full_name, email, role, organization_id').eq('organization_id', orgId),
        _supabase.from('activities').select().eq('organization_id', orgId),
      ]);
      if (!mounted) return;
      final acts = List<Map<String, dynamic>>.from(results[1] as List);
      await UserArchive.decorate(acts, 'activity');
      if (!mounted) return;
      setState(() {
        _orgProfiles = List<Map<String, dynamic>>.from(results[0] as List);
        _myActivities = acts;
      });

      _activitySubscription?.cancel();
      _activitySubscription = _supabase.from('activities').stream(primaryKey: ['id']).eq('organization_id', orgId).listen((data) async {
        final acts = List<Map<String, dynamic>>.from(data);
        await UserArchive.decorate(acts, 'activity');
        if (mounted) setState(() => _myActivities = acts);
      });

      // NEW: live updates for the organization row (lock/unlock)
      _orgSubscription?.cancel();
      _orgSubscription = _supabase
          .from('organizations')
          .stream(primaryKey: ['id'])
          .eq('id', orgId)
          .listen((rows) {
        if (rows.isNotEmpty && mounted && _orgData != null) {
          setState(() => _orgData = {..._orgData!, ...rows.first});
        }
      });
    } catch (e) {
      debugPrint('Org data load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  int _initialTab = 0;

  static const _pageAliases = {
    'GPOA Status': 'Manage GPOA',
    'GPOA Review': 'Manage GPOA',
    'Scheduling & Letters': 'Manage Events',
    'View Events': 'Manage Events',
    'Organization Ranks': 'Evaluation Scores',
  };

  void _onPageSelected(String page, {int tab = 0}) {
    setState(() {
      _activePage = _pageAliases[page] ?? page;
      _initialTab = tab;
    });
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            child: const Text('Log out', style: TextStyle(color: _C.danger, fontWeight: FontWeight.w600)),
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
    if (_orgData == null) {
      return Scaffold(
        backgroundColor: _C.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 56, color: _C.danger),
              const SizedBox(height: 16),
              const Text('No organization is linked to your account.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _C.text)),
              const SizedBox(height: 4),
              const Text('Please contact the OSDW office to be assigned.', style: TextStyle(color: _C.muted)),
              const SizedBox(height: 20),
              ElevatedButton(style: _filledBtn(), onPressed: _showLogoutDialog, child: const Text('Log out')),
            ],
          ),
        ),
      );
    }

    final role = _userRole ?? 'President';
    final isAdviser = role == 'Adviser';
    final activeActivities = _myActivities.where((a) => a['is_archived'] != true).toList();

    final eventsActionCount = isAdviser
        ? activeActivities.where((a) => a['status'] == 'Awaiting Date Approval').length
        : activeActivities.where((a) => ['Approved', 'Reschedule'].contains(a['status'])).length;

    final gpoaActionCount = isAdviser
        ? activeActivities.where((a) => a['status'] == 'Pending').length
        : activeActivities.where((a) => a['status'] == 'Needs Revision').length;

    final reportsActionCount = isAdviser
        ? 0
        : activeActivities.where((a) => a['status'] == 'Completed' || AppUtils.isEventDone(a)).length;

    return Scaffold(
      backgroundColor: _C.bg,
      body: Row(
        children: [
          _OrgSidebar(
            isCollapsed: _isSidebarCollapsed,
            activePage: _activePage,
            onPageSelected: _onPageSelected,
            userRole: role,
            eventsActionCount: eventsActionCount,
            gpoaActionCount: gpoaActionCount,
            reportsActionCount: reportsActionCount,
            onToggleCollapse: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
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
                  child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _buildBody()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() => KeyedSubtree(key: ValueKey('$_activePage-$_initialTab'), child: _buildPage());

  Widget _buildPage() {
    final role = _userRole ?? 'President';
    switch (_activePage) {
      case 'GPOA Submission':
        if (_gpoaLocked(_myActivities, orgData: _orgData)) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PageHeader(title: 'New GPOA proposal', subtitle: 'Proposals are locked.', onBack: () => _onPageSelected('Manage GPOA')),
              const Expanded(
                child: _EmptyState(
                  icon: Icons.lock_rounded,
                  text: 'All your proposals are approved, so new proposals are locked.',
                  hint: 'Contact OSDW if you need to add another activity.',
                ),
              ),
            ]),
          );
        }
        return _GPOASubmissionView(orgId: _orgData!['id'], orgType: _orgData!['type']?.toString(), onBack: () => _onPageSelected('Manage GPOA'));
      case 'Manage GPOA':
        return _GPOAStatusGridView(activities: _myActivities, orgData: _orgData, initialTab: _initialTab, onAction: (page) => _onPageSelected(page), userRole: role, onRefresh: _fetchOrgData);
      case 'Manage Events':
        return _OrgManageEventsView(orgId: _orgData!['id'].toString(), activities: _myActivities, initialTab: _initialTab, onRefresh: _fetchOrgData, userRole: role, onGoToReports: () => _onPageSelected('Submit Report'));
      case 'GPOA Report':
        return _GPOAReportPrintingView(orgData: _orgData!, activities: _myActivities, profiles: _orgProfiles, onBack: () => _onPageSelected('Manage GPOA'));
      case 'Submit Report':
        return _SubmitReportView(activities: _myActivities, userRole: role, onRefresh: _fetchOrgData);
      case 'Evaluation Scores':
        return _OrgEvaluationScoresView(orgData: _orgData!);
      case 'Archives':
        return _ArchivesView(orgData: _orgData!, activities: _myActivities, userRole: role);
      case 'Profile':
        return _OrgProfileView(orgData: _orgData!);
      case 'Dashboard':
      default:
        return _OrgDashboardContent(orgData: _orgData!, activities: _myActivities, userRole: role, onRefresh: _fetchOrgData, onNavigate: _onPageSelected);
    }
  }
}

class _OrgSidebar extends StatelessWidget {
  final bool isCollapsed;
  final String activePage;
  final Function(String) onPageSelected;
  final VoidCallback onToggleCollapse;
  final String userRole;
  final int eventsActionCount;
  final int gpoaActionCount;
  final int reportsActionCount;

  const _OrgSidebar({
    required this.isCollapsed,
    required this.activePage,
    required this.onPageSelected,
    required this.onToggleCollapse,
    required this.userRole,
    this.eventsActionCount = 0,
    this.gpoaActionCount = 0,
    this.reportsActionCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      clipBehavior: Clip.hardEdge,
      width: isCollapsed ? 76 : 260,
      decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: _C.border))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
            child: Row(
              mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _C.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: Image.asset(
                    'assets/images/csulogo.png',
                    width: 28,
                    height: 28,
                    errorBuilder: (c, e, s) => const Icon(Icons.school_rounded, color: _C.primary, size: 28),
                  ),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ATLAS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _C.text, letterSpacing: 1)),
                        Text(isAdviser ? 'Adviser Portal' : 'Organization Portal', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _C.muted)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: _C.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _SidebarItem(icon: Icons.dashboard_rounded, title: 'Dashboard', isSelected: activePage == 'Dashboard', isCollapsed: isCollapsed, onTap: () => onPageSelected('Dashboard')),
                if (!isCollapsed) const _SidebarHeader(title: 'PLANNING'),
                _SidebarItem(
                  icon: Icons.assignment_rounded,
                  title: 'GPOA Proposals',
                  badgeCount: gpoaActionCount,
                  isSelected: ['Manage GPOA', 'GPOA Submission', 'GPOA Review', 'GPOA Report'].contains(activePage),
                  isCollapsed: isCollapsed,
                  onTap: () => onPageSelected('Manage GPOA'),
                ),
                if (!isCollapsed) const _SidebarHeader(title: 'EVENTS'),
                _SidebarItem(
                  icon: Icons.calendar_month_rounded,
                  title: isAdviser ? 'Event Calendar' : 'Event Dates',
                  badgeCount: eventsActionCount,
                  isSelected: ['Manage Events', 'View Events', 'Scheduling & Letters', 'Event Dates'].contains(activePage),
                  isCollapsed: isCollapsed,
                  onTap: () => onPageSelected('Manage Events'),
                ),
                if (!isCollapsed) const _SidebarHeader(title: 'REPORTS'),
                _SidebarItem(
                  icon: Icons.upload_file_rounded,
                  title: isAdviser ? 'Review Reports' : 'Accomplishment Reports',
                  badgeCount: reportsActionCount,
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
                _SidebarItem(icon: Icons.folder_rounded, title: 'Archives', isSelected: activePage == 'Archives', isCollapsed: isCollapsed, onTap: () => onPageSelected('Archives')),
              ],
            ),
          ),
          const Divider(height: 1, color: _C.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _SidebarItem(
              icon: isCollapsed ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded,
              title: 'Collapse menu',
              isSelected: false,
              isCollapsed: isCollapsed,
              onTap: onToggleCollapse,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected, isCollapsed;
  final int? badgeCount;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isSelected = false,
    this.isCollapsed = false,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? _C.primary : _C.muted;
    final hasBadge = badgeCount != null && badgeCount! > 0;

    return Tooltip(
      message: isCollapsed ? (hasBadge ? '$title ($badgeCount action required)' : title) : '',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: isSelected ? _C.primarySoft : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 20, color: fg),
                    if (isCollapsed && hasBadge)
                      Positioned(
                        top: -3,
                        right: -5,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD97706),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? _C.primary : _C.body,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (hasBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(14, 20, 12, 6),
      child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _C.faint, letterSpacing: 1.2)),
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
      height: 72,
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _C.border))),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(orgName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: _C.text)),
                const SizedBox(height: 2),
                Text('Signed in as $userRole', style: const TextStyle(fontSize: 12, color: _C.muted)),
              ],
            ),
          ),
          NotificationInboxButton(onNotificationTap: onNavigate),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (val) {
              if (val == 'logout') onLogout();
              if (val == 'profile') onProfile();
            },
            offset: const Offset(0, 48),
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _C.border)),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.business_rounded, size: 18, color: _C.body), SizedBox(width: 12), Text('Organization profile')])),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout_rounded, size: 18, color: _C.danger), SizedBox(width: 12), Text('Log out', style: TextStyle(color: _C.danger))])),
            ],
            child: const CircleAvatar(radius: 18, backgroundColor: _C.primarySoft, child: Icon(Icons.business_rounded, size: 20, color: _C.primary)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DASHBOARD
// ════════════════════════════════════════════════════════════════════════════

class _OrgDashboardContent extends StatelessWidget {
  final Map<String, dynamic> orgData;
  final List<Map<String, dynamic>> activities;
  final String userRole;
  final VoidCallback onRefresh;
  final void Function(String page, {int tab}) onNavigate;

  const _OrgDashboardContent({required this.orgData, required this.activities, required this.userRole, required this.onRefresh, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final active = activities.where((a) => a['is_archived'] != true).toList();
    final underReview = active.where((a) => isAdviser ? a['status'] == 'Pending' : ['Pending', 'Endorsed'].contains(a['status'])).length;
    final approved = active.where((a) => ['Approved', 'Awaiting Date Approval', 'Reschedule', 'Scheduled'].contains(a['status'])).length;
    final needsCorrection = active.where((a) => a['status'] == 'Needs Revision').length;
    final needsDate = active.where((a) => a['status'] == 'Approved').length;
    final needsReschedule = active.where((a) => a['status'] == 'Reschedule').length;

    final todo = <Widget>[];
    if (isAdviser) {
      final n = active.where((a) => a['status'] == 'Pending').length;
      if (n > 0) todo.add(_ActionRow(icon: Icons.rate_review_rounded, color: _C.warning, text: '$n proposal${n == 1 ? '' : 's'} waiting for your review', button: 'Review', onTap: () => onNavigate('Manage GPOA', tab: 0)));
    } else {
      if (needsCorrection > 0) {
        todo.add(_ActionRow(icon: Icons.edit_note_rounded, color: _C.danger, text: '$needsCorrection proposal${needsCorrection == 1 ? '' : 's'} need${needsCorrection == 1 ? 's' : ''} corrections', button: 'Fix now', onTap: () => onNavigate('Manage GPOA', tab: 2)));
      }
      if (needsDate > 0) {
        todo.add(_ActionRow(icon: Icons.event_rounded, color: _C.warning, text: '$needsDate approved event${needsDate == 1 ? '' : 's'} need a date and letter', button: 'Set date', onTap: () => onNavigate('Manage Events', tab: 0)));
      }
      if (needsReschedule > 0) {
        todo.add(_ActionRow(icon: Icons.event_repeat_rounded, color: _C.danger, text: '$needsReschedule event${needsReschedule == 1 ? '' : 's'} need${needsReschedule == 1 ? 's' : ''} a new date (the date passed without approval)', button: 'Reschedule', onTap: () => onNavigate('Manage Events', tab: 0)));
      }
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(title: 'Welcome back, ${isAdviser ? 'Adviser' : 'President'}', subtitle: 'Here is an overview of ${orgData['name']}.'),
            const SizedBox(height: 28),
            Row(
              children: [
                StatCard(title: 'All proposals', value: active.length.toString(), icon: Icons.assignment_rounded, color: const Color(0xFF3B82F6), onTap: () => onNavigate('Manage GPOA')),
                const SizedBox(width: 16),
                StatCard(title: 'Under review', value: underReview.toString(), icon: Icons.hourglass_top_rounded, color: const Color(0xFFF59E0B), onTap: () => onNavigate('Manage GPOA', tab: 0)),
                const SizedBox(width: 16),
                StatCard(title: 'Approved', value: approved.toString(), icon: Icons.verified_rounded, color: const Color(0xFF10B981), onTap: () => onNavigate('Manage GPOA', tab: 1)),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: _box(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What needs your attention', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
                  const SizedBox(height: 12),
                  if (todo.isEmpty)
                    const Row(children: [
                      Icon(Icons.check_circle_rounded, color: _C.success, size: 20),
                      SizedBox(width: 10),
                      Text('You are all caught up. Nothing needs action right now.', style: TextStyle(color: _C.muted, fontSize: 14)),
                    ])
                  else
                    ...todo,
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('Recent proposals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _C.text)),
                        const Spacer(),
                        TextButton(onPressed: () => onNavigate('Manage GPOA'), child: const Text('View all')),
                      ]),
                      const SizedBox(height: 12),
                      if (active.isEmpty)
                        Container(
                          width: double.infinity,
                          decoration: _box(),
                          child: _EmptyState(
                            icon: Icons.inventory_2_outlined,
                            text: 'No proposals yet.',
                            hint: isAdviser ? 'Proposals from your organization will appear here.' : 'Go to GPOA Proposals and tap "New proposal" to start.',
                          ),
                        )
                      else
                        for (final a in active.take(5))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ItemCard(
                              icon: Icons.description_rounded,
                              title: a['title'] ?? 'Untitled',
                              onTap: () => _showActivityDialog(context, a),
                              body: [
                                Text(a['subtitle'] ?? a['sdgs'] ?? 'GPOA activity', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _C.muted)),
                                _meta('Submitted ${AppUtils.formatDateTime(a['created_at'])}', color: _C.faint),
                              ],
                              actions: [StatusBadge(status: a['status'])],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(flex: 1, child: _OrgStandingCard(orgName: orgData['name']?.toString() ?? 'Organization')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text, button;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.color, required this.text, required this.button, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _C.text))),
        TextButton(onPressed: onTap, child: Text(button)),
      ]),
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
  String _schoolYear = '2025-2026';
  Map<String, dynamic>? _standing;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    SchoolYearService.current().then((sy) {
      if (!mounted) return;
      setState(() => _schoolYear = sy);
      _loadStanding();
    });
  }

  Future<void> _loadStanding() async {
    try {
      final result = await Supabase.instance.client.rpc('get_my_organization_ranking', params: {'p_school_year': _schoolYear});
      if (!mounted) return;
      setState(() {
        _standing = result is List && result.isNotEmpty ? Map<String, dynamic>.from(result.first as Map) : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawRating = _standing?['adjectival_rating']?.toString() ?? 'Pending Evaluation';
    final rating = rawRating.contains('|') ? rawRating.split('|').first : rawRating;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.star_rounded, color: _C.primary, size: 20),
            SizedBox(width: 10),
            Text('Evaluation score', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
          ]),
          const SizedBox(height: 4),
          Text('School year $_schoolYear', style: const TextStyle(fontSize: 12, color: _C.muted)),
          const SizedBox(height: 24),
          Text(
            _isLoading
                ? 'Loading…'
                : _standing == null
                ? 'No score yet'
                : '${(((_standing!['grand_total'] as num?)?.toDouble()) ?? 0).toStringAsFixed(2)} pts',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _C.primary),
          ),
          if (_standing != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: _C.primarySoft, borderRadius: BorderRadius.circular(8)),
              child: Text(rating, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.primary)),
            ),
          ],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  NEW PROPOSAL FORM
// ════════════════════════════════════════════════════════════════════════════

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
  final List<Map<String, dynamic>> _drafts = []; // proposals waiting to be sent
  int? _editingIndex;
  int _formVersion = 0; // changing it rebuilds the time-frame widget
  final List<String> _selectedTypes = [];
  final List<String> _selectedSDGs = [];
  final List<String> _selectedParticipants = [];
  final List<String> _selectedPersons = [];
  final List<String> _selectedFacilities = [];
  final List<String> _selectedMaterials = [];
  final Map<String, TextEditingController> _controllers = {
    'title': TextEditingController(),
    'objectives': TextEditingController(),
    'outcome': TextEditingController(),
    'timeFrame': TextEditingController(),
    'delivery': TextEditingController(),
    'budget': TextEditingController(),
  };
  bool _isSubmitting = false;

  String get _draftsKey => 'gpoa_drafts_${widget.orgId}';

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_draftsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() => _drafts..clear()..addAll(list));
    } catch (_) {}
  }

  Future<void> _saveDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_drafts.isEmpty) {
        await prefs.remove(_draftsKey);
      } else {
        await prefs.setString(_draftsKey, jsonEncode(_drafts));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validateForm() {
    if (!_formKey.currentState!.validate()) {
      AppUtils.showTopToast(context, 'Please fill in the highlighted fields.', isError: true);
      return false;
    }
    final checks = <(bool, String)>[
      (_selectedTypes.isEmpty, 'Please choose at least one activity type.'),
      (_selectedSDGs.isEmpty, 'Please choose at least one SDG.'),
      (_selectedParticipants.isEmpty, 'Please choose who will participate.'),
      (_selectedPersons.isEmpty, 'Please choose who is involved in organizing.'),
      (_selectedFacilities.isEmpty && _selectedMaterials.isEmpty, 'Please choose facilities or materials needed.'),
    ];
    for (final c in checks) {
      if (c.$1) {
        AppUtils.showTopToast(context, c.$2, isError: true);
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _collect() => {
    'organization_id': widget.orgId,
    'title': _controllers['title']!.text.trim(),
    'subtitle': _selectedTypes.isEmpty ? 'General Activities' : _selectedTypes.first,
    'description': _controllers['objectives']!.text,
    'sdgs': _selectedSDGs.join(', '),
    'objectives': _controllers['objectives']!.text,
    'outcome': _controllers['outcome']!.text,
    'participants': _selectedParticipants.join(', '),
    'time_frame': _controllers['timeFrame']!.text,
    'delivery_strategy': _controllers['delivery']!.text,
    'persons_involved': _selectedPersons.join(', '),
    'facilities_materials': _combineFacilitiesAndMaterials(_selectedFacilities, _selectedMaterials),
    'budget_allocation': _controllers['budget']!.text,
    'status': 'Pending',
    'proposed_date': null,
  };

  void _clearForm() {
    _formKey.currentState?.reset();
    for (final c in _controllers.values) {
      c.clear();
    }
    _selectedTypes.clear();
    _selectedSDGs.clear();
    _selectedParticipants.clear();
    _selectedPersons.clear();
    _selectedFacilities.clear();
    _selectedMaterials.clear();
    _editingIndex = null;
    _formVersion++;
  }

  void _addToBatch() {
    if (!_validateForm()) return;
    final row = _collect();
    setState(() {
      if (_editingIndex != null) {
        _drafts[_editingIndex!] = row;
      } else {
        _drafts.add(row);
      }
      _clearForm();
    });
    _saveDrafts();
    AppUtils.showTopToast(context, 'Added. You have ${_drafts.length} proposal${_drafts.length == 1 ? '' : 's'} ready to submit.');
  }

  void _viewDraft(int i) {
    // Drafts have no created_at yet, so use "now" for the preview only.
    final d = {..._drafts[i], 'created_at': DateTime.now().toIso8601String()};
    showDialog(
      context: context,
      builder: (ctx) => _DialogFrame(
        title: 'Proposal preview',
        subtitle: d['title']?.toString(),
        maxWidth: 900,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: _outlineBtn(_C.muted),
            child: const Text('Close'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _editDraft(i);
            },
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text('Edit this proposal'),
            style: _filledBtn(),
          ),
        ],
        child: _detailsView(d),
      ),
    );
  }

  void _editDraft(int i) {
    final d = _drafts[i];
    _formKey.currentState?.reset();
    setState(() {
      _controllers['title']!.text = d['title'] ?? '';
      _controllers['objectives']!.text = d['objectives'] ?? '';
      _controllers['outcome']!.text = d['outcome'] ?? '';
      _controllers['timeFrame']!.text = d['time_frame'] ?? '';
      _controllers['delivery']!.text = d['delivery_strategy'] ?? '';
      _controllers['budget']!.text = d['budget_allocation'] ?? '';
      _selectedTypes..clear()..addAll(_matchOptions(d['subtitle'], _activityTypesFor(widget.orgType)));
      _selectedSDGs..clear()..addAll(_matchOptions(d['sdgs'], _sdgOptions));
      _selectedParticipants..clear()..addAll(_splitList(d['participants']));
      _selectedPersons..clear()..addAll(_splitList(d['persons_involved']));
      _parseFacilitiesAndMaterials(d['facilities_materials'], _selectedFacilities, _selectedMaterials);
      _editingIndex = i;
      _formVersion++;
    });
  }

  Future<void> _leave() async => widget.onBack();

  Future<void> _submitAll() async {
    if (_drafts.isEmpty) {
      AppUtils.showTopToast(context, 'Add at least one proposal first.', isError: true);
      return;
    }
    if (_controllers['title']!.text.trim().isNotEmpty) {
      AppUtils.showTopToast(context, 'The form has a proposal that is not added yet. Tap "Add to list" first, or clear it.', isError: true);
      return;
    }
    final ok = await _confirmBulk(context, 'Submit ${_drafts.length} proposal${_drafts.length == 1 ? '' : 's'}?',
        'All of them will be sent to your adviser at once.', 'Submit all');
    if (!ok || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.from('activities').insert(_drafts); // one request for the whole batch
      AppUtils.sendNotification(
        title: 'New GPOA Proposals 📝',
        body: '${_drafts.length} proposal${_drafts.length == 1 ? '' : 's'} submitted and waiting for your review.',
        recipientRole: 'adviser',
        organizationId: widget.orgId,
      );
      if (!mounted) return;
      AppUtils.showTopToast(context, '${_drafts.length} proposals submitted successfully.');
      _drafts.clear();
      await _saveDrafts();
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Could not submit: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _field(String label, String key, IconData icon, {int maxLines = 1, bool numeric = false, String? hint}) {
    return TextFormField(
      controller: _controllers[key],
      maxLines: maxLines,
      keyboardType: numeric ? TextInputType.number : TextInputType.multiline,
      inputFormatters: numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(fontSize: 14, color: _C.text),
      decoration: _input(label, icon: icon, hint: hint),
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _draftList() {
    return _FormSection(
      title: 'Ready to submit (${_drafts.length})',
      subtitle: 'These are not sent yet. Add as many as you need, then tap "Submit all".',
      icon: Icons.playlist_add_check_rounded,
      child: Column(
        children: [
          for (var i = 0; i < _drafts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ItemCard(
                icon: Icons.description_rounded,
                color: _editingIndex == i ? _C.warning : _C.primary,
                title: '${i + 1}. ${_drafts[i]['title']}',
                onTap: () => _viewDraft(i),
                body: [_meta('${_drafts[i]['subtitle']} · ₱${_drafts[i]['budget_allocation']}')],
                actions: [
                  IconButton(tooltip: 'View details', icon: const Icon(Icons.visibility_rounded, color: _C.muted), onPressed: () => _viewDraft(i)),
                  IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded, color: _C.primary), onPressed: () => _editDraft(i)),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded, color: _C.danger),
                    onPressed: () {
                      setState(() {
                        _drafts.removeAt(i);
                        if (_editingIndex == i) {
                          _clearForm();
                        } else if (_editingIndex != null && _editingIndex! > i) {
                          _editingIndex = _editingIndex! - 1;
                        }
                      });
                      _saveDrafts();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = _activityTypesFor(widget.orgType);
    final editing = _editingIndex != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PageHeader(
                title: 'New GPOA proposals',
                subtitle: 'Fill in one proposal, tap "Add to list", repeat. Then submit them all together.',
                onBack: _leave,
              ),
              const SizedBox(height: 28),
              if (_drafts.isNotEmpty) ...[_draftList(), const SizedBox(height: 20)],
              if (editing)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _C.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Text('Editing proposal ${_editingIndex! + 1}. Tap "Update proposal" to save your changes.',
                      style: const TextStyle(fontSize: 13, color: _C.text)),
                ),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _FormSection(
                      title: '1. Basic information',
                      subtitle: 'What is the activity called, and what kind of activity is it?',
                      icon: Icons.info_outline_rounded,
                      child: Column(children: [
                        _field('Activity title', 'title', Icons.title_rounded),
                        const SizedBox(height: 20),
                        _MultiSelectField(
                          label: 'Activity type',
                          hint: 'Tap to choose an activity type',
                          icon: Icons.category_rounded,
                          items: _selectedTypes,
                          onTap: () => _pickSingle(context, title: 'Choose activity type', options: types, selected: _selectedTypes, onChanged: () => setState(() {})),
                          onRemove: (s) => setState(() => _selectedTypes.remove(s)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _FormSection(
                      title: '2. Goals',
                      subtitle: 'Why are you doing this, and what do you expect to achieve?',
                      icon: Icons.flag_rounded,
                      child: Column(children: [
                        _MultiSelectField(
                          label: 'Sustainable Development Goals (SDGs)',
                          hint: 'Tap to choose one or more SDGs',
                          icon: Icons.public_rounded,
                          items: _selectedSDGs,
                          chipText: (s) => s.split(':').first,
                          onTap: () => _pickMultiple(context, title: 'Choose SDGs', options: _sdgOptions, selected: _selectedSDGs, onChanged: () => setState(() {})),
                          onRemove: (s) => setState(() => _selectedSDGs.remove(s)),
                        ),
                        const SizedBox(height: 20),
                        _field('Objectives', 'objectives', Icons.flag_rounded, maxLines: 4, hint: 'What does this activity aim to do?'),
                        const SizedBox(height: 20),
                        _field('Expected outcome', 'outcome', Icons.stars_rounded, maxLines: 4, hint: 'What result do you expect after the activity?'),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _FormSection(
                      title: '3. Plan and resources',
                      subtitle: 'Who is involved, how long it will take, and what you need.',
                      icon: Icons.rocket_launch_rounded,
                      child: Column(children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: _TimeFrameInput(key: ValueKey('tf$_formVersion'), controller: _controllers['timeFrame']!)),
                          const SizedBox(width: 16),
                          Expanded(child: Padding(padding: const EdgeInsets.only(top: 26), child: _field('Budget (₱)', 'budget', Icons.payments_rounded, numeric: true, hint: 'Numbers only'))),
                        ]),
                        const SizedBox(height: 20),
                        _MultiSelectField(
                          label: 'Who will attend? (Target participants)',
                          hint: 'Tap to choose who the activity is for',
                          icon: Icons.groups_rounded,
                          items: _selectedParticipants,
                          onTap: () => _pickGrouped(context,
                              title: 'Who will attend?',
                              intro: 'Choose the people this activity is meant for. You can pick more than one.',
                              groups: _participantGroups,
                              help: _participantHelp,
                              selected: _selectedParticipants,
                              onChanged: () => setState(() {})),
                          onRemove: (s) => setState(() => _selectedParticipants.remove(s)),
                        ),
                        const SizedBox(height: 20),
                        _MultiSelectField(
                          label: 'Who will organize or help? (Persons involved)',
                          hint: 'Tap to choose the people running the activity',
                          icon: Icons.people_alt_rounded,
                          items: _selectedPersons,
                          onTap: () => _pickGrouped(context,
                              title: 'Who will organize or help?',
                              intro: 'Choose the people who will help run this activity. These are not the attendees.',
                              groups: _personsGroups,
                              help: _personsHelp,
                              selected: _selectedPersons,
                              onChanged: () => setState(() {})),
                          onRemove: (s) => setState(() => _selectedPersons.remove(s)),
                        ),
                        const SizedBox(height: 20),
                        _field('Delivery strategy', 'delivery', Icons.map_rounded, maxLines: 4, hint: 'How will you carry out the activity?'),
                        const SizedBox(height: 20),
                        _MultiSelectField(
                          label: 'Facilities / Venues needed',
                          hint: 'Tap to choose venue/facilities (e.g. AVR, Gym, Classroom)',
                          icon: Icons.business_rounded,
                          items: _selectedFacilities,
                          onTap: () => _pickFacilities(context, selected: _selectedFacilities, onChanged: () => setState(() {})),
                          onRemove: (s) => setState(() => _selectedFacilities.remove(s)),
                        ),
                        const SizedBox(height: 20),
                        _MultiSelectField(
                          label: 'Materials & Equipment needed',
                          hint: 'Tap to choose equipment and supplies (e.g. Sound system, Projector)',
                          icon: Icons.inventory_2_rounded,
                          items: _selectedMaterials,
                          onTap: () => _pickMaterials(context, selected: _selectedMaterials, onChanged: () => setState(() {})),
                          onRemove: (s) => setState(() => _selectedMaterials.remove(s)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(onPressed: _isSubmitting ? null : _leave, style: _outlineBtn(_C.muted), child: const Text('Cancel')),
                        if (editing)
                          OutlinedButton(onPressed: () => setState(_clearForm), style: _outlineBtn(_C.muted), child: const Text('Discard changes')),
                        OutlinedButton.icon(
                          onPressed: _isSubmitting ? null : _addToBatch,
                          icon: Icon(editing ? Icons.check_rounded : Icons.add_rounded, size: 18),
                          label: Text(editing ? 'Update proposal' : 'Add to list'),
                          style: _outlineBtn(),
                        ),
                        ElevatedButton.icon(
                          onPressed: (_isSubmitting || _drafts.isEmpty) ? null : _submitAll,
                          style: _filledBtn(),
                          icon: _isSubmitting
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text('Submit all (${_drafts.length})'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 60),
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
const _facilityOptions = [
  'Audio Visual Room (AVR)',
  'Campus Gymnasium',
  'Covered Court',
  'Student Center / Lobby',
  'College Classrooms',
  'Computer Laboratory',
  'Science Laboratory',
  'Conference Hall',
  'Campus Oval / Open Grounds',
  'Library Conference Area',
  'University Auditorium',
];

const _materialOptions = [
  'Sound system and wireless microphones',
  'LCD Projector and projection screen',
  'Monoblock chairs',
  'Long tables',
  'Extension cords and power strips',
  'Whiteboard and markers',
  'Stage setup and podium',
  'Banners / Tarpaulins',
  'Laptops / Computers',
  'First aid kit and medical supplies',
  'Registration tables and supplies',
];

String _combineFacilitiesAndMaterials(List<String> facilities, List<String> materials) {
  final parts = <String>[];
  if (facilities.isNotEmpty) {
    parts.add('Facilities: ${facilities.join(', ')}');
  }
  if (materials.isNotEmpty) {
    parts.add('Materials: ${materials.join(', ')}');
  }
  return parts.isEmpty ? 'None specified' : parts.join(' | ');
}

void _parseFacilitiesAndMaterials(dynamic raw, List<String> facilities, List<String> materials) {
  facilities.clear();
  materials.clear();
  final text = raw?.toString() ?? '';
  if (text.trim().isEmpty) return;

  if (text.contains('Facilities:') || text.contains('Materials:')) {
    final parts = text.split('|');
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.startsWith('Facilities:')) {
        final val = trimmed.replaceFirst('Facilities:', '').trim();
        if (val.isNotEmpty && val != 'None specified') {
          facilities.addAll(val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
        }
      } else if (trimmed.startsWith('Materials:')) {
        final val = trimmed.replaceFirst('Materials:', '').trim();
        if (val.isNotEmpty && val != 'None specified') {
          materials.addAll(val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
        }
      }
    }
  } else {
    final items = text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    for (final item in items) {
      if (_facilityOptions.contains(item)) {
        facilities.add(item);
      } else {
        materials.add(item);
      }
    }
  }
}

Future<void> _pickFacilities(
  BuildContext context, {
  required List<String> selected,
  required VoidCallback onChanged,
}) {
  return _pickMultiple(
    context,
    title: 'Choose facilities / venues',
    options: _facilityOptions,
    selected: selected,
    onChanged: onChanged,
  );
}

Future<void> _pickMaterials(
  BuildContext context, {
  required List<String> selected,
  required VoidCallback onChanged,
}) {
  return _pickMultiple(
    context,
    title: 'Choose materials & equipment',
    options: _materialOptions,
    selected: selected,
    onChanged: onChanged,
  );
}
class _TimeFrameInput extends StatefulWidget {
  final TextEditingController controller;
  const _TimeFrameInput({super.key, required this.controller});

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
    _unit = raw.toLowerCase().contains('day') ? 'Days' : 'Hours';
    final match = RegExp(r'(\d+)').firstMatch(raw);
    _numberController = TextEditingController(text: match != null ? match.group(1) : '2');
    _updateParent(); // make sure the saved value matches what the user sees
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  void _updateParent() {
    final n = int.tryParse(_numberController.text.trim()) ?? 2;
    widget.controller.text = n == 1 ? (_unit == 'Days' ? '1 Day' : '1 Hour') : '$n $_unit';
  }

  bool _isPreset(String n, String u) => _numberController.text == n && _unit == u;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Time Frame', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _C.body)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _input('Duration', icon: Icons.timer_rounded),
                onChanged: (_) {
                  setState(() {});
                  _updateParent();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: _input('Unit'),
                items: const [DropdownMenuItem(value: 'Hours', child: Text('Hours')), DropdownMenuItem(value: 'Days', child: Text('Days'))],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _unit = v);
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
            _chip('2 Hours', '2', 'Hours'),
            _chip('4 Hours', '4', 'Hours'),
            _chip('8 Hours', '8', 'Hours'),
            _chip('1 Day', '1', 'Days'),
            _chip('2 Days', '2', 'Days'),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, String n, String u) {
    final sel = _isPreset(n, u);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: sel ? Colors.white : _C.body)),
      selected: sel,
      showCheckmark: false,
      selectedColor: _C.primary,
      backgroundColor: Colors.white,
      side: const BorderSide(color: _C.border),
      onSelected: (s) {
        if (s) {
          setState(() {
            _numberController.text = n;
            _unit = u;
          });
          _updateParent();
        }
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  EVENTS & SCHEDULE
// ════════════════════════════════════════════════════════════════════════════

class _OrgManageEventsView extends StatefulWidget {
  final String orgId;
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;
  final VoidCallback onGoToReports;
  final String userRole;
  final int initialTab;
  const _OrgManageEventsView({required this.orgId, required this.activities, required this.onRefresh, required this.onGoToReports, required this.userRole, this.initialTab = 0});

  @override
  State<_OrgManageEventsView> createState() => _OrgManageEventsViewState();
}

class _OrgManageEventsViewState extends State<_OrgManageEventsView> {
  static const _approvedWords = ['approved', 'completed', 'verified', 'passed'];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _campusEvents = [];
  bool _loaded = false;
  bool _campusEventsLoaded = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadReports();
    _loadCampusEvents();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadReports();
      _loadCampusEvents();
    });
  }

  @override
  void didUpdateWidget(covariant _OrgManageEventsView old) {
    super.didUpdateWidget(old);
    if (old.activities != widget.activities) {
      _loadReports();
      _loadCampusEvents();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadReports() async {
    try {
      final res = await Supabase.instance.client.from('accomplishment_reports').select('id, activity_id, status').eq('organization_id', widget.orgId);
      if (!mounted) return;
      setState(() {
        _reports = List<Map<String, dynamic>>.from(res);
        _loaded = true;
      });
    } catch (_) {}
  }

  // A restricted RPC returns only fields needed for the shared campus schedule.
  // It lets presidents see cross-organization date conflicts without exposing full proposals.
  Future<void> _loadCampusEvents() async {
    try {
      final res = await Supabase.instance.client.rpc('get_campus_event_calendar');
      if (!mounted) return;
      setState(() {
        _campusEvents = (res as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _campusEventsLoaded = true;
      });
    } catch (e) {
      debugPrint('Campus event calendar load failed: $e');
      if (mounted) setState(() => _campusEventsLoaded = false);
    }
  }

  /// Finished events whose accomplishment report is missing or not approved yet.
  List<Map<String, dynamic>> get _blockers {
    if (!_loaded) return [];
    return widget.activities.where((a) {
      final s = a['status']?.toString();
      if (!['Scheduled', 'Completed'].contains(s)) return false;
      if (!(s == 'Completed' || AppUtils.isEventDone(a))) return false;
      final matches = _reports.where((r) => r['activity_id']?.toString() == a['id']?.toString());
      if (matches.isEmpty) return true;
      return !_approvedWords.contains((matches.first['status'] ?? '').toString().toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _OrgManageEventsBody(
      activities: widget.activities,
      onRefresh: widget.onRefresh,
      userRole: widget.userRole,
      initialTab: widget.initialTab,
      blockers: _blockers,
      campusEvents: _campusEvents,
      campusEventsLoaded: _campusEventsLoaded,
      onGoToReports: widget.onGoToReports,
    );
  }
}

class _OrgManageEventsBody extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final VoidCallback onRefresh;
  final String userRole;
  final int initialTab;
  final List<Map<String, dynamic>> blockers;
  final List<Map<String, dynamic>> campusEvents;
  final bool campusEventsLoaded;
  final VoidCallback onGoToReports;
  const _OrgManageEventsBody({required this.activities, required this.onRefresh, required this.userRole, required this.blockers, required this.campusEvents, required this.campusEventsLoaded, required this.onGoToReports, this.initialTab = 0});

  Widget _blockedBanner() {
    final names = blockers.take(3).map((a) => '"${a['title'] ?? 'Untitled'}"').join(', ');
    final more = blockers.length > 3 ? ' and ${blockers.length - 3} more' : '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _C.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.warning.withValues(alpha: 0.35))),
      child: Row(children: [
        const Icon(Icons.lock_clock_rounded, color: _C.warning, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'You cannot schedule a new event yet. The accomplishment report for $names$more must be approved first.',
            style: const TextStyle(fontSize: 13.5, color: _C.text, fontWeight: FontWeight.w500),
          ),
        ),
        TextButton(onPressed: onGoToReports, child: const Text('Open reports')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final active = activities.where((a) => a['is_archived'] != true);
    final schedulingList = active.where((a) => ['Approved', 'Awaiting Date Approval', 'Reschedule'].contains(a['status'])).toList();
    final revisionList = active.where((a) => a['status'] == 'Needs Revision').toList();
    final scheduledList = active.where((a) => a['status'] == 'Scheduled').toList()
      ..sort((a, b) {
        final rawA = a['proposed_date']?.toString().trim() ?? '';
        final rawB = b['proposed_date']?.toString().trim() ?? '';
        final startA = DateTime.tryParse(rawA)?.toLocal() ?? DateTime(2100);
        final startB = DateTime.tryParse(rawB)?.toLocal() ?? DateTime(2100);
        return startA.compareTo(startB);
      });

    return DefaultTabController(
      length: 3,
      initialIndex: initialTab > 2 ? 0 : initialTab,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              title: isAdviser ? 'Event calendar' : 'Events & schedule',
              subtitle: isAdviser ? 'Follow the schedule and approval status of your organization\'s events.' : 'For each approved proposal: attach the letter and concept paper, pick a date, then submit for approval.',
            ),
            const SizedBox(height: 24),
            _Tabs(labels: ['Date & letter (${schedulingList.length})', 'Needs correction (${revisionList.length})', 'Scheduled events (${scheduledList.length})']),
            const SizedBox(height: 20),
            Expanded(
              child: TabBarView(
                children: [
                  (blockers.isEmpty || isAdviser)
                      ? _buildList(context, schedulingList, 'scheduling')
                      : Column(children: [_blockedBanner(), Expanded(child: _buildList(context, schedulingList, 'scheduling'))]),
                  _buildList(context, revisionList, 'corrections'),
                  _buildList(context, scheduledList, 'letters'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }




  bool _dateIsFuture(Map<String, dynamic> e) {
    final d = DateTime.tryParse(e['proposed_date']?.toString() ?? '');
    return d != null && d.toLocal().isAfter(DateTime.now());
  }

  Widget _buildList(BuildContext context, List<Map<String, dynamic>> list, String tabType) {
    final isAdviser = userRole == 'Adviser';
    if (list.isEmpty) {
      switch (tabType) {
        case 'scheduling':
          return const _EmptyState(icon: Icons.calendar_today_outlined, text: 'Nothing to schedule yet.', hint: 'Approved proposals will appear here so you can set a date and attach a letter.');
        case 'corrections':
          return const _EmptyState(icon: Icons.check_circle_outline_rounded, text: 'No corrections needed.');
        default:
          return const _EmptyState(icon: Icons.mail_outline_rounded, text: 'No scheduled events yet.');
      }
    }

    if (tabType == 'scheduling') {
      final Map<String, List<Map<String, dynamic>>> categories = {};
      for (final event in list) {
        final rawSubtitle = (event['subtitle'] ?? '').toString().trim();
        final List<String> parsedTypes = rawSubtitle.isEmpty
            ? ['General Activities']
            : rawSubtitle
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();

        final cleanTypes = parsedTypes.isEmpty ? ['General Activities'] : parsedTypes;

        for (final type in cleanTypes) {
          categories.putIfAbsent(type, () => []).add(event);
        }
      }

      return ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, catIndex) {
          final categoryName = categories.keys.elementAt(catIndex);
          final categoryEvents = categories[categoryName]!;

          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _C.border),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))
              ],
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _C.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.category_rounded, color: _C.primary, size: 20),
                ),
                title: Text(
                  categoryName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _C.text),
                ),
                subtitle: Text(
                  '${categoryEvents.length} event${categoryEvents.length == 1 ? '' : 's'} available to schedule',
                  style: const TextStyle(fontSize: 12, color: _C.muted),
                ),
                childrenPadding: const EdgeInsets.all(16),
                children: categoryEvents.map((event) {
                  final status = event['status'];
                  final hasDate = event['proposed_date'] != null && event['proposed_date'].toString().trim().isNotEmpty;
                  final hasLetter = event['letter_url'] != null && event['letter_url'].toString().trim().isNotEmpty;
                  final isReschedule = status == 'Reschedule';
                  final hasConcept = event['concept_paper_url'] != null && event['concept_paper_url'].toString().trim().isNotEmpty;
                  final dateReady = hasDate && (!isReschedule || _dateIsFuture(event));
                  final rejected = (status == 'Approved' || isReschedule) && (event['remarks']?.toString().trim().isNotEmpty ?? false);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: _ItemCard(
                      icon: status == 'Scheduled' ? Icons.event_available_rounded : Icons.event_rounded,
                      color: status == 'Scheduled' ? _C.success : _C.primary,
                      title: event['title'] ?? 'Untitled',
                      body: [
                        _statusLine(status),
                        _meta(
                          !hasDate
                              ? 'No date selected yet'
                              : (isReschedule && !dateReady)
                              ? 'Previous date passed: ${AppUtils.formatEventRange(event['proposed_date'], event['time_frame'])}'
                              : 'Date: ${AppUtils.formatEventRange(event['proposed_date'], event['time_frame'])}',
                          color: dateReady ? _C.body : _C.danger,
                          bold: true,
                        ),
                        if (status == 'Approved' || isReschedule)
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _ChecklistChip('Letter', hasLetter),
                              _ChecklistChip('Concept paper', hasConcept),
                              _ChecklistChip('Date', dateReady),
                            ],
                          ),
                        if (rejected)
                          _meta(
                            isReschedule ? '${event['remarks']}' : 'Date was not approved: ${event['remarks']}',
                            color: _C.danger,
                            bold: true,
                          ),
                      ],
                      actions: [
                        IconButton(
                          tooltip: 'View details',
                          onPressed: () => _showActivityDialog(context, event),
                          icon: const Icon(Icons.info_outline_rounded, color: _C.muted),
                        ),
                        if (!isAdviser) ..._actions(context, event),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = list[index];
        final status = event['status'];
        final hasDate = event['proposed_date'] != null && event['proposed_date'].toString().trim().isNotEmpty;
        final hasLetter = event['letter_url'] != null && event['letter_url'].toString().trim().isNotEmpty;
        final isReschedule = status == 'Reschedule';
        final hasConcept = event['concept_paper_url'] != null && event['concept_paper_url'].toString().trim().isNotEmpty;
        final dateReady = hasDate && (!isReschedule || _dateIsFuture(event));
        final rejected = (status == 'Approved' || isReschedule) && (event['remarks']?.toString().trim().isNotEmpty ?? false);

        return _ItemCard(
          icon: status == 'Scheduled' ? Icons.event_available_rounded : Icons.event_rounded,
          color: status == 'Scheduled' ? _C.success : _C.primary,
          title: event['title'] ?? 'Untitled',
          body: [
            _statusLine(status),
            _meta(
              !hasDate
                  ? 'No date selected yet'
                  : (isReschedule && !dateReady)
                  ? 'Previous date passed: ${AppUtils.formatEventRange(event['proposed_date'], event['time_frame'])}'
                  : 'Date: ${AppUtils.formatEventRange(event['proposed_date'], event['time_frame'])}',
              color: dateReady ? _C.body : _C.danger,
              bold: true,
            ),
            if (status == 'Approved' || isReschedule) Wrap(spacing: 8, runSpacing: 6, children: [_ChecklistChip('Letter', hasLetter), _ChecklistChip('Concept paper', hasConcept), _ChecklistChip('Date', dateReady)]),
            if (rejected) _meta(isReschedule ? '${event['remarks']}' : 'Date was not approved: ${event['remarks']}', color: _C.danger, bold: true),
          ],
          actions: [
            IconButton(tooltip: 'View details', onPressed: () => _showActivityDialog(context, event), icon: const Icon(Icons.info_outline_rounded, color: _C.muted)),
            if (!isAdviser) ..._actions(context, event),
          ],
        );
      },
    );
  }

  List<Widget> _actions(BuildContext context, Map<String, dynamic> event) {
    final status = event['status'];
    final hasDate = event['proposed_date'] != null && event['proposed_date'].toString().trim().isNotEmpty;
    final hasLetter = event['letter_url'] != null && event['letter_url'].toString().trim().isNotEmpty;
    final hasConcept = event['concept_paper_url'] != null && event['concept_paper_url'].toString().trim().isNotEmpty;

    final viewLetter = IconButton(
      tooltip: 'View letter',
      icon: const Icon(Icons.file_present_rounded, color: _C.primary),
      onPressed: () async {
        final ok = await StorageUtils.open(event['letter_url'].toString());
        if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the letter.', isError: true);
      },
    );

    final viewConcept = IconButton(
      tooltip: 'View concept paper',
      icon: const Icon(Icons.description_outlined, color: _C.primary),
      onPressed: () async {
        final ok = await StorageUtils.open(event['concept_paper_url'].toString());
        if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the concept paper.', isError: true);
      },
    );

    if (status == 'Needs Revision') {
      return [
        ElevatedButton.icon(
          onPressed: () => showDialog(context: context, builder: (_) => _ReviseActivityDialog(activity: event, userRole: userRole, onRefreshed: onRefresh)),
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Revise proposal'),
          style: _filledBtn(_C.warning),
        ),
      ];
    }

    if (status == 'Approved' || status == 'Reschedule') {
      final docsReady = hasLetter && hasConcept;
      final dateReady = hasDate && (status != 'Reschedule' || _dateIsFuture(event));
      final canSubmit = dateReady && docsReady && blockers.isEmpty;
      return [
        if (hasLetter) viewLetter,
        if (hasConcept) viewConcept,
        OutlinedButton.icon(
          onPressed: () => _uploadLetter(context, event),
          icon: Icon(hasLetter ? Icons.sync_rounded : Icons.attach_file_rounded, size: 16),
          label: Text(hasLetter ? 'Replace letter' : 'Attach letter'),
          style: _outlineBtn(),
        ),
        OutlinedButton.icon(
          onPressed: () => _uploadConceptPaper(context, event),
          icon: Icon(hasConcept ? Icons.sync_rounded : Icons.attach_file_rounded, size: 16),
          label: Text(hasConcept ? 'Replace concept paper' : 'Attach concept paper'),
          style: _outlineBtn(),
        ),
        Tooltip(
          message: blockers.isNotEmpty ? 'Get your last accomplishment report approved first' : (docsReady ? '' : 'Attach the letter and concept paper first'),
          child: OutlinedButton.icon(
            onPressed: (blockers.isNotEmpty || !docsReady) ? null : () => _selectDate(context, event, campusEvents),
            icon: const Icon(Icons.edit_calendar_rounded, size: 16),
            label: Text(dateReady ? 'Change date' : 'Pick date'),
            style: _outlineBtn(),
          ),
        ),
        Tooltip(
          message: blockers.isNotEmpty
              ? 'Get your last accomplishment report approved first'
              : (!docsReady ? 'Attach the letter and concept paper first' : (dateReady ? '' : 'Pick a new date first')),
          child: ElevatedButton.icon(
            onPressed: canSubmit
                ? () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Submit for approval?'),
                  content: const Text('The event date, approved letter and concept paper will be sent to OSDW for approval.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: _filledBtn(), child: const Text('Submit')),
                  ],
                ),
              );
              if (confirm == true && context.mounted) _requestDateApproval(context, event);
            }
                : null,
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Submit'),
            style: _filledBtn(),
          ),
        ),
      ];
    }

    if (status == 'Awaiting Date Approval') {
      return [
        if (hasLetter) viewLetter,
        if (hasConcept) viewConcept,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: _C.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Text('Waiting for OSDW', style: TextStyle(color: _C.warning, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ];
    }

    if (status == 'Scheduled') return [if (hasLetter) viewLetter, if (hasConcept) viewConcept];
    return [];
  }

  Future<void> _uploadLetter(BuildContext context, Map<String, dynamic> event) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: StorageUtils.allowedExtensions, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes ?? await file.xFile.readAsBytes();

      final path = await StorageUtils.upload('letters', file.name, bytes); // stores PATH, not public URL
      await Supabase.instance.client.from('activities').update({'letter_url': path}).eq('id', event['id']);

      if (context.mounted) {
        AppUtils.showTopToast(context, 'Letter attached.');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Upload failed: $e', isError: true);
    }
  }

  Future<void> _uploadConceptPaper(BuildContext context, Map<String, dynamic> event) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: StorageUtils.allowedExtensions, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes ?? await file.xFile.readAsBytes();

      final path = await StorageUtils.upload('letters', 'concept_${file.name}', bytes);
      await Supabase.instance.client.from('activities').update({'concept_paper_url': path}).eq('id', event['id']);

      if (context.mounted) {
        AppUtils.showTopToast(context, 'Concept paper attached.');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Upload failed: $e', isError: true);
    }
  }

  Future<void> _selectDate(BuildContext context, Map<String, dynamic> event, List<Map<String, dynamic>> campusEvents) async {
    if (blockers.isNotEmpty) {
      AppUtils.showTopToast(context, 'Get your last accomplishment report approved first.', isError: true);
      return;
    }
    final hasLetter = event['letter_url'] != null && event['letter_url'].toString().trim().isNotEmpty;
    final hasConcept = event['concept_paper_url'] != null && event['concept_paper_url'].toString().trim().isNotEmpty;
    if (!hasLetter || !hasConcept) {
      AppUtils.showTopToast(context, 'Attach the letter and the concept paper before choosing a date.', isError: true);
      return;
    }
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    DateTime initial = event['proposed_date'] != null ? DateTime.parse(event['proposed_date'].toString()).toLocal() : now;
    if (initial.isBefore(firstDate)) initial = firstDate;

    final picked = await showScheduleCalendar(
      context,
      initial: initial,
      firstDate: firstDate,
      duration: AppUtils.parseDuration(event['time_frame']),
      excludeId: event['id'].toString(),
    );
    if (picked == null || !context.mounted) return;
    final finalDateTime = picked;

    if (!finalDateTime.isAfter(DateTime.now())) {
      AppUtils.showTopToast(context, 'That time has already passed. Please choose a later time.', isError: true);
      return;
    }

    // Warn on any same-day campus event, including pending date requests. The user may still proceed.
    final selectedDay = DateTime(finalDateTime.year, finalDateTime.month, finalDateTime.day);
    final conflicts = campusEvents.where((other) {
      if (other['id']?.toString() == event['id']?.toString()) return false;
      if (other['is_archived'] == true) return false;
      final status = other['status']?.toString() ?? '';
      // Only submitted date requests and accepted schedules should block/warn.
      // Ordinary pending proposals and proposals not yet submitted for date approval are ignored.
      if (!['Awaiting Date Approval', 'Scheduled'].contains(status)) return false;
      final raw = other['proposed_date']?.toString();
      if (raw == null || raw.trim().isEmpty) return false;
      final d = DateTime.tryParse(raw)?.toLocal();
      if (d == null) return false;
      return d.year == selectedDay.year && d.month == selectedDay.month && d.day == selectedDay.day;
    }).toList();

    if (conflicts.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Row(children: [Icon(Icons.warning_amber_rounded, color: _C.warning), SizedBox(width: 8), Expanded(child: Text('Possible date conflict'))]),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${conflicts.length} other event${conflicts.length == 1 ? '' : 's'} already have a date on ${selectedDay.month}/${selectedDay.day}/${selectedDay.year}. You can choose another date or proceed anyway.'),
              const SizedBox(height: 12),
              ...conflicts.map((other) {
                final otherDate = DateTime.tryParse(other['proposed_date']?.toString() ?? '')?.toLocal();
                final org = other['organization_name']?.toString();
                final status = other['status']?.toString() ?? 'Requested';
                return Container(
                  width: double.infinity, margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _C.warning.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.warning.withValues(alpha: 0.25))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(other['title']?.toString() ?? 'Untitled event', style: const TextStyle(fontWeight: FontWeight.w700, color: _C.text)),
                    Text('${org?.isNotEmpty == true ? org : 'Another organization'} · $status', style: const TextStyle(fontSize: 12, color: _C.muted)),
                    if (otherDate != null) Text('Time: ${_fmt12(otherDate)}', style: const TextStyle(fontSize: 12, color: _C.body)),
                  ]),
                );
              }),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Choose another date')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: _filledBtn(_C.warning), child: const Text('Proceed anyway')),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }
    try {
      await Supabase.instance.client.from('activities').update({'proposed_date': finalDateTime.toUtc().toIso8601String()}).eq('id', event['id']);
      if (context.mounted) {
        AppUtils.showTopToast(context, 'Date saved.');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _requestDateApproval(BuildContext context, Map<String, dynamic> event) async {
    if (blockers.isNotEmpty) {
      AppUtils.showTopToast(context, 'Get your last accomplishment report approved first.', isError: true);
      return;
    }
    final hasDate = event['proposed_date'] != null && event['proposed_date'].toString().trim().isNotEmpty;
    final hasLetter = event['letter_url'] != null && event['letter_url'].toString().trim().isNotEmpty;
    final hasConcept = event['concept_paper_url'] != null && event['concept_paper_url'].toString().trim().isNotEmpty;
    if (!hasDate || !hasLetter || !hasConcept) {
      AppUtils.showTopToast(context, 'Attach the letter and concept paper, then pick a date first.', isError: true);
      return;
    }
    try {
      final d = DateTime.tryParse(event['proposed_date'].toString());
      if (d == null || !d.toLocal().isAfter(DateTime.now())) {
        AppUtils.showTopToast(context, 'That date has already passed. Please pick a new date.', isError: true);
        return;
      }
      await Supabase.instance.client.from('activities').update({
        'status': 'Awaiting Date Approval',
        'remarks': null,
        'date_requested_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', event['id']);

      AppUtils.sendNotification(
        title: 'Event Date Submitted 📅',
        body: '"${event['title']}" has a proposed date and approved letter awaiting your review.',
        recipientRole: 'admin',
        organizationId: event['organization_id']?.toString(),
      );

      if (context.mounted) {
        AppUtils.showTopToast(context, 'Submitted for approval.');
        onRefresh();
      }
    } catch (e) {
      if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ACCOMPLISHMENT REPORTS
// ════════════════════════════════════════════════════════════════════════════

class _SubmitReportView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final String userRole;
  final VoidCallback onRefresh;
  const _SubmitReportView({required this.activities, required this.userRole, required this.onRefresh});

  @override
  State<_SubmitReportView> createState() => _SubmitReportViewState();
}

class _SubmitReportViewState extends State<_SubmitReportView> {
  bool _showApprovedFilter = false;
  int _refreshKey = 0;

  static const _approvedWords = ['approved', 'completed', 'verified', 'passed'];

  @override
  Widget build(BuildContext context) {
    final isAdviser = widget.userRole == 'Adviser';

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: isAdviser ? 'Review accomplishment reports' : 'Accomplishment reports',
            subtitle: isAdviser ? 'Approve reports, or return them if something needs to be fixed.' : 'After an event is done, upload the narrative report, photos and receipts.',
          ),
          const SizedBox(height: 24),
          DefaultTabController(
            length: 2,
            child: _Tabs(labels: [isAdviser ? 'Waiting for review' : 'To do / In review', 'Approved'], onTap: (i) => setState(() => _showApprovedFilter = i == 1)),
          ),
          if (_showApprovedFilter)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: _archiveAllApproved,
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Archive all approved'),
                  style: _outlineBtn(),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey('$_showApprovedFilter-$_refreshKey'),
              future: _fetchReports(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final reports = snapshot.data ?? [];

                Map<String, dynamic>? reportFor(Map<String, dynamic> a) {
                  for (final r in reports) {
                    if (r['activity_id']?.toString() == a['id']?.toString()) return r;
                  }
                  return null;
                }

                final filtered = widget.activities.where((a) {
                  final report = reportFor(a);
                  final reportApproved = _approvedWords.contains((report?['status'] ?? '').toString().toLowerCase());
                  if (a['is_archived'] == true && reportApproved) return false; // only hide archived events that are fully done
                  if (report?['is_archived'] == true) return false; // archived: lives in Archives now
                  if (!(AppUtils.isEventDone(a) || report != null)) return false;
                  final approved = _approvedWords.contains((report?['status'] ?? '').toString().toLowerCase());
                  return _showApprovedFilter ? approved : !approved;
                }).toList();

                if (filtered.isEmpty) {
                  return _EmptyState(
                    icon: Icons.assignment_turned_in_outlined,
                    text: _showApprovedFilter ? 'No approved reports yet.' : 'No finished events need a report right now.',
                    hint: _showApprovedFilter ? null : 'Events appear here once their date has passed.',
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final activity = filtered[index];
                    final report = reportFor(activity);
                    final hasReport = report != null;
                    final reportStatus = (report?['status'] ?? 'Pending Submission').toString();
                    final lower = reportStatus.toLowerCase();
                    final isApproved = _approvedWords.contains(lower);
                    final display = isApproved ? 'Approved' : (lower.contains('revision') ? 'Needs Revision' : reportStatus);
                    final hasDate = activity['proposed_date'] != null;

                    return _ItemCard(
                      icon: Icons.assignment_rounded,
                      title: activity['title'] ?? 'Untitled activity',
                      body: [
                        _statusLine(display),
                        _meta('Event date: ${hasDate ? AppUtils.formatEventRange(activity['proposed_date'], activity['time_frame']) : 'Not selected'}', color: hasDate ? _C.body : _C.danger, bold: true),
                      ],
                      actions: [
                        IconButton(tooltip: 'View details', icon: const Icon(Icons.info_outline_rounded, color: _C.muted), onPressed: () => _showActivityDialog(context, activity)),
                        if (hasReport)
                          IconButton(
                            tooltip: 'Open attached files',
                            icon: const Icon(Icons.attach_file_rounded, color: _C.primary),
                            onPressed: () async {
                              final attachments = report['attachments'];
                              if (attachments is List && attachments.isNotEmpty) {
                                final ok = await StorageUtils.open(attachments.first.toString());
                                if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the file.', isError: true);
                              } else {
                                AppUtils.showTopToast(context, 'No attachment available.');
                              }
                            },
                          ),
                        if (hasReport && isApproved)
                          IconButton(
                            tooltip: 'Move to archive',
                            icon: const Icon(Icons.archive_outlined, color: _C.muted),
                            onPressed: () async {
                              try {
                                await UserArchive.setArchived('report', [report['id']], true);
                                if (!context.mounted) return;
                                setState(() => _refreshKey++);
                                AppUtils.showTopToast(context, 'Report moved to archive.');
                              } catch (e) {
                                if (context.mounted) AppUtils.showTopToast(context, 'Could not archive: $e', isError: true);
                              }
                            },
                          ),
                        if (isAdviser && hasReport && !isApproved) ...[
                          ElevatedButton(onPressed: () => _updateReportStatus(report['id'], report, 'Approved'), style: _filledBtn(_C.success), child: const Text('Approve')),
                          OutlinedButton(onPressed: () => _updateReportStatus(report['id'], report, 'Needs Revision'), style: _outlineBtn(_C.danger), child: const Text('Return')),
                        ] else if (!isAdviser && !isApproved)
                          ElevatedButton.icon(
                            onPressed: () => _showSubmitReportModal(context, activity, report),
                            icon: const Icon(Icons.upload_rounded, size: 16),
                            label: Text(hasReport ? 'Update report' : 'Submit report'),
                            style: _filledBtn(),
                          ),
                      ],
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
  Future<void> _archiveAllApproved() async {
    try {
      final reports = await _fetchReports();
      final myActIds = widget.activities.map((a) => a['id']?.toString()).toSet();
      final ids = reports
          .where((r) => r['is_archived'] != true && myActIds.contains(r['activity_id']?.toString()) && _approvedWords.contains((r['status'] ?? '').toString().toLowerCase()))
          .map((r) => r['id'])
          .toList();
      if (ids.isEmpty || !mounted) return;
      final ok = await _confirmBulk(context, 'Archive all ${ids.length} approved reports?', 'They will move to Archives. You can restore them there.', 'Archive all');
      if (!mounted || !ok) return;
      await _setArchived('accomplishment_reports', ids, true);
      if (!mounted) return;
      setState(() => _refreshKey++);
      AppUtils.showTopToast(context, '${ids.length} reports moved to archive.');
    } catch (e) {
      if (mounted) AppUtils.showTopToast(context, 'Could not archive: $e', isError: true);
    }
  }

  void _showSubmitReportModal(BuildContext context, Map<String, dynamic> activity, Map<String, dynamic>? existingReport) {
    if (!AppUtils.isEventDone(activity)) {
      AppUtils.showTopToast(context, 'You can submit a report only after the event is done.', isError: true);
      return;
    }
    showDialog(context: context, builder: (_) => _SubmitReportDialog(activity: activity, existingReport: existingReport, onRefresh: widget.onRefresh));
  }

  Future<List<Map<String, dynamic>>> _fetchReports() async {
    final response = await Supabase.instance.client.from('accomplishment_reports').select();
    return UserArchive.decorate(List<Map<String, dynamic>>.from(response), 'report');
  }

  Future<void> _updateReportStatus(dynamic reportId, Map<String, dynamic>? report, String status) async {
    setState(() {
      if (report != null) report['status'] = status;
      _refreshKey++;
    });

    try {
      final statusesToTry = status == 'Approved' ? ['Approved', 'APPROVED', 'Completed', 'Verified'] : [status, status.toUpperCase(), status.toLowerCase()];

      for (var sVal in statusesToTry) {
        try {
          await Supabase.instance.client.from('accomplishment_reports').update({'status': sVal}).eq('id', reportId);
          break;
        } catch (e) {
          if (!e.toString().contains('accomplishment_reports_status_check')) rethrow;
        }
      }

      if (status == 'Approved' && report != null) {
        final actId = report['activity_id'];
        if (actId != null) {
          for (var actStatusVal in ['Completed', 'COMPLETED', 'Approved']) {
            try {
              await Supabase.instance.client.from('activities').update({'status': actStatusVal}).eq('id', actId);
              break;
            } catch (_) {}
          }
        }
      }

      final repOrgId = report?['organization_id']?.toString();
      if (repOrgId != null) {
        final repActId = report?['activity_id']?.toString();
        final repAct = widget.activities.firstWhere((a) => a['id']?.toString() == repActId, orElse: () => <String, dynamic>{});
        final repTitle = (report?['title'] ?? repAct['title'] ?? 'your activity').toString();
        AppUtils.sendNotification(
          title: status == 'Approved' ? 'Accomplishment Report Approved 🎉' : 'Accomplishment Report Returned ↩️',
          body: status == 'Approved'
              ? 'The adviser approved the report for "$repTitle".'
              : 'The adviser returned the report for "$repTitle". Update it and submit again.',
          recipientRole: 'president',
          organizationId: repOrgId,
        );
      }

      widget.onRefresh();
      if (mounted) AppUtils.showTopToast(context, status == 'Approved' ? 'Report approved.' : 'Report returned to the organization.');
    } catch (e) {
      debugPrint('Error updating report status: $e');
      if (mounted) AppUtils.showTopToast(context, 'Could not update the report.', isError: true);
    }
  }
}

class _SubmitReportDialog extends StatefulWidget {
  final Map<String, dynamic> activity;
  final Map<String, dynamic>? existingReport;
  final VoidCallback onRefresh;
  const _SubmitReportDialog({required this.activity, this.existingReport, required this.onRefresh});

  @override
  State<_SubmitReportDialog> createState() => _SubmitReportDialogState();
}

class _SubmitReportDialogState extends State<_SubmitReportDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  final List<PlatformFile> _newFiles = [];
  final List<String> _existingUrls = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final rep = widget.existingReport;
    _titleController = TextEditingController(text: rep?['title']?.toString() ?? 'Accomplishment Report: ${widget.activity['title']}');
    final rawAttach = rep?['attachments'];
    if (rawAttach is List) _existingUrls.addAll(rawAttach.map((e) => e.toString()));
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom,allowedExtensions: ['pdf', 'doc', 'docx', 'zip', 'jpg', 'jpeg', 'png'], allowMultiple: true, withData: true);
    if (result != null && result.files.isNotEmpty) setState(() => _newFiles.addAll(result.files));
  }

  Future<void> _saveReport(List<String> urls, String status) async {
    final data = {
      'title': _titleController.text.trim(),
      'summary': 'Submitted Accomplishment Report',
      'attachments': urls,
      'status': status,
      'report_date': DateTime.now().toIso8601String(),
      'is_archived': false,
    };
    final client = Supabase.instance.client;
    if (widget.existingReport != null) {
      await client.from('accomplishment_reports').update(data).eq('id', widget.existingReport!['id']);
    } else {
      await client.from('accomplishment_reports').insert({
        ...data,
        'organization_id': widget.activity['organization_id'],
        'activity_id': widget.activity['id'],
      });
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_existingUrls.isEmpty && _newFiles.isEmpty) {
      AppUtils.showTopToast(context, 'Please attach at least one file (narrative report, photos or receipts).', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final urls = List<String>.from(_existingUrls);

      for (final file in _newFiles) {
        final bytes = file.bytes ?? await file.xFile.readAsBytes();
        urls.add(await StorageUtils.upload('reports/${widget.activity['id']}', file.name, bytes));
      }

      try {
        await _saveReport(urls, 'Pending');
      } catch (err) {
        if (err.toString().contains('accomplishment_reports_status_check')) {
          await _saveReport(urls, 'Submitted');
        } else {
          rethrow;
        }
      }

      final orgId = widget.activity['organization_id']?.toString();
      String orgName = 'An organization';
      try {
        if (orgId != null) {
          final o = await Supabase.instance.client.from('organizations').select('name').eq('id', orgId).maybeSingle();
          if (o?['name'] != null) orgName = o!['name'].toString();
        }
      } catch (_) {}
      final actTitle = (widget.activity['title'] ?? 'Activity').toString();

      AppUtils.sendNotification(title: 'Accomplishment Report Submitted 📄', body: '$orgName submitted accomplishment report for "$actTitle".', recipientRole: 'admin', organizationId: orgId);
      AppUtils.sendNotification(title: 'Accomplishment Report Submitted 📄', body: 'New accomplishment report submitted for "$actTitle".', recipientRole: 'adviser', organizationId: orgId);

      if (mounted) {
        Navigator.pop(context);
        AppUtils.showTopToast(context, 'Report submitted successfully.');
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppUtils.showTopToast(context, 'Could not submit the report: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogFrame(
      title: 'Submit accomplishment report',
      subtitle: widget.activity['title']?.toString(),
      icon: Icons.upload_file_rounded,
      maxWidth: 640,
      actions: [
        OutlinedButton(onPressed: _isSubmitting ? null : () => Navigator.pop(context), style: _outlineBtn(_C.muted), child: const Text('Cancel')),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submitReport,
          style: _filledBtn(),
          icon: _isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Submit report'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(controller: _titleController, decoration: _input('Report title', icon: Icons.title_rounded), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 20),
            const Text('Files', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _C.body)),
            const SizedBox(height: 4),
            const Text('Narrative report, photos, receipts. Accepted: PDF, DOC, DOCX, JPG, PNG, ZIP.', style: TextStyle(fontSize: 12.5, color: _C.muted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _pickFiles, icon: const Icon(Icons.attach_file_rounded, size: 18), label: const Text('Choose files'), style: _outlineBtn()),
            if (_existingUrls.isNotEmpty || _newFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in _existingUrls)
                    Chip(
                      avatar: const Icon(Icons.insert_drive_file_rounded, size: 14, color: _C.muted),
                      label: Text(StorageUtils.fileName(u), style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFFF1F5F9),
                      side: BorderSide.none,
                      onDeleted: () => setState(() => _existingUrls.remove(u)),
                    ),
                  for (final f in _newFiles)
                    Chip(
                      avatar: const Icon(Icons.insert_drive_file_rounded, size: 14, color: _C.primary),
                      label: Text(f.name, style: const TextStyle(fontSize: 12)),
                      backgroundColor: _C.primarySoft,
                      side: BorderSide.none,
                      onDeleted: () => setState(() => _newFiles.remove(f)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  GPOA PROPOSALS LIST
// ════════════════════════════════════════════════════════════════════════════

class _GPOAStatusGridView extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  final Map<String, dynamic>? orgData;
  final Function(String) onAction;
  final String userRole;
  final VoidCallback onRefresh;
  final int initialTab;
  const _GPOAStatusGridView({required this.activities, this.orgData, required this.onAction, required this.userRole, required this.onRefresh, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    final active = activities.where((a) => a['is_archived'] != true).toList();
    final inReview = active.where((a) => ['Pending', 'Endorsed'].contains(a['status'])).toList();
    final approved = active.where((a) => ['Approved', 'Awaiting Date Approval', 'Reschedule', 'Scheduled'].contains(a['status'])).toList();
    final revision = active.where((a) => a['status'] == 'Needs Revision').toList();
    final completed = active.where((a) => a['status'] == 'Completed').toList();
    final declined = active.where((a) => a['status'] == 'Rejected').toList();
    final isAdviser = userRole == 'Adviser';
    final locked = _gpoaLocked(activities, orgData: orgData);

    return DefaultTabController(
      length: 5,
      initialIndex: initialTab,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              title: 'GPOA proposals',
              subtitle: isAdviser ? 'Review your organization\'s proposals, endorse them, or send them back.' : 'Track each proposal from submission to approval. GPOA stands for General Plan of Activities.',
              actions: [
                if (!isAdviser)
                  Tooltip(
                    message: locked ? 'All proposals are approved, so new proposals are locked.' : '',
                    child: ElevatedButton.icon(
                      onPressed: locked ? null : () => onAction('GPOA Submission'),
                      icon: Icon(locked ? Icons.lock_rounded : Icons.add_rounded, size: 18),
                      label: Text(locked ? 'Proposals locked' : 'New proposal'),
                      style: _filledBtn(),
                    ),
                  ),
                OutlinedButton.icon(onPressed: () => onAction('GPOA Report'), icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print GPOA'), style: _outlineBtn()),
              ],
            ),
            if (!isAdviser && orgData != null && orgData!['is_unlocked'] == true) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFA7F3D0))),
                child: const Row(
                  children: [
                    Icon(Icons.lock_open_rounded, color: Color(0xFF059669), size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('New proposal submissions have been unlocked by Admin. You may submit additional GPOA activity proposals.', style: TextStyle(fontSize: 13, color: Color(0xFF047857), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ] else if (!isAdviser && locked) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFED7AA))),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('All your GPOA proposals are approved. Proposal creation is locked for this school year unless unlocked by Admin.', style: TextStyle(fontSize: 13, color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            _Tabs(labels: [
              '${isAdviser ? 'For review' : 'Under review'} (${inReview.length})',
              'Approved (${approved.length})',
              'Needs correction (${revision.length})',
              'Completed (${completed.length})',
              'Declined (${declined.length})',
            ]),
            const SizedBox(height: 20),
            Expanded(
              child: TabBarView(
                children: [
                  _buildList(inReview, isAdviser ? 'No proposals are waiting for your review.' : 'No proposals are under review.', approveAll: true),
                  _buildList(approved, 'No approved proposals yet.'),
                  _buildList(revision, 'Nothing needs correction.'),
                  _buildList(completed, 'No completed activities yet.', archiveAll: true),
                  _buildList(declined, 'No declined proposals.', archiveAll: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, String emptyText, {bool archiveAll = false, bool approveAll = false}) {
    if (list.isEmpty) return _EmptyState(icon: Icons.inbox_rounded, text: emptyText);
    final canArchive = archiveAll && userRole != 'Adviser';
    final pending = (approveAll && userRole == 'Adviser') ? list.where((a) => a['status'] == 'Pending').toList() : <Map<String, dynamic>>[];
    return Builder(
      builder: (context) => Column(
        children: [
          if (pending.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  onPressed: () => _adviserApproveAll(context, pending, onRefresh),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text('Approve all (${pending.length})'),
                  style: _filledBtn(_C.success),
                ),
              ),
            ),
          if (canArchive)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await _confirmBulk(context, 'Archive all ${list.length}?', 'They will move to Archives. You can restore them there.', 'Archive all');
                    if (!ok || !context.mounted) return;
                    try {
                      await _setArchived('activities', list.map((a) => a['id']).toList(), true);
                      if (!context.mounted) return;
                      AppUtils.showTopToast(context, '${list.length} proposals moved to archive.');
                      onRefresh();
                    } catch (e) {
                      if (context.mounted) AppUtils.showTopToast(context, 'Could not archive: $e', isError: true);
                    }
                  },
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('Archive all'),
                  style: _outlineBtn(),
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _GPOAStatusCard(activity: list[i], userRole: userRole, onRefresh: onRefresh),
            ),
          ),
        ],
      ),
    );
  }
}

class _GPOAStatusCard extends StatelessWidget {
  final Map<String, dynamic> activity;
  final String userRole;
  final VoidCallback onRefresh;
  const _GPOAStatusCard({required this.activity, required this.userRole, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final status = activity['status'] ?? 'Pending';
    final remarks = activity['remarks']?.toString();

    // Only show GPOA proposal remarks (Needs Revision / Rejected for proposal itself)
    final isGpoaRevision = status == 'Needs Revision' || status == 'Rejected';
    final hasRemarks = isGpoaRevision && remarks != null && remarks.trim().isNotEmpty;

    // Only show final event date if approved by admin
    final isFinalDate = status == 'Scheduled' || status == 'Completed';
    final hasDate = isFinalDate && activity['proposed_date'] != null && activity['proposed_date'].toString().trim().isNotEmpty;
    final dateText = hasDate ? AppUtils.formatEventRange(activity['proposed_date'], activity['time_frame']) : null;

    return _ItemCard(
      icon: Icons.description_rounded,
      title: activity['title'] ?? 'Untitled activity',
      body: [
        _statusLine(status),
        if (dateText != null && dateText.isNotEmpty && dateText != 'Not set') _meta('Date: $dateText', color: _C.body, bold: true),
        if (hasRemarks)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _C.danger.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.danger.withValues(alpha: 0.2))),
            child: Text('Feedback: $remarks', style: const TextStyle(fontSize: 12.5, color: _C.danger, fontWeight: FontWeight.w500)),
          ),
      ],
      actions: [
        IconButton(tooltip: 'View details', icon: const Icon(Icons.info_outline_rounded, color: _C.muted), onPressed: () => _showDetails(context)),
        if (isAdviser) ...[
          if (status == 'Pending') ...[
            OutlinedButton(onPressed: () => _adviserDecision(context, activity, 'Rejected', onRefresh, closeDialog: false), style: _outlineBtn(_C.danger), child: const Text('Decline')),
            OutlinedButton(onPressed: () => _adviserDecision(context, activity, 'Needs Revision', onRefresh, closeDialog: false), style: _outlineBtn(_C.warning), child: const Text('Revise')),
            ElevatedButton(onPressed: () => _adviserDecision(context, activity, 'Approved', onRefresh, closeDialog: false), style: _filledBtn(_C.success), child: const Text('Approve')),
          ],
        ] else ...[
          if (status == 'Needs Revision')
            ElevatedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => _ReviseActivityDialog(activity: activity, userRole: userRole, onRefreshed: onRefresh)),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Revise and resubmit'),
              style: _filledBtn(_C.warning),
            ),
          IconButton(
            tooltip: activity['is_archived'] == true ? 'Restore' : 'Move to archive',
            onPressed: () async {
              final wasArchived = activity['is_archived'] == true;
              try {
                await UserArchive.setArchived('activity', [activity['id']], !wasArchived);
                if (context.mounted) {
                  AppUtils.showTopToast(context, wasArchived ? 'Proposal restored.' : 'Proposal moved to archive.');
                  onRefresh();
                }
              } catch (e) {
                if (context.mounted) AppUtils.showTopToast(context, 'Could not update archive: $e', isError: true);
              }
            },
            icon: Icon(activity['is_archived'] == true ? Icons.unarchive_outlined : Icons.archive_outlined, size: 20, color: _C.muted),
          ),
        ],
      ],
    );
  }

  void _showDetails(BuildContext context) {
    final isAdviser = userRole == 'Adviser';
    final status = activity['status'];
    showDialog(
      context: context,
      builder: (dialogCtx) => _DialogFrame(
        title: 'Proposal details',
        subtitle: activity['title']?.toString(),
        maxWidth: 900,
        child: _detailsView(
          activity,
          timeOnly: true,
          onStatusUpdate: isAdviser
              ? (status == 'Pending' ? (String s) => _adviserDecision(dialogCtx, activity, s, onRefresh) : null)
              : (status == 'Needs Revision'
              ? (String s) async {
            Navigator.pop(dialogCtx);
            showDialog(context: context, builder: (_) => _ReviseActivityDialog(activity: activity, userRole: userRole, onRefreshed: onRefresh));
          }
              : null),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PRINT GPOA
// ════════════════════════════════════════════════════════════════════════════

class _GPOAReportPrintingView extends StatelessWidget {
  final Map<String, dynamic> orgData;
  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> profiles;
  final VoidCallback onBack;
  const _GPOAReportPrintingView({required this.orgData, required this.activities, required this.profiles, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final live = activities.where((a) => a['is_archived'] != true).toList();
    final ready = live.where((a) => _approvedStates.contains(a['status'])).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Align(alignment: Alignment.centerLeft, child: _PageHeader(title: 'Print GPOA', subtitle: 'Create a PDF of your General Plan of Activities.', onBack: onBack)),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(36),
                decoration: _box(radius: 16),
                child: Column(
                  children: [
                    Container(padding: const EdgeInsets.all(18), decoration: const BoxDecoration(color: _C.primarySoft, shape: BoxShape.circle), child: const Icon(Icons.picture_as_pdf_rounded, size: 40, color: _C.primary)),
                    const SizedBox(height: 20),
                    const Text('Your GPOA document', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _C.text)),
                    const SizedBox(height: 8),
                    const Text('Only approved, scheduled and completed activities are included. The PDF follows the university template.', textAlign: TextAlign.center, style: TextStyle(color: _C.muted, fontSize: 14)),
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(child: _SummaryItem(label: 'All proposals', value: live.length.toString(), icon: Icons.assignment_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _SummaryItem(label: 'Included in PDF', value: ready.toString(), icon: Icons.check_circle_rounded)),
                    ]),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(onPressed: () => _handlePrint(context), icon: const Icon(Icons.visibility_rounded, size: 18), label: const Text('Preview and print PDF'), style: _filledBtn()),
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

  Future<void> _handlePrint(BuildContext context) async {
    final president = profiles.firstWhere((p) => p['role'] == 'President', orElse: () => {'full_name': 'Not Assigned'});
    final adviser = profiles.firstWhere((p) => p['role'] == 'Adviser', orElse: () => {'full_name': 'Not Assigned'});
    final approvedActivities = activities
        .where((a) => a['is_archived'] != true && _approvedStates.contains(a['status']))
        .toList();
    final orgId = orgData['id'].toString();

    final saved = await _loadSignatories(orgId);
    final initial = {...GPOAPdfGenerator.signatoryDefaults(president: president, adviser: adviser), ...saved};
    if (!context.mounted) return;

    final edited = await _showSignatoriesDialog(context, initial);
    if (edited == null || !context.mounted) return;
    await _saveSignatories(orgId, edited);
    if (!context.mounted) return;

    GPOAPdfGenerator.customSignatories = edited;

    showDialog(
      context: context,
      builder: (context) => GPOAPreviewDialog(
        organization: {...orgData, 'gpoa_signatories': edited},
        activities: approvedActivities,
        president: president,
        adviser: adviser,
        fileName: 'GPOA_${orgData['name']}.pdf',
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _SummaryItem({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
      child: Column(children: [
        Icon(icon, size: 20, color: _C.primary),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _C.text)),
        Text(label, style: const TextStyle(fontSize: 12, color: _C.muted)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  EVALUATION SCORES
// ════════════════════════════════════════════════════════════════════════════

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
    SchoolYearService.current().then((sy) {
      if (!mounted) return;
      setState(() => _schoolYear = sy);
      _fetchScore();
    });
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
      if (mounted) setState(() { _eval = res; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  Widget _scoreTable(List<List<dynamic>> rows) {
    double sumMax = 0, sumEarned = 0;
    for (final r in rows) {
      sumMax += r[2] as double;
      sumEarned += (r[3] as num?)?.toDouble() ?? 0;
    }

    Widget cell(String text, {bool bold = false, Color color = _C.body, TextAlign align = TextAlign.center}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(text, textAlign: align, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
    );

    return Container(
      decoration: _box(radius: 12),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder.symmetric(inside: BorderSide(color: _C.border)),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {0: FlexColumnWidth(5), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2)},
        children: [
          TableRow(
            decoration: const BoxDecoration(color: _C.bg),
            children: [
              cell('Category', bold: true, color: _C.text),
              cell('Maximum Points', bold: true, color: _C.text),
              cell('Points Earned', bold: true, color: _C.text),
              cell('Remaining score', bold: true, color: _C.text),
            ],
          ),
          for (final r in rows)
                () {
              final max = r[2] as double;
              final earned = (r[3] as num?)?.toDouble() ?? 0.0;
              final remaining = (max - earned).clamp(0.0, max).toDouble();
              return TableRow(children: [
                cell('${r[0]}. ${r[1]}', align: TextAlign.left),
                cell(max.toStringAsFixed(1)),
                cell(earned.toStringAsFixed(1), bold: true, color: _C.primary),
                cell(remaining.toStringAsFixed(1)),
              ]);
            }(),
          TableRow(
            decoration: const BoxDecoration(color: _C.primarySoft),
            children: [
              cell('TOTAL :', bold: true, color: _C.text),
              cell(sumMax.toStringAsFixed(2), bold: true, color: _C.text),
              cell(sumEarned.toStringAsFixed(2), bold: true, color: _C.primary),
              cell((sumMax - sumEarned).clamp(0.0, sumMax).toStringAsFixed(2), bold: true, color: _C.text),
            ],
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final total = (_eval?['grand_total'] as num?)?.toDouble() ?? 0.0;
    final rawRating = (_eval?['adjectival_rating'] ?? 'Pending Evaluation').toString();
    final rating = rawRating.contains('|') ? rawRating.split('|').first : rawRating;

    final isSpec = (widget.orgData['type'] ?? '').toString().toLowerCase().contains('special');
    // [numeral, name, maximum points, points earned]
    final rows = <List<dynamic>>[
      if (isSpec) ...[
        ['I', 'Symposium / Seminars Conducted', 20.0, _eval?['score_i']],
        ['II', 'Activities in line with the nature of the organization', 30.0, _eval?['score_ii']],
        ['III', 'Clean & Green Activities', 10.0, _eval?['score_iii']],
        ['IV', 'Extension Services', 10.0, _eval?['score_iv']],
        ['V', 'Tangible / Physical Projects', 10.0, _eval?['score_v']],
        ['VI', 'Fund Drive / IGP', 10.0, _eval?['score_vi']],
        ['VII', 'Action Plan Implementation', 10.0, _eval?['score_vii']],
      ] else ...[
        ['I', 'Symposium / Seminars Conducted', 10.0, _eval?['score_i']],
        ['II', 'Activities / Programs Conducted', 10.0, _eval?['score_ii']],
        ['III', 'Religious Activities', 5.0, _eval?['score_iii']],
        ['IV', 'Socio-Cultural & Sports Activities', 10.0, _eval?['score_iv']],
        ['V', 'Clean & Green Activities', 10.0, _eval?['score_v']],
        ['VI', 'Extension Services', 10.0, _eval?['score_vi']],
        ['VII', 'Tangible / Physical Projects', 15.0, _eval?['score_vii']],
        ['VIII', 'Fund Drive / IGP', 10.0, _eval?['score_viii']],
        ['IX', 'Financial Assistance', 10.0, _eval?['score_ix']],
        ['X', 'Action Plan Implementation', 10.0, _eval?['score_x']],
      ],
    ];

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: 'Evaluation scores',
            subtitle: widget.orgData['name']?.toString() ?? '',
            actions: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: _box(radius: 10),
                child: DropdownButton<String>(
                  value: _schoolYear,
                  underline: const SizedBox(),
                  items: {'2024-2025', '2025-2026', '2026-2027', _schoolYear}.toList().map((sy) => DropdownMenuItem(value: sy, child: Text('SY $sy'))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _schoolYear = v);
                      _fetchScore();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: _C.primary, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Total score', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(_isLoading ? 'Loading…' : '${total.toStringAsFixed(2)} pts', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(100)),
                  child: Text(rating, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Score by category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _eval == null
                ? const _EmptyState(icon: Icons.stars_outlined, text: 'No score recorded for this school year yet.')
                : SingleChildScrollView(child: _scoreTable(rows)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ORGANIZATION PROFILE
// ════════════════════════════════════════════════════════════════════════════

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
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit organization profile'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameController, decoration: _input('Organization name')),
                  const SizedBox(height: 24),
                  const Text('Officers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const Text('Add the names and positions of your organization officers.', style: TextStyle(fontSize: 12.5, color: _C.muted)),
                  const SizedBox(height: 8),
                  if (_officers.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No officers added yet.', style: TextStyle(color: _C.faint, fontSize: 13))),
                  ..._officers.map((off) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(off['full_name'] ?? 'No name'),
                    subtitle: Text(off['position'] ?? 'Officer'),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: _C.danger, size: 20),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: dialogCtx,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Colors.white,
                            title: const Text('Remove officer?'),
                            content: Text('Remove ${off['full_name']} from the list?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: _filledBtn(_C.danger), child: const Text('Remove')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _supabase.from('org_officers').delete().eq('id', off['id']);
                          await _fetchProfileData();
                          setD(() {});
                        }
                      },
                    ),
                  )),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      await _showAddOfficerDialog();
                      setD(() {});
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add officer'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
            ElevatedButton(
              style: _filledBtn(),
              onPressed: () async {
                try {
                  await _supabase.from('organizations').update({'name': nameController.text.trim()}).eq('id', widget.orgData['id']);
                  widget.orgData['name'] = nameController.text.trim();
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  if (mounted) AppUtils.showTopToast(context, 'Changes saved.');
                  _fetchProfileData();
                } catch (e) {
                  if (dialogCtx.mounted) AppUtils.showTopToast(dialogCtx, 'Error: $e', isError: true);
                }
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddOfficerDialog() {
    final nameController = TextEditingController();
    final posController = TextEditingController();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add officer'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: _input('Full name', icon: Icons.person_rounded), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s.]'))]),
              const SizedBox(height: 16),
              TextField(controller: posController, decoration: _input('Position', icon: Icons.badge_rounded, hint: 'e.g. Secretary, Treasurer'), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s.]'))]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: _filledBtn(),
            onPressed: () async {
              final fullName = nameController.text.trim();
              final position = posController.text.trim();
              if (fullName.isEmpty || position.isEmpty) {
                AppUtils.showTopToast(ctx, 'Please enter both the name and the position.', isError: true);
                return;
              }
              try {
                await _supabase.from('org_officers').insert({'full_name': fullName, 'position': position, 'organization_id': widget.orgData['id']});
                await _fetchProfileData();
                if (ctx.mounted) {
                  AppUtils.showTopToast(ctx, '$fullName added.');
                  Navigator.pop(ctx);
                }
              } catch (e) {
                if (ctx.mounted) AppUtils.showTopToast(ctx, 'Error adding officer: $e', isError: true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadLogo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;
      setState(() => _isLoading = true);
      final file = result.files.first;
      final orgId = widget.orgData['id'].toString();
      // Folder name must be the org id so the org-logos policy accepts it.
      final fileName = '$orgId/${DateTime.now().millisecondsSinceEpoch}.png';
      final storage = _supabase.storage.from('org-logos');
      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      await storage.uploadBinary(fileName, bytes, fileOptions: const FileOptions(contentType: 'image/png'));
      final url = storage.getPublicUrl(fileName);
      await _supabase.from('organizations').update({'logo_url': url}).eq('id', widget.orgData['id']);
      widget.orgData['logo_url'] = url;
      if (!mounted) return;
      AppUtils.showTopToast(context, 'Logo updated.');
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
    final points = _completedActivities.fold<double>(0, (sum, item) => sum + (double.tryParse(item['points']?.toString() ?? '0') ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: _box(radius: 16),
                child: Column(
                  children: [
                    Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _showEditProfileDialog, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit profile'))),
                    Stack(children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor: _C.primarySoft,
                        backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                        child: logoUrl == null ? const Icon(Icons.business_rounded, size: 48, color: _C.primary) : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Tooltip(
                          message: 'Change logo',
                          child: GestureDetector(
                            onTap: _uploadLogo,
                            child: Container(padding: const EdgeInsets.all(7), decoration: const BoxDecoration(color: _C.primary, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Text(widget.orgData['name'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _C.text)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(color: _C.primarySoft, borderRadius: BorderRadius.circular(20)),
                      child: Text(widget.orgData['type']?.toString() ?? '', style: const TextStyle(color: _C.primary, fontWeight: FontWeight.w600, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ProfileSection(
                      title: 'Leadership',
                      icon: Icons.people_outline_rounded,
                      child: Column(children: [
                        _LeadershipTile(label: 'Adviser', name: adviser['full_name'], icon: Icons.person_outline_rounded),
                        const Divider(height: 24, color: _C.border),
                        _LeadershipTile(label: 'President', name: president['full_name'], icon: Icons.person_rounded),
                        if (_officers.isNotEmpty) ...[
                          const Divider(height: 24, color: _C.border),
                          const Align(alignment: Alignment.centerLeft, child: Text('Officers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.muted))),
                          const SizedBox(height: 12),
                          ..._officers.map((o) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              const Icon(Icons.badge_outlined, size: 16, color: _C.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(o['full_name'] ?? 'Unknown', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _C.text)),
                                  Text('${o['position'] ?? 'Officer'} · Added ${AppUtils.formatDateTime(o['created_at'])}', style: const TextStyle(fontSize: 11.5, color: _C.muted)),
                                ]),
                              ),
                            ]),
                          )),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _ProfileSection(
                      title: 'Performance',
                      icon: Icons.analytics_outlined,
                      child: Column(children: [
                        Row(children: [
                          Expanded(child: _StatBox(label: 'Completed', value: _completedActivities.length.toString(), icon: Icons.task_alt_rounded, color: _C.success)),
                          const SizedBox(width: 12),
                          Expanded(child: _StatBox(label: 'Points', value: points.toStringAsFixed(2), icon: Icons.star_outline_rounded, color: _C.warning)),
                        ]),
                        const SizedBox(height: 24),
                        const Align(alignment: Alignment.centerLeft, child: Text('Recent accomplishments', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.muted))),
                        const SizedBox(height: 8),
                        if (_completedActivities.isEmpty)
                          const Align(alignment: Alignment.centerLeft, child: Text('No completed events yet.', style: TextStyle(color: _C.faint, fontSize: 13)))
                        else
                          ..._completedActivities.take(5).map((a) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(Icons.check_circle_rounded, color: _C.success, size: 18),
                            title: Text(a['title'], style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                            subtitle: Text(AppUtils.formatEventRange(a['proposed_date'], a['time_frame']), style: const TextStyle(fontSize: 11.5)),
                          )),
                      ]),
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
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: _box(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: _C.primary),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.text)),
        ]),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }
}

class _LeadershipTile extends StatelessWidget {
  final String label, name;
  final IconData icon;
  const _LeadershipTile({required this.label, required this.name, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 20, color: _C.muted)),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: _C.muted, fontWeight: FontWeight.w600)),
        Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _C.text)),
      ]),
    ]);
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REVISE PROPOSAL DIALOG
// ════════════════════════════════════════════════════════════════════════════

class _ReviseActivityDialog extends StatefulWidget {
  final Map<String, dynamic> activity;
  final String userRole;
  final VoidCallback onRefreshed;
  const _ReviseActivityDialog({required this.activity, required this.userRole, required this.onRefreshed});

  @override
  State<_ReviseActivityDialog> createState() => _ReviseActivityDialogState();
}

class _ReviseActivityDialogState extends State<_ReviseActivityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title, _objectives, _outcome, _timeFrame, _delivery, _budget;
  final List<String> _selectedTypes = [];
  final List<String> _selectedSDGs = [];
  final List<String> _selectedParticipants = [];
  final List<String> _selectedPersons = [];
  final List<String> _selectedFacilities = [];
  final List<String> _selectedMaterials = [];
  bool _isSubmitting = false;

  List<String> get _activityTypes => _activityTypesFor((widget.activity['organization_type'] ?? widget.userRole).toString());

  String? _normalizeActivityType(String? rawType) {
    if (rawType == null || rawType.trim().isEmpty) return _activityTypes.first;
    final lower = rawType.toLowerCase();

    if (lower.contains('makakalikasan') || lower.contains('green') || lower.contains('clean')) return 'Makakalikasan/ Clean and Green Activities and Projects';
    if (lower.contains('extension')) return 'Extension Services Sponsored/ Conducted';
    if (lower.contains('seminar') || lower.contains('symposium')) return 'Symposium/ Seminars Conducted';
    if (lower.contains('convocation') || lower.contains('literary') || lower.contains('program')) return 'Convocations/ Programs and Literary Activities';
    if (lower.contains('religious') || lower.contains('holy mass') || lower.contains('rosary')) return 'Religious Activities';
    if (lower.contains('sport') || lower.contains('socio') || lower.contains('cultural')) return 'Socio-Cultural and Sports Activities';
    if (lower.contains('nature') || lower.contains('specialized')) return 'Activities Conducted /Sponsored in line with the nature of the organization';
    if (_activityTypes.contains(rawType)) return rawType;
    return _activityTypes.first;
  }

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    _title = TextEditingController(text: a['title']?.toString() ?? '');
    _objectives = TextEditingController(text: a['objectives']?.toString() ?? a['description']?.toString() ?? '');
    _outcome = TextEditingController(text: a['outcome']?.toString() ?? '');
    _timeFrame = TextEditingController(text: a['time_frame']?.toString() ?? '');
    _delivery = TextEditingController(text: a['delivery_strategy']?.toString() ?? '');
    _budget = TextEditingController(text: a['budget_allocation']?.toString() ?? '');
    _selectedTypes.addAll(_matchOptions(a['subtitle'], _activityTypes));
    if (_selectedTypes.isEmpty) {
      final n = _normalizeActivityType(a['subtitle']?.toString());
      if (n != null) _selectedTypes.add(n);
    }
    _selectedSDGs.addAll(_matchOptions(a['sdgs'], _sdgOptions));
    _selectedParticipants.addAll(_splitList(a['participants']));
    _selectedPersons.addAll(_splitList(a['persons_involved']));
    _parseFacilitiesAndMaterials(a['facilities_materials'], _selectedFacilities, _selectedMaterials);
  }

  @override
  void dispose() {
    for (final c in [_title, _objectives, _outcome, _timeFrame, _delivery, _budget]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submitRevision() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTypes.isEmpty) {
      AppUtils.showTopToast(context, 'Please choose at least one activity type.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final data = <String, dynamic>{
        'title': _title.text.trim(),
        'subtitle': _selectedTypes.isEmpty ? 'General Activities' : _selectedTypes.first,
        'description': _objectives.text.trim(),
        'objectives': _objectives.text.trim(),
        'outcome': _outcome.text.trim(),
        'time_frame': _timeFrame.text.trim(),
        'delivery_strategy': _delivery.text.trim(),
        'facilities_materials': _combineFacilitiesAndMaterials(_selectedFacilities, _selectedMaterials),
        'budget_allocation': _budget.text.trim(),
        'status': 'Pending',
        'remarks': null,
      };
      if (_selectedSDGs.isNotEmpty) data['sdgs'] = _selectedSDGs.join(', ');
      if (_selectedParticipants.isNotEmpty) data['participants'] = _selectedParticipants.join(', ');
      if (_selectedPersons.isNotEmpty) data['persons_involved'] = _selectedPersons.join(', ');

      await Supabase.instance.client.from('activities').update(data).eq('id', widget.activity['id']);

      AppUtils.sendNotification(
        title: 'Proposal Revised 📝',
        body: '"${_title.text.trim()}" was revised and is back for your review.',
        recipientRole: 'adviser',
        organizationId: widget.activity['organization_id']?.toString(),
      );

      if (mounted) {
        Navigator.pop(context);
        AppUtils.showTopToast(context, 'Proposal resubmitted for review.');
        widget.onRefreshed();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppUtils.showTopToast(context, 'Could not resubmit: $e', isError: true);
      }
    }
  }

  Widget _tf(TextEditingController c, String label, IconData icon, {int maxLines = 1, bool required = false, bool numeric = false}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: numeric ? TextInputType.number : TextInputType.multiline,
      inputFormatters: numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: _input(label, icon: icon),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final remarks = widget.activity['remarks']?.toString();
    final types = _activityTypes;

    return _DialogFrame(
      title: 'Revise proposal',
      subtitle: 'Update the details, then resubmit for review.',
      icon: Icons.edit_note_rounded,
      color: _C.warning,
      maxWidth: 960,
      actions: [
        OutlinedButton(onPressed: _isSubmitting ? null : () => Navigator.pop(context), style: _outlineBtn(_C.muted), child: const Text('Cancel')),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submitRevision,
          style: _filledBtn(_C.warning),
          icon: _isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 16),
          label: const Text('Resubmit proposal'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (remarks != null && remarks.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDBA74))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.feedback_outlined, color: Color(0xFFC2410C), size: 18),
                  SizedBox(width: 8),
                  Text('What to fix (feedback from reviewer)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC2410C))),
                ]),
                const SizedBox(height: 8),
                Text(remarks, style: const TextStyle(fontSize: 14, color: Color(0xFF7C2D12), height: 1.5)),
              ]),
            ),
            const SizedBox(height: 20),
          ],
          Form(
            key: _formKey,
            child: Column(children: [
              _FormSection(
                title: 'Basic information',
                icon: Icons.info_outline_rounded,
                child: Column(children: [
                  _tf(_title, 'Activity title', Icons.title_rounded, required: true),
                  const SizedBox(height: 16),
                  _MultiSelectField(
                    label: 'Activity type',
                    hint: 'Tap to choose an activity type',
                    icon: Icons.category_rounded,
                    items: _selectedTypes,
                    onTap: () => _pickSingle(context, title: 'Choose activity type', options: types, selected: _selectedTypes, onChanged: () => setState(() {})),
                    onRemove: (s) => setState(() => _selectedTypes.remove(s)),
                  ),
                ]),
              ),

              const SizedBox(height: 16),
              _FormSection(
                title: 'Goals',
                icon: Icons.flag_rounded,
                child: Column(children: [
                  _MultiSelectField(
                    label: 'Sustainable Development Goals (SDGs)',
                    hint: 'Tap to choose one or more SDGs',
                    icon: Icons.public_rounded,
                    items: _selectedSDGs,
                    chipText: (s) => s.split(':').first,
                    onTap: () => _pickMultiple(context, title: 'Choose SDGs', options: _sdgOptions, selected: _selectedSDGs, onChanged: () => setState(() {})),
                    onRemove: (s) => setState(() => _selectedSDGs.remove(s)),
                  ),
                  const SizedBox(height: 16),
                  _tf(_objectives, 'Objectives', Icons.flag_rounded, maxLines: 4, required: true),
                  const SizedBox(height: 16),
                  _tf(_outcome, 'Expected outcome', Icons.stars_rounded, maxLines: 4),
                ]),
              ),
              const SizedBox(height: 16),
              _FormSection(
                title: 'Plan and resources',
                icon: Icons.rocket_launch_rounded,
                child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _TimeFrameInput(controller: _timeFrame)),
                    const SizedBox(width: 16),
                    Expanded(child: Padding(padding: const EdgeInsets.only(top: 26), child: _tf(_budget, 'Budget (₱)', Icons.payments_rounded, numeric: true))),
                  ]),
                  const SizedBox(height: 16),
                  _MultiSelectField(
                    label: 'Who will attend? (Target participants)',
                    hint: 'Tap to choose who the activity is for',
                    icon: Icons.groups_rounded,
                    items: _selectedParticipants,
                    onTap: () => _pickGrouped(
                      context,
                      title: 'Who will attend?',
                      intro: 'Choose the people this activity is meant for. You can pick more than one.',
                      groups: _participantGroups,
                      help: _participantHelp,
                      selected: _selectedParticipants,
                      onChanged: () => setState(() {}),
                    ),
                    onRemove: (s) => setState(() => _selectedParticipants.remove(s)),
                  ),
                  const SizedBox(height: 16),
                  _MultiSelectField(
                    label: 'Who will organize or help? (Persons involved)',
                    hint: 'Tap to choose the people running the activity',
                    icon: Icons.people_alt_rounded,
                    items: _selectedPersons,
                    onTap: () => _pickGrouped(
                      context,
                      title: 'Who will organize or help?',
                      intro: 'Choose the people who will help run this activity. These are not the attendees.',
                      groups: _personsGroups,
                      help: _personsHelp,
                      selected: _selectedPersons,
                      onChanged: () => setState(() {}),
                    ),
                    onRemove: (s) => setState(() => _selectedPersons.remove(s)),
                  ),
                  const SizedBox(height: 16),
                  _tf(_delivery, 'Delivery strategy', Icons.map_rounded, maxLines: 4),
                  const SizedBox(height: 16),
                  _MultiSelectField(
                    label: 'Facilities / Venues needed',
                    hint: 'Tap to choose venue/facilities (e.g. AVR, Gym, Classroom)',
                    icon: Icons.business_rounded,
                    items: _selectedFacilities,
                    onTap: () => _pickFacilities(context, selected: _selectedFacilities, onChanged: () => setState(() {})),
                    onRemove: (s) => setState(() => _selectedFacilities.remove(s)),
                  ),
                  const SizedBox(height: 16),
                  _MultiSelectField(
                    label: 'Materials & Equipment needed',
                    hint: 'Tap to choose equipment and supplies (e.g. Sound system, Projector)',
                    icon: Icons.inventory_2_rounded,
                    items: _selectedMaterials,
                    onTap: () => _pickMaterials(context, selected: _selectedMaterials, onChanged: () => setState(() {})),
                    onRemove: (s) => setState(() => _selectedMaterials.remove(s)),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ARCHIVES
// ════════════════════════════════════════════════════════════════════════════

class _ArchivesView extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final Map<String, dynamic>? orgData;
  final String userRole;
  const _ArchivesView({required this.activities, this.orgData, this.userRole = 'Admin'});

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
    SchoolYearService.current().then((sy) {
      if (mounted) setState(() => _schoolYear = sy);
    });
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
      final currentOrgId = widget.orgData?['id']?.toString();
      var query = Supabase.instance.client.from('accomplishment_reports').select('*, activities(*)');
      if (currentOrgId != null && currentOrgId.isNotEmpty) {
        query = query.eq('organization_id', currentOrgId);
      }
      final res = await query;
      final reps = await UserArchive.decorate(List<Map<String, dynamic>>.from(res), 'report');
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
    final currentOrgId = widget.orgData?['id']?.toString();
    final orgNameFilter = widget.orgData != null ? (widget.orgData!['name'] ?? '').toString().toLowerCase().trim() : '';
    final query = _searchQuery.toLowerCase();

    final myActivities = widget.activities.where((act) {
      if (act['is_archived'] != true) return false; // only archived items
      final actOrgId = act['organization_id']?.toString();
      if (currentOrgId != null && currentOrgId.isNotEmpty && actOrgId == currentOrgId) return true;
      final actOrgName = (act['organization_name'] ?? act['organization']?['name'] ?? '').toString().toLowerCase().trim();
      return orgNameFilter.isNotEmpty && actOrgName == orgNameFilter;
    }).toList();

    final docs = <Map<String, dynamic>>[];

    // 1. One GPOA entry per organization
    if (_selectedCategory == 'All' || _selectedCategory == 'GPOA') {
      final Map<String, List<Map<String, dynamic>>> orgActsMap = {};
      final Map<String, String> orgNamesMap = {};
      for (var act in myActivities) {
        final orgId = act['organization_id']?.toString() ?? widget.orgData?['id']?.toString() ?? 'unknown';
        orgNamesMap[orgId] = (act['organization_name'] ?? widget.orgData?['name'] ?? 'Organization').toString();
        orgActsMap.putIfAbsent(orgId, () => []).add(act);
      }
      orgActsMap.forEach((orgId, acts) {
        final orgName = orgNamesMap[orgId] ?? 'Organization';
        if (query.isNotEmpty && !orgName.toLowerCase().contains(query)) return;
        docs.add({
          'type': 'GPOA',
          'title': 'Annual GPOA – $orgName',
          'org_name': orgName,
          'date': 'SY $_schoolYear',
          'color': _C.primary,
          'icon': Icons.description_rounded,
          'acts': acts,
          'is_gpoa': true,
        });
      });
    }

    // 2. Approved event letters
    for (var act in myActivities) {
      final actTitle = (act['title'] ?? 'Untitled Activity').toString();
      final orgName = (act['organization_name'] ?? widget.orgData?['name'] ?? 'Organization').toString();
      if (query.isNotEmpty && !actTitle.toLowerCase().contains(query) && !orgName.toLowerCase().contains(query)) continue;

      if (act['letter_url'] != null && act['letter_url'].toString().isNotEmpty && (_selectedCategory == 'All' || _selectedCategory == 'Approved Letter')) {
        docs.add({
          'type': 'Approved Letter',
          'title': 'Event letter – $actTitle',
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

    // 3. Approved accomplishment reports only
    for (var rep in _accomplishmentReports) {
      final statusLower = (rep['status'] ?? '').toString().toLowerCase();
      if (rep['is_archived'] != true) continue;
      if (!['approved', 'completed', 'verified', 'passed'].contains(statusLower)) continue;

      final act = rep['activities'] ?? {};
      final actTitle = (rep['title'] ?? act['title'] ?? 'Activity Report').toString();
      final orgName = (rep['organization_name'] ?? widget.orgData?['name'] ?? 'Organization').toString();
      if (query.isNotEmpty && !actTitle.toLowerCase().contains(query) && !orgName.toLowerCase().contains(query)) continue;

      final rawUrls = rep['attachments'] ?? rep['file_urls'] ?? rep['report_url'] ?? rep['attachment_url'];
      String? fileUrl;
      if (rawUrls is List && rawUrls.isNotEmpty) {
        fileUrl = rawUrls.first.toString();
      } else if (rawUrls is String && rawUrls.isNotEmpty) {
        fileUrl = rawUrls;
      }

      if (_selectedCategory == 'All' || _selectedCategory == 'Accomplishment Report') {
        docs.add({
          'type': 'Accomplishment Report',
          'title': 'Report – $actTitle',
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

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(
            title: 'Archives',
            subtitle: 'Your approved GPOA, event letters and accomplishment reports in one place.',
            actions: [
              if (docs.isNotEmpty)
                OutlinedButton.icon(onPressed: () => _restoreDocs(docs), icon: const Icon(Icons.unarchive_outlined, size: 18), label: const Text('Restore all'), style: _outlineBtn()),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: _box(radius: 10),
                child: DropdownButton<String>(
                  value: _schoolYear,
                  underline: const SizedBox(),
                  items: {'2024-2025', '2025-2026', '2026-2027', _schoolYear}.toList().map((sy) => DropdownMenuItem(value: sy, child: Text('SY $sy'))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _schoolYear = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: _input('Search', icon: Icons.search_rounded, hint: 'Search by title, activity or organization'),
                ),
              ),
              const SizedBox(width: 16),
              Wrap(
                spacing: 8,
                children: ['All', 'GPOA', 'Accomplishment Report', 'Approved Letter'].map((cat) {
                  final sel = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat == 'Approved Letter' ? 'Letters' : (cat == 'Accomplishment Report' ? 'Reports' : cat)),
                    selected: sel,
                    showCheckmark: false,
                    selectedColor: _C.primary,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _C.border),
                    labelStyle: TextStyle(color: sel ? Colors.white : _C.body, fontWeight: FontWeight.w600, fontSize: 13),
                    onSelected: (s) {
                      if (s) setState(() => _selectedCategory = cat);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isLoadingReports
                ? const Center(child: CircularProgressIndicator())
                : docs.isEmpty
                ? const _EmptyState(icon: Icons.inventory_2_outlined, text: 'No documents match your search.')
                : ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) {
                final doc = docs[idx];
                final Color col = doc['color'];
                final isGPOA = doc['is_gpoa'] == true;
                return _ItemCard(
                  icon: doc['icon'],
                  color: col,
                  title: doc['title'].toString(),
                  body: [_meta('${doc['org_name']} · ${doc['date']}')],
                  actions: [
                    IconButton(tooltip: 'Restore (unarchive)', icon: const Icon(Icons.unarchive_outlined, color: _C.muted), onPressed: () => _restoreDocs([doc])),
                    ElevatedButton.icon(
                      style: _filledBtn(col),
                      icon: Icon(isGPOA ? Icons.picture_as_pdf_rounded : Icons.visibility_rounded, size: 16),
                      label: Text(isGPOA ? 'View GPOA' : 'View file'),
                      onPressed: () async {
                        if (isGPOA && doc['acts'] != null) {
                          _openGPOADialog(List<Map<String, dynamic>>.from(doc['acts'] as List), doc['org_name'].toString());
                        } else if (doc['type'] == 'Accomplishment Report') {
                          showDialog(context: context, builder: (_) => AccomplishmentReportDetailsDialog(report: doc));
                        } else if (doc['file_url'] != null && doc['file_url'].toString().isNotEmpty) {
                          final ok = await StorageUtils.open(doc['file_url'].toString());
                          if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the file.', isError: true);
                        } else {
                          AppUtils.showTopToast(context, 'No file attached.');
                        }
                      },
                    ),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final title = report['title']?.toString() ?? 'Accomplishment Report';
    final orgName = report['org_name']?.toString() ?? 'Organization';
    final date = report['date']?.toString() ?? 'SY 2025-2026';
    final summary = report['summary']?.toString() ?? report['description']?.toString() ?? 'Submitted Accomplishment Report';
    final act = report['act'] as Map<String, dynamic>? ?? {};

    final attachments = <String>[];
    if (report['file_url'] != null && report['file_url'].toString().isNotEmpty) attachments.add(report['file_url'].toString());
    final rawAttach = report['attachments'] ?? act['attachments'] ?? act['report_url'];
    if (rawAttach is List) {
      attachments.addAll(rawAttach.map((e) => e.toString()).where((e) => e.isNotEmpty));
    } else if (rawAttach is String && rawAttach.isNotEmpty) {
      attachments.add(rawAttach);
    }
    final files = attachments.toSet().toList();

    return _DialogFrame(
      title: title,
      subtitle: '$orgName · $date',
      icon: Icons.assignment_turned_in_rounded,
      color: const Color(0xFF0D9488),
      maxWidth: 680,
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.muted)),
              const SizedBox(height: 8),
              Text(summary.trim().isEmpty ? 'Report submitted and approved.' : summary, style: const TextStyle(fontSize: 14, color: _C.body, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('Attached files', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _C.text)),
          const SizedBox(height: 10),
          if (files.isEmpty)
            const Text('No files attached.', style: TextStyle(fontSize: 13, color: _C.muted))
          else
            ...files.map((fileUrl) {
              final fileName = StorageUtils.fileName(fileUrl);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: _box(radius: 10),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF0D9488), size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5, color: _C.text))),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await StorageUtils.open(fileUrl);
                      if (!ok && context.mounted) AppUtils.showTopToast(context, 'Could not open the file.', isError: true);
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Open'),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ADVISER DECISION (endorse / return / reject)
// ════════════════════════════════════════════════════════════════════════════

Future<void> _adviserDecision(BuildContext context, Map<String, dynamic> activity, String s, VoidCallback onRefresh, {bool closeDialog = true}) async {
  final status = s == 'Approved' ? 'Endorsed' : s; // the widget's "approve" means endorse for advisers
  String? remarks;
  if (status == 'Needs Revision' || status == 'Rejected') {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(status == 'Rejected' ? 'Reject this proposal' : 'Return for revision'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: c, maxLines: 4, decoration: _input('Remarks (required)', hint: 'Explain what needs to change')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: _filledBtn(status == 'Rejected' ? _C.danger : _C.warning),
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    remarks = c.text.trim();
  }
  try {
    await Supabase.instance.client.from('activities').update({
      'status': status,
      'remarks': remarks,
      'revision_by': status == 'Needs Revision' ? 'Adviser' : null,
    }).eq('id', activity['id']);

    final orgId = activity['organization_id']?.toString();
    if (status == 'Endorsed') {
      AppUtils.sendNotification(title: 'GPOA Endorsed ✅', body: '"${activity['title']}" was endorsed and awaits your review.', recipientRole: 'admin', organizationId: orgId);
    } else {
      AppUtils.sendNotification(title: status == 'Rejected' ? 'GPOA Rejected' : 'GPOA Needs Revision', body: '"${activity['title']}": see the adviser remarks.', recipientRole: 'president', organizationId: orgId);
    }
    if (context.mounted) {
      AppUtils.showTopToast(context, status == 'Endorsed' ? 'Proposal endorsed.' : 'Feedback sent.');
      if (closeDialog) Navigator.pop(context);
      onRefresh();
    }
  } catch (e) {
    if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
  }
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

Future<Map<String, String>?> _showSignatoriesDialog(BuildContext context, Map<String, String> initial) {
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

  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('GPOA signatories'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _meta('These names and positions will appear on the printed GPOA.'),
              for (final r in rows) ...[
                const SizedBox(height: 16),
                Text('${r.$1}:', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _C.text)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: ctrls['${r.$2}_name'], decoration: _input('Full name', icon: Icons.person_rounded))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: ctrls['${r.$2}_title'], decoration: _input('Position', icon: Icons.badge_rounded))),
                ]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, GPOAPdfGenerator.signatoryDefaults()), child: const Text('Reset')),
        ElevatedButton(
          style: _filledBtn(),
          onPressed: () => Navigator.pop(ctx, {for (final e in ctrls.entries) e.key: e.value.text.trim()}),
          child: const Text('Continue to preview'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmBulk(BuildContext context, String title, String message, String action) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: _filledBtn(), child: Text(action)),
      ],
    ),
  );
  return res == true;
}

Future<void> _setArchived(String table, List<dynamic> ids, bool archived) async {
  if (ids.isEmpty) return;
  await UserArchive.setArchived(table == 'activities' ? 'activity' : 'report', ids, archived);
}
const _approvedStates = ['Approved', 'Reschedule', 'Awaiting Date Approval', 'Scheduled', 'Completed'];

/// True when proposals are locked for this organization:
/// 1. Admin explicitly locked it (`is_unlocked == false`), OR
/// 2. Organization has active proposals, all active proposals are approved, AND Admin has not explicitly unlocked it (`is_unlocked != true`).
bool _gpoaLocked(List<Map<String, dynamic>> acts, {Map<String, dynamic>? orgData}) {
  if (orgData != null) {
    if (orgData['is_unlocked'] == false) {
      return true; // Explicitly locked by Admin!
    }
    if (orgData['is_unlocked'] == true) {
      return false; // Explicitly unlocked by Admin!
    }
  }

  // Automatic lock rule: Locked if org has active proposals and ALL of them are approved.
  final active = acts.where((a) => a['is_archived'] != true).toList();
  return active.isNotEmpty && active.every((a) => _approvedStates.contains(a['status']));
}

Future<void> _adviserApproveAll(BuildContext context, List<Map<String, dynamic>> pending, VoidCallback onRefresh) async {
  if (pending.isEmpty) return;
  final ok = await _confirmBulk(context, 'Approve all ${pending.length} proposals?',
      'They will be endorsed and sent to OSDW for final approval.', 'Approve all');
  if (!ok || !context.mounted) return;
  try {
    await Supabase.instance.client
        .from('activities')
        .update({'status': 'Endorsed', 'remarks': null, 'revision_by': null})
        .inFilter('id', pending.map((a) => a['id']).toList());
    AppUtils.sendNotification(
      title: 'GPOA Endorsed ✅',
      body: '${pending.length} proposals were endorsed and await your review.',
      recipientRole: 'admin',
      organizationId: pending.first['organization_id']?.toString(),
    );
    if (context.mounted) AppUtils.showTopToast(context, '${pending.length} proposals endorsed.');
    onRefresh();
  } catch (e) {
    if (context.mounted) AppUtils.showTopToast(context, 'Error: $e', isError: true);
  }
}