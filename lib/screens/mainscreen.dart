import 'dart:async';

import 'package:digitalkhata/customerpagedaa.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/services/auto_sync_service.dart';
import 'package:digitalkhata/screens/backup_screen.dart';
import 'package:digitalkhata/screens/payment_reminder_settings_screen.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/tabs/tab1/customer_details.dart';
import 'package:digitalkhata/tabs/tab1/tab1.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/backup_frequency_picker.dart';
import 'package:digitalkhata/widgets/brand.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/logoutbutton.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class Mainscreen extends StatefulWidget {
  const Mainscreen({super.key});

  @override
  State<Mainscreen> createState() => _MainscreenState();
}

class _MainscreenState extends State<Mainscreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;
  final ValueNotifier<int?> _reminderTap =
      PaymentReminderService.instance.tappedTransactionId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _reminderTap.addListener(_openTappedReminder);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startAutoSyncAfterInitialization());
    });
  }

  /// Opens the ledger of the entry whose reminder was tapped, ready to extend
  /// its return date. Runs for taps while the app is open and, once the data
  /// has loaded, for the tap that started the app.
  Future<void> _openTappedReminder() async {
    final transactionId = _reminderTap.value;
    if (transactionId == null || !mounted) return;
    final dbProvider = context.read<Dbprovider>();
    await dbProvider.initialization;
    if (!mounted || dbProvider.initialLoadError != null) return;
    // Another call already took this tap while the data was loading.
    if (_reminderTap.value != transactionId) return;
    _reminderTap.value = null;
    final customer = await dbProvider.customerForTransaction(transactionId);
    if (customer == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Customerdetails(
          item: customer,
          extendTransactionId: transactionId,
        ),
      ),
    );
  }

  Future<void> _startAutoSyncAfterInitialization() async {
    final dbProvider = context.read<Dbprovider>();
    await dbProvider.initialization;
    if (!mounted) return;
    if (dbProvider.initialLoadError != null) return;
    unawaited(_openTappedReminder());
    await dbProvider.autoSync?.start();
    await _askBackupFrequencyIfNeeded();
  }

  /// First run for this account: ask how often to back up.
  Future<void> _askBackupFrequencyIfNeeded() async {
    final sync = context.read<Dbprovider>().autoSync;
    if (!mounted || sync == null) return;
    if (sync.needsFrequencyChoice) {
      final choice = await showBackupFrequencyPicker(context, firstTime: true);
      if (choice != null) await sync.setFrequency(choice);
    }
    await _offerDriveConnectOnce(sync);
  }

  /// E-mail accounts: ask ONE time to link Google Drive for backup. The
  /// linked account is then remembered for every future backup.
  Future<void> _offerDriveConnectOnce(AutoSyncService sync) async {
    if (!mounted || !await sync.shouldOfferDriveConnect() || !mounted) return;
    await sync.markDriveConnectOffered();
    if (!mounted) return;
    final connect = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.add_to_drive_rounded, size: 32),
        title: const Text('Back up to Google Drive'),
        content: const Text(
          'Connect a Google account once. Easy Khata will remember it and '
          'save every backup to its Google Drive automatically. You will '
          'not be asked again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (connect != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final err = await sync.connectGoogleDrive();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: err == null ? AppColors.receivable : AppColors.payable,
        content: Text(
          err ?? 'Google Drive connected. Backups are automatic now.',
        ),
      ),
    );
  }

  Future<void> _retryLocalDatabase() async {
    final dbProvider = context.read<Dbprovider>();
    await dbProvider.retryInitialization();
    if (!mounted || dbProvider.initialLoadError != null) return;
    await dbProvider.autoSync?.start();
    await _askBackupFrequencyIfNeeded();
  }

  @override
  void dispose() {
    _reminderTap.removeListener(_openTappedReminder);
    _tabController.dispose();
    super.dispose();
  }

  void _openBackup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackupScreen()),
    );
  }

  void _openPaymentReminders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PaymentReminderSettingsScreen(),
      ),
    );
  }

  /// Drive full / almost full / not connected: shown above the lists.
  Widget _backupBanner(AutoSyncService sync) {
    final (IconData icon, Color bg, Color fg, String text, String action)?
    b = switch (sync.status) {
      SyncStatus.driveFull => (
        Icons.cloud_off_rounded,
        const Color(0xFFFEF2F2),
        AppColors.payable,
        'Google Drive is full. Backups are paused; your last backup is safe.',
        'Fix',
      ),
      SyncStatus.needsDriveConnection => (
        Icons.add_to_drive_rounded,
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
        'Connect Google Drive to keep your khata backed up.',
        'Connect',
      ),
      SyncStatus.needsPermission => (
        Icons.verified_user_outlined,
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
        'Allow Google Drive access to keep your khata backed up.',
        'Allow',
      ),
      _ when sync.driveAlmostFull => (
        Icons.storage_rounded,
        const Color(0xFFFFFBEB),
        const Color(0xFFB45309),
        'Google Drive is almost full. Free up space so backups keep working.',
        'Details',
      ),
      _ => null,
    };
    if (b == null) return const SizedBox.shrink();
    final (icon, bg, fg, text, action) = b;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.35, color: fg),
            ),
          ),
          TextButton(
            onPressed: _openBackup,
            style: TextButton.styleFrom(foregroundColor: fg),
            child: Text(
              action,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ================= AUTO-SYNC STATUS =================
  Widget _syncIcon(AutoSyncService sync) {
    final Widget icon = switch (sync.status) {
      SyncStatus.syncing => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          value: sync.progress,
          strokeWidth: 2.4,
          color: Colors.white,
          backgroundColor: Colors.white24,
        ),
      ),
      SyncStatus.idle => const Icon(
        Icons.cloud_done,
        key: ValueKey('sync-idle'),
        color: Colors.white,
        size: 20,
      ),
      SyncStatus.pending => const Icon(
        Icons.cloud_upload,
        key: ValueKey('sync-pending'),
        color: Colors.amber,
        size: 20,
      ),
      SyncStatus.offline => const Icon(
        Icons.cloud_off,
        key: ValueKey('sync-offline'),
        color: Colors.amber,
        size: 20,
      ),
      SyncStatus.needsReLogin ||
      SyncStatus.needsDriveConnection ||
      SyncStatus.needsPermission ||
      SyncStatus.driveFull ||
      SyncStatus.error => const Icon(
        Icons.sync_problem,
        key: ValueKey('sync-problem'),
        color: Colors.redAccent,
        size: 20,
      ),
      SyncStatus.disabled => const Icon(
        Icons.cloud_off,
        key: ValueKey('sync-disabled'),
        color: Colors.white38,
        size: 20,
      ),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch only what this screen shows. Saving an entry changes none of
    // these, so the whole main screen is no longer rebuilt behind every save.
    final (loading, loadError, operationError, sync) = context
        .select<Dbprovider, (bool, String?, String?, AutoSyncService?)>(
          (db) => (
            db.isLoadingInitialData,
            db.initialLoadError,
            db.operationError,
            db.autoSync,
          ),
        );
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.ink,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    if (loadError != null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.storage_rounded,
          title: 'Your data could not be opened',
          message: loadError,
          actionLabel: 'Try again',
          onAction: _retryLocalDatabase,
        ),
      );
    }

    final user = _auth.currentUser;
    final firstName = (user?.displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    final greeting = firstName.isEmpty ? 'Your khata' : 'Hello, $firstName';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: _Header(
                greeting: greeting,
                email: user?.email ?? '',
                trailing: [
                  IconButton(
                    icon: const Icon(Icons.notifications_active_outlined),
                    tooltip: 'Payment reminders',
                    onPressed: _openPaymentReminders,
                  ),
                  if (sync != null)
                    ListenableBuilder(
                      listenable: sync,
                      builder: (context, _) => IconButton(
                        icon: _syncIcon(sync),
                        tooltip: 'Backup',
                        onPressed: _openBackup,
                      ),
                    ),
                  Logoutbutton(onBackup: _openBackup),
                ],
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.muted,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  splashBorderRadius: BorderRadius.circular(12),
                  tabs: const [Tab(text: 'Customers')],
                ),
              ),
            ),
          ],
          body: Column(
            children: [
              if (operationError != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.payable,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          operationError,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.payable,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: context
                            .read<Dbprovider>()
                            .clearOperationError,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                ),
              if (sync != null)
                ListenableBuilder(
                  listenable: sync,
                  builder: (context, _) => _backupBanner(sync),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [Tab1()],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      elevation: 2,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddCustomerPage()),
        );
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text(
        'Add customer',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Navy header: brand, account actions, greeting and the summary of the
/// selected tab.
class _Header extends StatelessWidget {
  const _Header({
    required this.greeting,
    required this.email,
    required this.trailing,
  });

  final String greeting;
  final String email;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF18263D), AppColors.navy, Color(0xFF0B1220)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -46,
              top: top + 18,
              child: _HeaderOrb(size: 150, opacity: 0.045),
            ),
            Positioned(
              right: 72,
              bottom: -78,
              child: _HeaderOrb(size: 138, opacity: 0.035),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, top + 8, 8, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandLockup(logoSize: 32, fontSize: 18),
                      const Spacer(),
                      ...trailing,
                    ],
                  ),
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const _Summary(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderOrb extends StatelessWidget {
  const _HeaderOrb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: opacity),
        width: 1.2,
      ),
      color: Colors.white.withValues(alpha: opacity * 0.45),
    ),
  );
}

/// Customer totals from the provider's existing figures.
class _Summary extends StatelessWidget {
  const _Summary();

  @override
  Widget build(BuildContext context) {
    final (a, b, count) = context.select<Dbprovider, (double, double, int)>(
      (db) => (db.customerToReceive, db.customerToPay, db.allCustomers.length),
    );
    final stats = <(String, String, Color)>[
      ('TO RECEIVE', formatMoney(a), const Color(0xFF86EFAC)),
      ('TO PAY', formatMoney(b), const Color(0xFFFCA5A5)),
      ('Customers', '$count', Colors.white),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.085),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 34,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stats[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.18),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Text(
                          stats[i].$2,
                          key: ValueKey('${stats[i].$1}-${stats[i].$2}'),
                          style: TextStyle(
                            color: stats[i].$3,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);

  final TabBar tabBar;
  static const double _vPad = 10;

  @override
  double get minExtent => tabBar.preferredSize.height + _vPad * 2 + 8;
  @override
  double get maxExtent => tabBar.preferredSize.height + _vPad * 2 + 8;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, _vPad, 16, _vPad),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(3),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}
