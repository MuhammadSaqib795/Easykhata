import 'dart:async';

import 'package:digitalkhata/customerpagedaa.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/screens/backup_screen.dart';
import 'package:digitalkhata/screens/sales_history_screen.dart';
import 'package:digitalkhata/services/auto_sync_service.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/tabs/home_tab.dart';
import 'package:digitalkhata/tabs/products_tab.dart';
import 'package:digitalkhata/tabs/sale_tab.dart';
import 'package:digitalkhata/tabs/settings_tab.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/product_editor.dart';
import 'package:digitalkhata/tabs/tab1/customer_details.dart';
import 'package:digitalkhata/tabs/tab1/tab1.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/backup_frequency_picker.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Home of the app: three tabs (Khata, POS, Settings) under one app bar.
class Mainscreen extends StatefulWidget {
  const Mainscreen({super.key});

  @override
  State<Mainscreen> createState() => _MainscreenState();
}

class _MainscreenState extends State<Mainscreen> {
  static const _home = 0;
  static const _khata = 1;
  static const _sale = 2;
  static const _products = 3;

  static const _titles = [
    AppBrand.name,
    'Khata',
    'New sale',
    'Products',
    'More',
  ];
  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Khata'),
    (Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Sale'),
    (Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Products'),
    (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
  ];

  int _tab = _home;

  /// Bumped each time Home is opened, so its figures are read again.
  int _homeRefresh = 0;

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = index;
      if (index == _home) _homeRefresh++;
    });
  }

  Widget? _floatingAction() {
    switch (_tab) {
      case _home:
        return FloatingActionButton.extended(
          onPressed: () => _select(_sale),
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('New sale'),
        );
      case _khata:
        return FloatingActionButton.extended(
          onPressed: () => _open(const AddCustomerPage()),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add customer'),
        );
      case _products:
        return FloatingActionButton.extended(
          onPressed: () => showProductEditor(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add product'),
        );
    }
    return null;
  }
  final ValueNotifier<int?> _reminderTap =
      PaymentReminderService.instance.tappedTransactionId;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// Drive full / almost full / not connected: shown above the tabs.
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
    return _Banner(
      icon: icon,
      background: bg,
      foreground: fg,
      text: text,
      actionLabel: action,
      onAction: () => _open(const BackupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch only what this screen shows. Saving an entry changes none of
    // these, so the whole main screen is not rebuilt behind every save.
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

    final wide = isWideLayout(context);
    final content = Column(
        children: [
          if (operationError != null)
            _Banner(
              icon: Icons.error_outline,
              background: const Color(0xFFFEF2F2),
              foreground: AppColors.payable,
              text: operationError,
              actionLabel: 'Dismiss',
              onAction: context.read<Dbprovider>().clearOperationError,
            ),
          if (sync != null)
            ListenableBuilder(
              listenable: sync,
              builder: (context, _) => _backupBanner(sync),
            ),
          Expanded(
            // Keeps every tab alive, so a half-built sale or a search is
            // still there after a look at another tab.
            child: IndexedStack(
              index: _tab,
              children: [
                HomeTab(
                  refreshToken: _homeRefresh,
                  onNewSale: () => _select(_sale),
                ),
                const Tab1(),
                SaleTab(onGoToProducts: () => _select(_products)),
                const ProductsTab(),
                const SettingsTab(),
              ],
            ),
          ),
        ],
      );

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          if (_tab == _sale)
            IconButton(
              tooltip: 'Sales history',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => _open(const SalesHistoryScreen()),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: wide
          ? Row(
              children: [
                // Landscape phones are wide but short: icons only then.
                LayoutBuilder(
                  builder: (context, box) => NavigationRail(
                    selectedIndex: _tab,
                    backgroundColor: Colors.white,
                    indicatorColor: AppColors.navy.withValues(alpha: 0.1),
                    labelType: box.maxHeight < 480
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    onDestinationSelected: _select,
                    destinations: [
                      for (final (icon, selected, label) in _destinations)
                        NavigationRailDestination(
                          icon: Icon(icon),
                          selectedIcon: Icon(selected),
                          label: Text(label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      floatingActionButton: _floatingAction(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _select,
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: label,
                  ),
              ],
            ),
    );
  }
}

/// One-line notice with a single action, shown above the tabs.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, height: 1.35, color: foreground),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: foreground),
            child: Text(
              actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
