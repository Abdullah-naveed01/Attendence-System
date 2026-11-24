import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/auth_service.dart';
import 'admin_students_screen.dart';
import 'student_devices_screen.dart';
import 'teachers_screen.dart';

// Admin Home: the admin's tools. Only users with role 'admin' reach this
// screen (AuthGate decides), and the server checks the role again.
// Proxy alerts are NOT shown here: they go only to the course's teacher.
// The admin can still reset a student's phone from the Students screen.
class AdminHome extends StatelessWidget {
  final Profile profile;
  const AdminHome({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile.fullName.isEmpty ? profile.email : profile.fullName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome, $name', style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          _toolCard(
            context,
            icon: Icons.co_present,
            title: 'Teachers',
            subtitle: 'Add, view and remove teachers',
            screen: const TeachersScreen(),
          ),
          _toolCard(
            context,
            icon: Icons.people,
            title: 'Students',
            subtitle: 'Add, enroll, reset phone, delete',
            screen: const AdminStudentsScreen(),
          ),
          _toolCard(
            context,
            icon: Icons.phonelink_setup,
            title: 'Student Devices',
            subtitle: 'Registered phones and Reset Device',
            screen: const StudentDevicesScreen(),
          ),
        ],
      ),
    );
  }

  Widget _toolCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        ),
      ),
    );
  }
}
