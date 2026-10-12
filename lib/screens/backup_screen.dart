import 'dart:io';

import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/services/auto_sync_service.dart';
import 'package:digitalkhata/services/backup_file.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/backup_frequency_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// Backup & restore for the signed-in account. The account is shown as
/// information only: it is always the login account, never chosen here.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with SingleTickerProviderStateMixin {
  bool _backingUp = false;
  bool _connecting = false;
  bool _fileBusy = false;
  late final AnimationController _headerMotion;

  @override
  void initState() {
    super.initState();
    _headerMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _headerMotion.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.payable : AppColors.receivable,
          content: Text(message),
        ),
      );
  }

  Future<void> _backupNow(AutoSyncService sync) async {
    if (_backingUp || sync.isBusy) return;
    setState(() => _backingUp = true);
    final err = await sync.syncNowManual();
    if (!mounted) return;
    setState(() => _backingUp = false);
    if (err == null) {
      _snack('Backup complete. Your data is safe.');
    } else {
      _snack(err, error: true);
    }
  }

  Future<void> _chooseFrequency(AutoSyncService sync) async {
    final choice = await showBackupFrequencyPicker(
      context,
      current: sync.frequency,
    );
    if (choice == null) return;
    await sync.setFrequency(choice);
    _snack('Backup frequency set to ${choice.label}.');
  }

  Future<void> _restore(AutoSyncService sync) async {
    final provider = context.read<Dbprovider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restore_rounded),
        title: const Text('Restore backup?'),
        content: const Text(
          'Your data on this phone will be replaced with the latest backup '
          'from your account. What is on the phone now is kept as a safety '
          'copy, so you can undo the restore from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.payable,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final status = ValueNotifier<String>('Restoring backup…');
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Restoring backup'),
          content: ListenableBuilder(
            listenable: Listenable.merge([sync, status]),
            builder: (_, _) => _TransferProgress(
              value: sync.progress,
              label: sync.progressLabel ?? status.value,
            ),
          ),
        ),
      ),
    );

    final err = await provider.restoreFromCloud(
      onStatus: (m) => status.value = m,
    );
    navigator.pop();
    status.dispose();
    if (err == null) {
      _snack('Backup restored successfully.');
    } else {
      _snack(err, error: true);
    }
  }

  // ==========================================================
  // BACKUP FILE (export / import)
  // ==========================================================

  /// Larger than any real khata; stops a wrong file from filling memory.
  static const int _maxImportBytes = 200 * 1024 * 1024;

  Future<void> _exportFile(AutoSyncService sync) async {
    if (_fileBusy) return;
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: const Text('Save to phone'),
              subtitle: const Text('Choose a folder, e.g. Downloads'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              subtitle: const Text('WhatsApp, Gmail, Google Drive, …'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (how == null || !mounted) return;

    setState(() => _fileBusy = true);
    try {
      final bytes = await sync.exportBackupBytes();
      final name = backupFileName(DateTime.now());
      if (how == 'save') {
        final saved = await FilePicker.saveFile(fileName: name, bytes: bytes);
        if (saved != null) _snack('Backup file saved: $name');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, name));
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/octet-stream')],
            subject: 'Easy Khata backup',
          ),
        );
      }
    } on BackupFileException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      debugPrint('Backup file export failed: $e');
      _snack(
        'The backup file could not be exported. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<void> _importFile(AutoSyncService sync) async {
    if (_fileBusy || sync.isBusy) return;
    setState(() => _fileBusy = true);
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null || !mounted) return;
      if ((await picked.length() ?? 0) > _maxImportBytes) {
        throw const BackupFileException(
          'This file is too large to be an Easy Khata backup.',
        );
      }

      // Verified before anything on the phone is touched.
      final bytes = await picked.readAsBytes();
      final incoming = await sync.inspectBackupBytes(bytes);
      final current = await sync.localSummary();
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.upload_file_rounded),
          title: const Text('Import this backup?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The file is complete and contains ${incoming.description}.',
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 12),
              Text(
                current.isEmpty
                    ? 'It will be loaded into the account you are signed in '
                          'with.'
                    : 'It will replace what is on this phone now '
                          '(${current.description}).',
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 12),
              const Text(
                'Supplier and community records from older backups, including '
                'their history, are permanently removed when imported.',
                style: TextStyle(height: 1.45),
              ),
              if (current.unsettled > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${current.unsettled} khata(s) on this phone still have '
                    'an amount to get or to pay. They are not lost: a safety '
                    'copy is kept and "Undo" on this screen brings them back.',
                    style: const TextStyle(height: 1.4, fontSize: 13.5),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      final err = await sync.importBackupBytes(bytes);
      if (err == null) {
        _snack(
          'Backup file imported. Your khata is ready. Tap “Back up now” to '
          'upload it to Easy Khata’s Google Drive backup.',
        );
      } else {
        _snack(err, error: true);
      }
    } on BackupFileException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      debugPrint('Backup file import failed: $e');
      _snack(
        'The file could not be read. Your data was not changed.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<void> _undoReplace(AutoSyncService sync) async {
    if (_fileBusy || sync.isBusy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.undo_rounded),
        title: const Text('Bring back previous data?'),
        content: const Text(
          'The data this phone had before the last restore or import comes '
          'back. The data shown now is kept as the new safety copy, so this '
          'can be undone as well.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bring back'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _fileBusy = true);
    final err = await sync.undoLastReplace();
    if (!mounted) return;
    setState(() => _fileBusy = false);
    if (err == null) {
      _snack('Previous data is back.');
    } else {
      _snack(err, error: true);
    }
  }

  Widget _fileCard(AutoSyncService sync, {required bool busy}) {
    final safetyCopyAt = sync.safetyCopyAt;
    final disabled = busy || _fileBusy;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            enabled: !disabled,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            leading: const Icon(Icons.file_download_outlined),
            title: const Text(
              'Export backup file',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Your complete khata in one file'),
            trailing: _fileBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: () => _exportFile(sync),
          ),
          const Divider(height: 1),
          ListTile(
            enabled: !disabled,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text(
              'Import backup file',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('Load an exported file into this account'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _importFile(sync),
          ),
          if (safetyCopyAt != null) ...[
            const Divider(height: 1),
            ListTile(
              enabled: !disabled,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18),
              leading: const Icon(Icons.undo_rounded),
              title: const Text(
                'Undo last restore / import',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Data replaced on ${formatDateTime(safetyCopyAt)} is kept',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _undoReplace(sync),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.select<Dbprovider, AutoSyncService?>(
      (db) => db.autoSync,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: sync == null
          ? const Center(child: Text('Please sign in to use backup.'))
          : ListenableBuilder(
              listenable: sync,
              builder: (context, _) => _buildBody(sync),
            ),
    );
  }

  Future<void> _connectDrive(AutoSyncService sync) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final err = await sync.connectGoogleDrive();
    if (!mounted) return;
    setState(() => _connecting = false);
    if (err == null) {
      _snack('Google Drive connected. Your backups will be saved there.');
    } else {
      _snack(err, error: true);
    }
  }

  Future<void> _allowDrive(AutoSyncService sync) async {
    final err = await sync.grantDriveAccess();
    if (err != null) _snack(err, error: true);
  }

  static String _gb(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  Widget _buildBody(AutoSyncService sync) {
    final driveEmail = sync.driveEmail;
    final busy = _backingUp || sync.status == SyncStatus.syncing;
    final blocked =
        sync.status == SyncStatus.needsReLogin ||
        sync.status == SyncStatus.needsDriveConnection ||
        sync.status == SyncStatus.needsPermission;
    final transferring = sync.isBusy && sync.progress != null;
    final quota = sync.driveQuota;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _BackupHero(
          motion: _headerMotion,
          status: sync.status,
          message: sync.message,
          busy: busy,
        ),
        const SizedBox(height: 14),

        // ---- backup account (information only) ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.add_to_drive_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Backup account · Google Drive',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            driveEmail ?? 'Not connected yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  driveEmail == null
                      ? 'Connect a Google account once. It stays linked to '
                            'your Easy Khata account, and every backup is saved '
                            'in its Google Drive.'
                      : 'Your backup automatically uses the Google Drive of '
                            'your signed-in account.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.muted,
                  ),
                ),
                if (sync.status == SyncStatus.needsDriveConnection) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _connecting ? null : () => _connectDrive(sync),
                    icon: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.link_rounded),
                    label: Text(
                      _connecting
                          ? 'Connecting…'
                          : (driveEmail == null
                                ? 'Connect Google Drive'
                                : 'Reconnect $driveEmail'),
                    ),
                  ),
                ] else if (sync.status == SyncStatus.needsPermission) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _allowDrive(sync),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Allow Google Drive access'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ---- Drive full / almost full ----
        if (sync.status == SyncStatus.driveFull)
          const _Notice(
            icon: Icons.cloud_off_rounded,
            color: AppColors.payable,
            background: Color(0xFFFEF2F2),
            title: 'Google Drive is full',
            text:
                'There is not enough space in your Google Drive for a new '
                'backup. Your previous backup is safe. Delete files in Google '
                'Drive, Gmail or Google Photos (or get more storage), then tap '
                '"Back up now".',
          )
        else if (sync.driveAlmostFull)
          _Notice(
            icon: Icons.storage_rounded,
            color: const Color(0xFFB45309),
            background: const Color(0xFFFFFBEB),
            title: 'Google Drive is almost full',
            text:
                'Only ${_gb(quota!.freeBytes!)} is left. Free up space soon so '
                'your backups keep working.',
          ),

        if (quota != null && quota.limitBytes != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _StorageMeter(
                used: quota.usedBytes,
                limit: quota.limitBytes!,
                label:
                    '${_gb(quota.usedBytes)} of ${_gb(quota.limitBytes!)} used',
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ---- live transfer ----
        if (transferring) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _TransferProgress(
                value: sync.progress,
                label: sync.progressLabel ?? sync.message,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ---- status ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    _StatusIcon(status: sync.status),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sync.message.isEmpty ? 'Ready' : sync.message,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                _InfoRow(
                  label: 'Last backup',
                  value: sync.lastBackupAt != null
                      ? formatDateTime(sync.lastBackupAt!)
                      : 'No backup has been completed yet.',
                ),
                const SizedBox(height: 10),
                _InfoRow(
                  label: 'Next backup',
                  value: sync.frequency == null
                      ? 'Choose a backup frequency'
                      : (!sync.enabled
                            ? 'Only when you tap "Back up now"'
                            : _nextText(sync.nextBackupAt)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (sync.status == SyncStatus.needsReLogin)
          const _Notice(
            icon: Icons.info_outline_rounded,
            color: Color(0xFFC2410C),
            background: Color(0xFFFFF7ED),
            title: 'Backup paused',
            text: 'Your session ended. Log out and sign in again to resume.',
          ),

        // ---- frequency ----
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 6,
            ),
            leading: const Icon(
              Icons.event_repeat_rounded,
              color: AppColors.navy,
            ),
            title: const Text(
              'Automatic backup',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              sync.frequency?.description ?? 'Not set yet. Tap to choose.',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sync.frequency?.label ?? 'Choose',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ),
            onTap: () => _chooseFrequency(sync),
          ),
        ),
        const SizedBox(height: 20),

        FilledButton.icon(
          onPressed: busy || blocked ? null : () => _backupNow(sync),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(
            busy
                ? (sync.progress != null
                      ? 'Backing up ${(sync.progress! * 100).round()}%'
                      : 'Creating backup…')
                : 'Back up now',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy || blocked ? null : () => _restore(sync),
          icon: const Icon(Icons.cloud_download_outlined),
          label: const Text('Restore backup'),
        ),
        const SizedBox(height: 18),
        const Text(
          'Only complete backups are saved. If the connection drops during a '
          'backup, your previous backup is kept unchanged and the unfinished '
          'one is discarded.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        const Text(
          'Backups are stored in a private app folder of your Google Drive '
          'that only Easy Khata can open. To use a different account, log out '
          'and sign in with it.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
        ),

        // ---- backup file: works without Google Drive ----
        const SizedBox(height: 28),
        const Text(
          'Backup file',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Export the .ekb file and save or share it to the Google Drive you '
          'want to use. On the new phone, sign in to Easy Khata, choose '
          '“Import backup file”, and select the .ekb from Drive. Import '
          'replaces that phone’s khata; an undo safety copy is kept.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        _fileCard(sync, busy: busy),
        const SizedBox(height: 10),
        const Text(
          'The file holds your customers and their entries. Keep it private '
          'and share it only with yourself.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.muted),
        ),
      ],
    );
  }

  static String _nextText(DateTime? next) {
    if (next == null) return '—';
    if (!next.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return 'Now, when online';
    }
    return formatDateTime(next);
  }
}

