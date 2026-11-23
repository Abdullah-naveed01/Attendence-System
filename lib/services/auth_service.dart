import '../core/supabase_client.dart';
import '../models/profile.dart';

// Login, logout, and loading the user's own profile (which holds the role).
// Screens do not call Supabase directly; they call this service.
class AuthService {
  // Log in with email and password. Throws AuthException if wrong.
  Future<void> signIn(String email, String password) async {
    await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // Load the logged-in user's row from profiles (it contains the role).
  // Because of RLS, a student can only read their own row — which is all we need.
  Future<Profile> getMyProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not logged in');
    }

    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();

    return Profile.fromMap(data);
  }
}
