import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../widgets_root_back_scope.dart';
import 'admin_mobile_shell.dart';

/// Native Android admin experience — now just the shared pill-bottom-nav
/// mobile shell (see admin_mobile_shell.dart), wrapped in RootBackScope
/// since this is the root screen for the admin session on Android.
class AdminDashboardScreen extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;
  const AdminDashboardScreen({super.key, required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return RootBackScope(
      child: AdminMobileShell(user: user, onLogout: onLogout),
    );
  }
}
