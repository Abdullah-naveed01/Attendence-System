import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/rpc_error.dart';
import '../../core/supabase_client.dart';
import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../admin/admin_home.dart';
import '../student/student_home.dart';
import '../teacher/teacher_home.dart';
import 'login_screen.dart';

// The app's entry point after startup. It listens for login/logout:
// - nobody logged in -> LoginScreen
// - logged in        -> RoleRouter (opens the Home screen for the user's role)
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;

        if (session == null) {
          // Logged out: close any banner of the previous account
          // (e.g. a teacher's proxy alert) so the next user never sees it.
          _clearBanners(context);
          return const LoginScreen();
        }

        // The key is the user id, so the role reloads if a different user logs in.
        return RoleRouter(key: ValueKey(session.user.id));
      },
    );
  }
}

// Closes every open SnackBar banner (after the current frame is drawn).
void _clearBanners(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  });
}

// Reads the role from the profiles table and shows that role's Home screen.
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final _authService = AuthService();
  late Future<Profile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.getMyProfile();
    // A new user logged in: no banner from the previous account.
    _clearBanners(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        // Still loading
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Profile could not be loaded (network or RLS problem)
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load your profile.\n'
                      '${friendlyError(snapshot.error ?? 'No data')}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _authService.signOut(),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final profile = snapshot.data!;
        switch (profile.role) {
          case 'admin':
            return AdminHome(profile: profile);
          case 'teacher':
            return TeacherHome(profile: profile);
          default:
            return StudentHome(profile: profile);
        }
      },
    );
  }
}
