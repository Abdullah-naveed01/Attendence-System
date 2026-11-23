import 'package:flutter/material.dart';

// A centered icon + message, with an optional Retry button.
// Used by screens for their error state and their empty state.
class MessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? color;
  final VoidCallback? onRetry;

  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.color,
    this.onRetry,
  });

  // Network or server error: red icon + Retry.
  const MessageView.error(this.message, {super.key, this.onRetry})
      : icon = Icons.error_outline,
        color = Colors.red;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: color ?? Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
