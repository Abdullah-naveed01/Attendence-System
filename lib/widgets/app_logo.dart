import 'package:flutter/material.dart';

import '../core/theme.dart';

// The app logo: a rounded square with an indigo -> teal gradient and a
// QR icon. Used on the splash and the login screen.
// The Hero tag makes the logo "fly" from the splash to the login screen.
class AppLogo extends StatelessWidget {
  final double size;
  final bool onDark; // white tile, for use on the colored splash background

  const AppLogo({super.key, this.size = 96, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'app-logo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          color: onDark ? Colors.white : null,
          gradient: onDark
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
          boxShadow: [
            BoxShadow(
              color: (onDark ? Colors.black : AppColors.primary)
                  .withValues(alpha: 0.25),
              blurRadius: size * 0.25,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: Icon(
          Icons.qr_code_scanner_rounded,
          color: onDark ? AppColors.primary : Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }
}