class _BackupHero extends StatelessWidget {
  const _BackupHero({
    required this.motion,
    required this.status,
    required this.message,
    required this.busy,
  });

  final Animation<double> motion;
  final SyncStatus status;
  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      SyncStatus.idle => (
        Icons.cloud_done_rounded,
        const Color(0xFF86EFAC),
        'Your backup is up to date',
      ),
      SyncStatus.syncing => (
        Icons.cloud_sync_rounded,
        const Color(0xFFFFD17A),
        'Backup in progress',
      ),
      SyncStatus.pending => (
        Icons.cloud_upload_rounded,
        const Color(0xFFFFD17A),
        'Backup waiting to run',
      ),
      SyncStatus.offline => (
        Icons.cloud_off_rounded,
        const Color(0xFFFFD17A),
        'You are currently offline',
      ),
      SyncStatus.disabled => (
        Icons.cloud_off_rounded,
        const Color(0xFFCBD5E1),
        'Automatic backup is off',
      ),
      SyncStatus.needsDriveConnection => (
        Icons.add_to_drive_rounded,
        const Color(0xFFBFDBFE),
        'Connect Google Drive to begin',
      ),
      SyncStatus.needsPermission => (
        Icons.verified_user_outlined,
        const Color(0xFFBFDBFE),
        'Allow Drive access to continue',
      ),
      SyncStatus.driveFull => (
        Icons.cloud_off_rounded,
        const Color(0xFFFCA5A5),
        'Google Drive storage is full',
      ),
      SyncStatus.needsReLogin => (
        Icons.lock_clock_rounded,
        const Color(0xFFFDBA74),
        'Sign in again to resume backups',
      ),
      SyncStatus.error => (
        Icons.sync_problem_rounded,
        const Color(0xFFFCA5A5),
        'Backup needs your attention',
      ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF243B5A), AppColors.navy, Color(0xFF0B1220)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -45,
              top: -58,
              child: _BackupOrb(size: 180, opacity: 0.055),
            ),
            Positioned(
              right: 42,
              bottom: -86,
              child: _BackupOrb(size: 170, opacity: 0.04),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 14,
                                color: Color(0xFF9FC5FF),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'BACKUP & RESTORE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Your khata,\nprotected.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            height: 1.08,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            AnimatedBuilder(
                              animation: motion,
                              builder: (context, child) => Transform.scale(
                                scale: busy ? 0.92 + motion.value * 0.16 : 1,
                                child: child,
                              ),
                              child: Icon(icon, color: color, size: 17),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                busy ? 'Keeping your data in sync' : label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (message.isNotEmpty &&
                            status != SyncStatus.idle) ...[
                          const SizedBox(height: 5),
                          Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 11.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: motion,
                    builder: (context, _) {
                      final pulse = 1 + motion.value * 0.06;
                      return SizedBox(
                        width: 104,
                        height: 112,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: pulse,
                              child: Container(
                                width: 98,
                                height: 98,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Icon(icon, size: 36, color: color),
                            ),
                            Positioned(
                              right: 7,
                              bottom: 13,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: AppColors.navy,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF243B5A),
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  busy
                                      ? Icons.sync_rounded
                                      : Icons.check_rounded,
                                  size: 13,
                                  color: busy
                                      ? const Color(0xFFFFD17A)
                                      : const Color(0xFF86EFAC),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupOrb extends StatelessWidget {
  const _BackupOrb({required this.size, required this.opacity});

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
    ),
  );
}

class _TransferProgress extends StatelessWidget {
  const _TransferProgress({required this.value, required this.label});

  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final percent = value == null ? null : (value! * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (percent != null)
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: AppColors.receivable,
            backgroundColor: AppColors.border,
          ),
        ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (status) {
      SyncStatus.idle => (Icons.cloud_done_rounded, AppColors.receivable),
      SyncStatus.syncing => (Icons.sync_rounded, AppColors.navy),
      SyncStatus.pending => (Icons.cloud_upload_rounded, AppColors.accent),
      SyncStatus.offline => (Icons.cloud_off_rounded, AppColors.accent),
      SyncStatus.disabled => (Icons.cloud_off_rounded, AppColors.muted),
      SyncStatus.needsDriveConnection || SyncStatus.needsPermission => (
        Icons.add_to_drive_rounded,
        AppColors.navy,
      ),
      SyncStatus.driveFull => (Icons.cloud_off_rounded, AppColors.payable),
      SyncStatus.needsReLogin ||
      SyncStatus.error => (Icons.sync_problem_rounded, AppColors.payable),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(height: 1.4, color: AppColors.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google Drive storage bar.
class _StorageMeter extends StatelessWidget {
  const _StorageMeter({
    required this.used,
    required this.limit,
    required this.label,
  });

  final int used;
  final int limit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final color = ratio >= 0.95
        ? AppColors.payable
        : (ratio >= 0.85 ? AppColors.accent : AppColors.receivable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.storage_rounded, size: 20, color: AppColors.muted),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Google Drive storage',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${(ratio * 100).round()}%',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            color: color,
            backgroundColor: AppColors.border,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
      ],
    );
  }
}
