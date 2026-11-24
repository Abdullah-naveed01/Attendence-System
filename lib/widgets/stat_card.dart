import 'package:flutter/material.dart';

import '../core/theme.dart';

// A small dashboard tile: colored icon, big number, label.
// e.g. StatCard(icon: Icons.school, label: 'Students', value: '42')
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(value,
                style: text.headlineSmall?.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}
