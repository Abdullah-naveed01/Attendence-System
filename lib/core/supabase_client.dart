import 'package:supabase_flutter/supabase_flutter.dart';

// Short way to reach the Supabase client from anywhere in the app.
// Write `supabase` instead of `Supabase.instance.client`.
SupabaseClient get supabase => Supabase.instance.client;
