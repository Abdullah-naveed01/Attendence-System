import 'package:flutter/material.dart';

import '../core/theme.dart';

// The colored greeting header at the top of each Home screen.
// Each role has its own accent color (Student teal, Teacher indigo,
// Admin brown). Shows "Good morning," + the user's name + a role badge.
class RoleHeader extends StatelessWidget {
  final String name;
  final String role; // 'student' | 'teacher' | 'admin'
  final String? subtitle; // e.g. "Monday, 23 Nov"

  const RoleHeader({
    super.key,
    required this.name,
    required this.role,
    this.subtitle,
  });

  // Greeting based on the time of day
  static String greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning,';
    if (now.hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.forRole(role);
    final initial = name.isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.lerp(accent, Colors.black, 0.25)!],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting(DateTime.now()),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85)),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role[0].toUpperCase() + role.substring(1),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
