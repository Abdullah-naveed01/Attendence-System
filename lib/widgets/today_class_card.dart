import 'package:flutter/material.dart';

import '../models/timetable_slot.dart';

// One card in the "Today's Classes" list (used by Teacher and Student Home).
// Shows the time, the course, and a status chip: Upcoming / Now / Finished.
// [action] is an optional button on the right (the teacher's "Start Class").
class TodayClassCard extends StatelessWidget {
  final TimetableSlot slot;
  final DateTime now;
  final Widget? action;

  const TodayClassCard({
    super.key,
    required this.slot,
    required this.now,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final status = slot.statusAt(now);

    final (String label, Color color) = switch (status) {
      SlotStatus.open => ('Now', Colors.green),
      SlotStatus.upcoming => ('Upcoming', Colors.blue),
      SlotStatus.finished => ('Finished', Colors.grey),
      SlotStatus.notToday => ('', Colors.grey),
    };

    return Card(
      // Highlight the class that is happening now
      color: status == SlotStatus.open ? Colors.green.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.timeRange,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: status == SlotStatus.finished
                          ? Colors.grey
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(slot.course.name, style: const TextStyle(fontSize: 16)),
                  Text(slot.course.code,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(label,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
            ?action, // only added when an action was given
          ],
        ),
      ),
    );
  }
}
