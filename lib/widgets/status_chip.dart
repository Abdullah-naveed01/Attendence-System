import 'package:flutter/material.dart';

import '../core/theme.dart';

// The 4 attendance statuses (+ "in_progress" while today's class runs).
const attendanceStatuses = ['present', 'late', 'absent', 'excused'];

// Human label for a status code.
String statusLabel(String status) {
  switch (status) {
    case 'present':
      return 'Present';
    case 'late':
      return 'Late';
    case 'excused':
      return 'Excused';
    case 'in_progress':
      return 'In progress';
    default:
      return 'Absent';
  }
}

// Color for a status code.
Color statusColor(String status) {
  switch (status) {
    case 'present':
      return AppColors.success;
    case 'late':
      return AppColors.warning;
    case 'excused':
      return AppColors.info;
    case 'in_progress':
      return Colors.grey;
    default:
      return AppColors.danger;
  }
}

// A small colored pill: Present (green) / Late (orange) /
// Absent (red) / Excused (blue) / In progress (grey).
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
