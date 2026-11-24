import 'package:flutter/material.dart';

// The main action button of a screen: full width, rounded, with an
// optional icon and a built-in loading spinner.
// onPressed == null  -> disabled (same as a normal Flutter button).
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading; // shows a spinner and blocks taps
  final Color? color; // optional custom background (e.g. red for End Class)

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = color == null
        ? null
        : FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          );

    final Widget child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: loading
          ? const SizedBox(
              key: ValueKey('loading'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: style,
        // While loading the button keeps its color but ignores taps.
        onPressed: loading ? () {} : onPressed,
        child: child,
      ),
    );
  }
}
