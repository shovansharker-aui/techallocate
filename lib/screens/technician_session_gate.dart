import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/technician_session_service.dart';
import '../services/notify_service.dart';
import 'admin_dashboard_screen.dart';
import 'admin_web_dashboard_screen.dart';
import 'water_plant_overview_screen.dart';
import 'login_screen.dart';
import 'technician_screen.dart';
import '../widgets_root_back_scope.dart';
import '../utils/app_colors.dart';

class UserSessionGate extends StatefulWidget {
  final String docId;

  const UserSessionGate({super.key, required this.docId});

  @override
  State<UserSessionGate> createState() => _UserSessionGateState();
}

class _UserSessionGateState extends State<UserSessionGate> {
  bool _notifyChecked = false;

  void _maybeCheckNotify(AppUser user) {
    if (_notifyChecked) return;
    _notifyChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notifyService.checkAndShow(context, role: user.role.toLowerCase());
    });
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again with your Employee ID and PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    await TechnicianSessionService().clear();
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.docId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _ErrorScreen(
            message: 'Unable to load employee profile.\n${snapshot.error}',
            onLogout: () => _logout(context),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _ErrorScreen(
            message: 'The employee profile could not be found.',
            onLogout: () => _logout(context),
          );
        }

        final user = AppUser.fromMap(widget.docId, snapshot.data!.data()!);
        // Runs exactly once per session (guarded by _notifyChecked)
        // rather than in initState, specifically because the role isn't
        // known until this first snapshot arrives.
        _maybeCheckNotify(user);

        switch (user.role.toLowerCase()) {
          case 'admin':
            if (kIsWeb) {
              return RootBackScope(
                child: AdminWebDashboardScreen(
                  user: user,
                  onLogout: () => _logout(context),
                ),
              );
            }
            return AdminDashboardScreen(
              user: user,
              onLogout: () => _logout(context),
            );
          case 'technician':
            return TechnicianScreen(
              user: user,
              onLogout: () => _logout(context),
            );
          case 'water_plant_manager':
            // Now sees the same live overview dashboard admin sees, plus
            // its own logout button (this is a root screen for this
            // account, unlike for admin) and a button to reach the duty
            // allocation editing table.
            return RootBackScope(
              title: 'Exit TechAllocate?',
              child: WaterPlantOverviewScreen(
                onLogout: () => _logout(context),
                showDutyAllocationButton: true,
                showSwitchingToggle: false,
              ),
            );
          default:
            return _ErrorScreen(
              message: 'Invalid employee role: ${user.role}',
              onLogout: () => _logout(context),
            );
        }
      },
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onLogout;

  const _ErrorScreen({required this.message, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.danger),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onLogout,
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Kept as a compatibility wrapper so any existing import of
// TechnicianSessionGate will continue to compile.
class TechnicianSessionGate extends UserSessionGate {
  const TechnicianSessionGate({super.key, required super.docId});
}
