import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/screens/backup_screen.dart';
import 'package:digitalkhata/screens/payment_reminder_settings_screen.dart';
import 'package:digitalkhata/screens/sales_history_screen.dart';
import 'package:digitalkhata/services/auto_sync_service.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/logoutbutton.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings tab: the signed-in account and everything that is not daily work
/// (reminders, backup, sales history, log out).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static String _backupStatus(AutoSyncService sync) => switch (sync.status) {
    SyncStatus.syncing => 'Backing up now…',
    SyncStatus.idle => 'Backed up to Google Drive',
    SyncStatus.pending => 'Changes waiting to be backed up',
    SyncStatus.offline => 'Offline · backs up when connected',
    SyncStatus.needsReLogin => 'Sign in again to continue backups',
    SyncStatus.needsDriveConnection => 'Google Drive is not connected',
    SyncStatus.needsPermission => 'Google Drive access is needed',
    SyncStatus.driveFull => 'Google Drive is full',
    SyncStatus.error => 'The last backup failed',
    SyncStatus.disabled => 'Automatic backup is off',
  };

  @override
  Widget build(BuildContext context) {
    final sync = context.select<Dbprovider, AutoSyncService?>(
      (db) => db.autoSync,
    );
    final user = FirebaseAuth.instance.currentUser;
    final name = (user?.displayName ?? '').trim();
    final email = user?.email ?? '';

    void open(Widget screen) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              AppAvatar(
                name: name.isEmpty ? email : name,
                size: 52,
                onDark: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your account' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _SectionLabel('KHATA'),
        _Group(
          children: [
            _SettingTile(
              icon: Icons.notifications_active_outlined,
              title: 'Payment reminders',
              subtitle: 'Alert times and a test notification',
              onTap: () => open(const PaymentReminderSettingsScreen()),
            ),
          ],
        ),
        const _SectionLabel('POINT OF SALE'),
        _Group(
          children: [
            _SettingTile(
              icon: Icons.receipt_long_outlined,
              title: 'Sales history',
              subtitle: 'Past sales and today’s total',
              onTap: () => open(const SalesHistoryScreen()),
            ),
          ],
        ),
        const _SectionLabel('DATA'),
        _Group(
          children: [
            if (sync == null)
              _SettingTile(
                icon: Icons.cloud_outlined,
                title: 'Backup & restore',
                subtitle: 'Google Drive backup',
                onTap: () => open(const BackupScreen()),
              )
            else
              ListenableBuilder(
                listenable: sync,
                builder: (context, _) => _SettingTile(
                  icon: Icons.cloud_outlined,
                  title: 'Backup & restore',
                  subtitle: _backupStatus(sync),
                  onTap: () => open(const BackupScreen()),
                ),
              ),
          ],
        ),
        const _SectionLabel('ACCOUNT'),
        _Group(
          children: [
            _SettingTile(
              icon: Icons.logout_rounded,
              title: 'Log out',
              subtitle: 'Your data stays on this phone and in your backup',
              color: AppColors.payable,
              onTap: () => Logoutbutton.logout(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        letterSpacing: 1,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = AppColors.navy,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 21),
    ),
    title: Text(
      title,
      style: TextStyle(fontWeight: FontWeight.w700, color: color),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
    onTap: onTap,
  );
}
