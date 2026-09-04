import 'package:flutter/material.dart';
import 'common_ui.dart';

class GPOAActivityDetailsView extends StatelessWidget {
  final String title, sdgs, objectives, outcome, participants, timeFrame, delivery, persons, facilities, budget, status;
  final String? createdAt, proposedDate;
  final Function(String)? onStatusUpdate;

  const GPOAActivityDetailsView({
    super.key,
    required this.title,
    required this.sdgs,
    required this.objectives,
    required this.outcome,
    required this.participants,
    required this.timeFrame,
    required this.delivery,
    required this.persons,
    required this.facilities,
    required this.budget,
    required this.status,
    this.createdAt,
    this.proposedDate,
    this.onStatusUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final isCleared = ['Approved', 'Scheduled', 'Completed'].contains(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
                        ],
                      ),
                      child: const Icon(Icons.event_note_rounded, color: Color(0xFF6366F1), size: 28),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5),
                          ),
                          const SizedBox(height: 8),
                          if (createdAt != null)
                            Row(
                              children: [
                                const Icon(Icons.history_toggle_off_rounded, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 6),
                                Text(
                                  'Submitted on: $createdAt',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    StatusBadge(status: status),
                  ],
                ),
                if (!isCleared && onStatusUpdate != null) ...[
                  const SizedBox(height: 32),
                  if (status == 'Needs Revision')
                    _ActionButton(
                      onPressed: () => onStatusUpdate!('Pending'),
                      icon: Icons.send_rounded,
                      label: 'Resubmit for Review',
                      color: const Color(0xFF6366F1),
                    )
                  else
                    Row(
                      children: [
                        _ActionButton(
                          onPressed: () => onStatusUpdate!(status == 'Endorsed' ? 'Approved' : 'Endorsed'),
                          icon: Icons.check_circle_rounded,
                          label: status == 'Endorsed' ? 'Approve GPOA' : 'Endorse Proposal',
                          color: const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 12),
                        _ActionButton(
                          onPressed: () => onStatusUpdate!('Needs Revision'),
                          icon: Icons.history_edu_rounded,
                          label: 'Return for Revision',
                          color: const Color(0xFFF59E0B),
                          isOutlined: true,
                        ),
                        const SizedBox(width: 12),
                        _ActionButton(
                          onPressed: () => onStatusUpdate!('Rejected'),
                          icon: Icons.cancel_rounded,
                          label: 'Reject',
                          color: const Color(0xFFEF4444),
                          isOutlined: true,
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                _GPOAGridSection(
                  title: 'STRATEGIC ALIGNMENT',
                  icon: Icons.track_changes_rounded,
                  items: [
                    _InfoBlock(label: 'SDGs ADDRESSED', value: sdgs, icon: Icons.public_rounded),
                    _InfoBlock(label: 'OBJECTIVES', value: objectives, icon: Icons.flag_rounded),
                    _InfoBlock(label: 'EXPECTED OUTCOME', value: outcome, icon: Icons.verified_user_rounded),
                  ],
                ),
                const _Divider(),
                _GPOAGridSection(
                  title: 'EXECUTION PLAN',
                  icon: Icons.rocket_launch_rounded,
                  items: [
                    _InfoBlock(label: 'TARGET PARTICIPANTS', value: participants, icon: Icons.groups_rounded),
                    _InfoBlock(label: 'TIME FRAME', value: timeFrame, icon: Icons.timer_rounded),
                    _InfoBlock(label: 'DELIVERY STRATEGY', value: delivery, icon: Icons.map_rounded),
                  ],
                ),
                const _Divider(),
                _GPOAGridSection(
                  title: 'RESOURCE ALLOCATION',
                  icon: Icons.inventory_2_rounded,
                  items: [
                    _InfoBlock(label: 'PERSONS INVOLVED', value: persons, icon: Icons.person_search_rounded),
                    _InfoBlock(label: 'FACILITIES & MATERIALS', value: facilities, icon: Icons.business_rounded),
                    _InfoBlock(label: 'BUDGET ALLOCATION', value: budget, icon: Icons.payments_rounded, isHighlight: true),
                  ],
                ),
                if (proposedDate != null) ...[
                  const _Divider(),
                  _GPOAGridSection(
                    title: 'SCHEDULING',
                    icon: Icons.calendar_month_rounded,
                    items: [
                      _InfoBlock(label: 'FINAL EVENT DATE', value: proposedDate!, icon: Icons.event_available_rounded, isHighlight: true),
                      const SizedBox(),
                      const SizedBox(),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool isOutlined;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isOutlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _GPOAGridSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> items;
  const _GPOAGridSection({required this.title, required this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.map((e) => Expanded(child: e)).toList(),
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final bool isHighlight;
  const _InfoBlock({required this.label, required this.value, required this.icon, this.isHighlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHighlight ? const Color(0xFF6366F1).withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: isHighlight ? const Color(0xFF6366F1) : const Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isHighlight ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                    fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Divider(color: Color(0xFFF1F5F9), height: 1),
    );
  }
}
