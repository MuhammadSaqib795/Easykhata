import 'package:digitalkhata/authentication/auth_service.dart';
import 'package:digitalkhata/authentication/loginscreen.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Account menu: signed-in account (information only), backup, logout.
class Logoutbutton extends StatelessWidget {
  const Logoutbutton({super.key, this.onBackup});

  final VoidCallback? onBackup;

  /// Stops this user's backup, closes their data, then signs out. The next
  /// login decides the next backup owner.
  static Future<void> logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'Your data stays safe on this phone and in your Google Drive backup. '
          'Sign in again with the same account to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final provider = context.read<Dbprovider>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 18),
              Text('Signing out…'),
            ],
          ),
        ),
      ),
    );
    try {
      await provider.closeSession();
      await AuthService.instance.signOut();
    } catch (e) {
      debugPrint('Sign-out problem: $e');
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;
    return PopupMenuButton<String>(
      color: Colors.white,
      tooltip: 'Account',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (value) {
        if (value == 'logout') logout(context);
        if (value == 'backup') onBackup?.call();
      },
      icon: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.more_horiz_rounded, color: Colors.white),
      ),
      itemBuilder: (context) => [
        if (email != null)
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Signed in as',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
                Text(
                  email,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        if (onBackup != null)
          const PopupMenuItem(
            value: 'backup',
            child: Row(
              children: [
                Icon(Icons.cloud_outlined),
                SizedBox(width: 10),
                Text('Backup & restore'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded),
              SizedBox(width: 10),
              Text('Log out'),
            ],
          ),
        ),
      ],
    );
  }
}
