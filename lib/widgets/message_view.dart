import 'package:flutter/material.dart';

import 'state_views.dart';

// A centered icon + message, with an optional Retry button.
// Used by screens for their error state and their empty state.
// It now draws itself with the shared EmptyState / ErrorState styles,
// so every screen that uses it gets the new look automatically.
class MessageView extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? color;
  final VoidCallback? onRetry;
  final bool _isError;

  const MessageView({
    super.key,
    required this.icon,
    required this.message,
    this.color,
    this.onRetry,
  }) : _isError = false;

  // Network or server error: red icon + Retry.
  const MessageView.error(this.message, {super.key, this.onRetry})
      : icon = Icons.error_outline,
        color = null,
        _isError = true;

  @override
  Widget build(BuildContext context) {
    if (_isError) return ErrorState(message: message, onRetry: onRetry);
    return EmptyState(
      icon: icon,
      message: message,
      color: color,
      action: onRetry == null
          ? null
          : FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}
