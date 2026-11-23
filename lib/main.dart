import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/auth_gate.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      // AuthGate decides whether to show Login or the role's Home screen.
      home: const AuthGate(),
    );
  }
}
