import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'screens/splash_screen.dart';

// Supabase project details.
// Only the public (publishable/anon) key goes here. NEVER the secret key.
const String supabaseUrl = 'https://roqofpqikwjhrdviicio.supabase.co';
const String supabaseAnonKey = 'sb_publishable_yGX2q8hi0qNdgIW38FwHyw_eGWU4wKC';

Future<void> main() async {
  // Make sure Flutter is ready before starting Supabase.
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    // In newer supabase_flutter versions this parameter is called
    // publishableKey. It takes the same public key.
    publishableKey: supabaseAnonKey,
  );

  runApp(const SmartAttendanceApp());
}

class SmartAttendanceApp extends StatelessWidget {
  const SmartAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Attendance',
      debugShowCheckedModeBanner: false,
      // The app's look (lib/core/theme.dart). Follows the phone's
      // light / dark mode setting.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // Splash first; it then opens AuthGate, which decides whether to
      // show Login or the role's Home screen (logic unchanged).
      home: const SplashScreen(),
    );
  }
}
