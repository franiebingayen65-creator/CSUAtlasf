import 'package:flutter/material.dart';

/// One place for colors so every screen looks consistent.
class UiColors {
  static const bg = Color(0xFFF6F7FB);
  static const surface = Colors.white;
  static const border = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const primary = Color(0xFF4F46E5);
  static const success = Color(0xFF059669);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const info = Color(0xFF0284C7);
}

/// Plain-language label + color for every status stored in the database.
class StatusInfo {
  final String label;
  final Color color;
  const StatusInfo(this.label, this.color);
}

StatusInfo statusInfo(String? raw) {
  switch ((raw ?? 'Pending').trim()) {
    case 'Pending':
      return const StatusInfo('Waiting for review', UiColors.muted);
    case 'Endorsed':
      return const StatusInfo('Ready for your review', UiColors.warning);
    case 'Awaiting Date Approval':
      return const StatusInfo('Date needs approval', UiColors.primary);
    case 'Needs Revision':
      return const StatusInfo('Returned for changes', UiColors.danger);
    case 'Approved':
      return const StatusInfo('Approved', UiColors.success);
    case 'Scheduled':
      return const StatusInfo('Scheduled', UiColors.info);
    case 'Completed':
      return const StatusInfo('Completed', UiColors.success);
    case 'Rejected':
      return const StatusInfo('Rejected', UiColors.danger);
    default:
      return StatusInfo(raw ?? 'Unknown', UiColors.muted);
  }
}

class StatusChip extends StatelessWidget {
  final String? status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = statusInfo(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s.color),
      ),
    );
  }
}

/// Page title + one-line explanation + optional action on the right.
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const PageHeader({super.key, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800, color: UiColors.text, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 14, color: UiColors.muted, height: 1.4)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

/// White rounded card with a thin border (no heavy shadows).
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final String? title;
  final IconData? icon;
  final Widget? action;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.title,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: UiColors.muted), const SizedBox(width: 8)],
                Expanded(
                  child: Text(title!,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: UiColors.text)),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

/// Friendly "nothing here" message that also says what to do next.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFFCBD5E1)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: UiColors.text)),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message!,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: UiColors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Clickable number card. No made-up percentages; just a count and a hint.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UiColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: UiColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: UiColors.text, height: 1)),
                    const SizedBox(height: 4),
                    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: UiColors.text)),
                    Text(hint, style: const TextStyle(fontSize: 12, color: UiColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: UiColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple tab bar used on review screens.
class PillTabBar extends StatelessWidget {
  final List<Tab> tabs;
  final ValueChanged<int>? onTap;
  const PillTabBar({super.key, required this.tabs, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UiColors.border),
      ),
      child: TabBar(
        onTap: onTap,
        labelColor: Colors.white,
        unselectedLabelColor: UiColors.muted,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(borderRadius: BorderRadius.circular(9), color: UiColors.primary),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: tabs,
      ),
    );
  }
}


class OrgFilter extends StatelessWidget {
  final List<Map<String, dynamic>> organizations;
  final String? value;
  final ValueChanged<String?> onChanged;
  const OrgFilter({super.key, required this.organizations, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UiColors.border),
      ),
      child: DropdownButton<String?>(
        value: value,
        underline: const SizedBox(),
        icon: const Icon(Icons.expand_more_rounded, color: UiColors.muted),
        onChanged: onChanged,
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All organizations')),
          ...organizations.map((o) => DropdownMenuItem<String?>(
            value: o['id'].toString(),
            child: Text((o['name'] ?? 'Unnamed organization').toString()),
          )),
        ],
      ),
    );
  }
}