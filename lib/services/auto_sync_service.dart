import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:digitalkhata/authentication/auth_service.dart';
import 'package:digitalkhata/db/dbhelper.dart';
import 'package:digitalkhata/services/backup_file.dart';
import 'package:digitalkhata/services/connectivity_policy.dart';
import 'package:digitalkhata/services/backup_schedule.dart';
import 'package:digitalkhata/services/cloud_services.dart';
import 'package:digitalkhata/services/local_data_fingerprint.dart';
import 'package:digitalkhata/services/sync_decision.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

String _fingerprintInBackground(Map<String, List<Map<String, Object?>>> data) =>
    fingerprintLocalTables(data);

enum SyncStatus {
  /// Automatic backup is off ("Never") or no frequency chosen yet.
  disabled,

  /// The session no longer belongs to the backup owner; sign in again.
  needsReLogin,

  /// No Google Drive linked yet, or its session must be restored (one tap).
  needsDriveConnection,

  /// The linked Google account has not allowed Drive backup.
  needsPermission,

  /// Google Drive has no free space; the previous backup is kept.
  driveFull,

  /// Local and cloud are identical.
  idle,

  /// A sync is running right now.
  syncing,

  /// There are local changes waiting to be uploaded.
  pending,

  /// No internet. Changes are kept and uploaded once back online.
  offline,

  /// Last attempt failed for another reason. Will retry automatically.
  error,
}

/// Thrown when the active local database no longer belongs to [ownerUid]
/// (the user logged out or another user logged in mid-operation).
class _OwnerChanged implements Exception {
  const _OwnerChanged();
}

/// Keeps ONE app user's local SQLite database and cloud backup in
/// sync on the schedule the user chose (hourly, daily, weekly, monthly,
/// yearly or never):
///
///  * when a backup is due and data changed, a complete snapshot is uploaded;
///    the backup only switches to it after every piece arrived,
///  * a backup missed while offline runs as soon as internet returns,
///  * newer data from another device is downloaded at a scheduled round
///    (only when there are no unsent local changes, otherwise the cloud copy
///    is preserved as a conflict backup).
///
/// The backup owner is always [ownerUid], the authenticated app user. A new
/// instance is created on every login and shut down on logout; there is no
/// separate backup account and nothing to choose.
class AutoSyncService extends ChangeNotifier with WidgetsBindingObserver {
  AutoSyncService({
    required this.ownerUid,
    required Dbhelper dbhelper,
    required DriveBackupService cloud,
    required Future<void> Function() reloadData,
  }) : _dbhelper = dbhelper,
       _cloud = cloud,
       _reloadData = reloadData;

  /// Firebase UID of the app user whose data this instance backs up.
  final String ownerUid;
  final Dbhelper _dbhelper;
  final DriveBackupService _cloud;
  final Future<void> Function() _reloadData;

  // ---- preference keys (scoped to [ownerUid], see [_key]) ----
  static const _kEnabled = 'autosync_enabled';
  static const _kFrequency = 'backup_frequency';
  static const _kDirty = 'autosync_dirty';
  static const _kLastRemoteMs = 'autosync_last_remote_ms';
  static const _kLastBackupDigest = 'autosync_last_backup_digest';
  static const _kLastSyncedAt = 'autosync_last_synced_ms';
  static const _kLastBackupAt = 'autosync_last_backup_ms';
  static const _kLastRunAt = 'autosync_last_scheduled_run_ms';

  /// Unscoped keys of older versions, including the separately chosen
  /// backup e-mail, which must not survive.
  static const _legacyKeys = [
    'autosync_account_email',
    _kEnabled,
    _kDirty,
    _kLastRemoteMs,
    _kLastBackupDigest,
    _kLastSyncedAt,
  ];

  /// How often the schedule is checked while the app is open.
  static const Duration _scheduleCheckInterval = Duration(minutes: 5);
  static const Duration _startupDelay = Duration(seconds: 5);
  static const Duration _shutdownWait = Duration(seconds: 15);
  static const Duration _connectivityProbeTimeout = Duration(seconds: 3);
  static const Duration _maximumProbeLatency = Duration(seconds: 2);
  static const int _requiredSuccessfulProbes = 2;
  static const Duration _probeInterval = Duration(milliseconds: 300);

  SharedPreferences? _prefs;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _connTimer;
  Timer? _retryTimer;
  Timer? _pollTimer;
  Timer? _startupTimer;

  bool _started = false;
  bool _stopped = false;
  bool _startupDelayElapsed = false;
  bool _syncing = false;
  Completer<void>? _syncDone;
  bool _resync = false;
  int _retryAttempt = 0;

  /// True once the full local content fingerprint was compared with the last
  /// backup in this app run. Until then every check verifies the content;
  /// afterwards checks can skip the expensive full-table scan while nothing
  /// is flagged as changed.
  bool _localVerifiedThisRun = false;

  /// The user's choice; null until they pick one (the app then asks).
  BackupFrequency? _frequency;
  bool _dirty = false;
  int _dirtyVersion = 0;
  int? _lastRemoteMs;
  String? _lastBackupDigest;
  DateTime? _lastSyncedAt;
  DateTime? _lastBackupAt;

  /// Last completed round (a backup, or a check that found the backup
  /// already up to date). The schedule counts from here.
  DateTime? _lastRunAt;

  /// When a failed round will be retried.
  DateTime? _retryAt;

  /// Google Drive storage of the linked account (last known).
  DriveQuota? _driveQuota;

  /// After a "Drive full" failure, automatic rounds pause until then.
  DateTime? _driveFullUntil;

  /// Upload / download progress 0..1 while a transfer runs, else null.
  double? _progress;
  String? _progressLabel;

  /// Set when the backup could not be reached for the signed-in user; stops
  /// background retries until the app resumes or the user signs in again.
  bool _authBlocked = false;

  SyncStatus _status = SyncStatus.idle;
  String _message = '';

  // ---- public state ----
  SyncStatus get status => _status;
  String get message => _message;
  BackupFrequency? get frequency => _frequency;

  /// The user has not chosen a backup frequency yet.
  bool get needsFrequencyChoice => _started && _frequency == null;

  /// Automatic backup is on (any frequency except Never).
  bool get enabled =>
      _frequency != null && _frequency != BackupFrequency.never;
  bool get hasPendingChanges => _dirty;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Last time a complete backup was uploaded.
  DateTime? get lastBackupAt => _lastBackupAt;

  /// When the next automatic backup is due (null when automatic backup is
  /// off). A pending retry after a failure comes first.
  DateTime? get nextBackupAt {
    if (!enabled) return null;
    if (_retryAt != null) return _retryAt;
    final last = _lastRunAt ?? _lastBackupAt;
    final now = DateTime.now();
    if (last == null) return now;
    final next = _frequency!.nextAfter(last)!;
    return next.isBefore(now) ? now : next;
  }

  DriveQuota? get driveQuota => _driveQuota;

  /// Less than 5% or 50 MB left in Google Drive.
  bool get driveAlmostFull => _driveQuota?.isAlmostFull ?? false;

  /// Google account whose Drive holds the backup (information only).
  String? get driveEmail {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != ownerUid) return null;
    return AuthService.driveEmailOf(user);
  }

  double? get progress => _progress;
  String? get progressLabel => _progressLabel;
  bool get isBusy => _syncing;

  /// E-mail of the signed-in app user, shown as information only. Always
  /// derived from the current login, never stored.
  String? get accountEmail {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid == ownerUid ? user?.email : null;
  }

  String _key(String base) => '${base}_$ownerUid';

  bool get _isDue =>
      enabled &&
      _frequency!.isDue(
        lastRun: _lastRunAt ?? _lastBackupAt,
        now: DateTime.now(),
      );

  // ==========================================================
  // LIFECYCLE
  // ==========================================================

  /// Call once the user is logged in (e.g. when the main screen opens).
  Future<void> start() async {
    if (_started || _stopped) return;

    final prefs = await _ensurePrefs();
    for (final key in _legacyKeys) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
    if (_stopped) return;

    _frequency = BackupFrequency.fromName(prefs.getString(_key(_kFrequency)));
    // Users who had switched the old auto-sync off keep it off.
    if (_frequency == null && prefs.getBool(_key(_kEnabled)) == false) {
      _frequency = BackupFrequency.never;
    }
    _dirty = _dirty || (prefs.getBool(_key(_kDirty)) ?? false);
    _lastRemoteMs = prefs.getInt(_key(_kLastRemoteMs));
    _lastBackupDigest = prefs.getString(_key(_kLastBackupDigest));
    _lastSyncedAt = _readTime(prefs, _kLastSyncedAt);
    _lastBackupAt = _readTime(prefs, _kLastBackupAt);
    _lastRunAt = _readTime(prefs, _kLastRunAt);
    await _loadSafetyCopyTime();
    if (_stopped) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    _pollTimer = Timer.periodic(_scheduleCheckInterval, (_) => _runIfDue());
    _refreshIdleStatus();
    _startupTimer = Timer(_startupDelay, () {
      _startupDelayElapsed = true;
      _runIfDue();
    });
  }

  DateTime? _readTime(SharedPreferences prefs, String key) {
    final ms = prefs.getInt(_key(key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Logout: stops all timers and triggers and waits (bounded) for a running
  /// transfer to finish. Unsent changes stay flagged in this user's own
  /// preferences and are backed up after this user's next login.
  Future<void> shutdown() async {
    if (_stopped) return;
    _stopped = true;
    _cancelTimers();
    WidgetsBinding.instance.removeObserver(this);
    await _connSub?.cancel();
    _connSub = null;

    final running = _syncDone;
    if (_syncing && running != null) {
      try {
        await running.future.timeout(_shutdownWait);
      } on TimeoutException {
        // The running round aborts on its own once the database is closed
        // (see [_db]); an unfinished upload never becomes the backup.
      }
    }
  }

  void _cancelTimers() {
    _connTimer?.cancel();
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    _startupTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _stopped || !enabled) return;
    if (state == AppLifecycleState.resumed && _startupDelayElapsed) {
      _authBlocked = false;
      _runIfDue();
    }
  }

  @override
  void dispose() {
    _stopped = true;
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _cancelTimers();
    super.dispose();
  }

  /// Starts an automatic round when the chosen schedule says it is time.
  void _runIfDue() {
    if (_stopped || !_started || !_isDue) return;
    unawaited(syncNow(scheduled: true));
  }

  // ==========================================================
  // CHANGE TRACKING  (called by Dbprovider after every write)
  // ==========================================================

  /// Records that local data changed. The change is backed up at the next
  /// scheduled time (or by "Back up now").
  void markDirty() {
    if (_stopped) return;
    _dirty = true;
    _dirtyVersion++;
    unawaited(_persistBool(_kDirty, true));
    if (_started && !_syncing) _refreshIdleStatus();
  }

  // ==========================================================
  // USER ACTIONS
  // ==========================================================

  /// Saves the backup frequency for this account.
  Future<void> setFrequency(BackupFrequency frequency) async {
    if (_stopped) return;
    _frequency = frequency;
    _retryTimer?.cancel();
    _retryAt = null;
    _authBlocked = false;
    try {
      await (await _ensurePrefs()).setString(
        _key(_kFrequency),
        frequency.name,
      );
    } catch (e) {
      debugPrint('Pref write failed: $e');
    }
    if (!_syncing) _refreshIdleStatus();
    notifyListeners();
    if (_startupDelayElapsed) _runIfDue();
  }

  /// "Back up now" button. Returns an error message, or null on success.
  Future<String?> syncNowManual() async {
    _authBlocked = false;
    _driveFullUntil = null;
    await syncNow();
    switch (_status) {
      case SyncStatus.offline:
      case SyncStatus.needsReLogin:
      case SyncStatus.needsDriveConnection:
      case SyncStatus.needsPermission:
      case SyncStatus.driveFull:
      case SyncStatus.error:
        return _message;
      default:
        return null;
    }
  }

  /// "Connect Google Drive": links a Google account once to an e-mail
  /// account, or restores the linked account's session. Only the Google
  /// account linked to this user is ever accepted. Returns an error
  /// message, or null when Drive is ready.
  Future<String?> connectGoogleDrive() async {
    if (_stopped) return 'You are signed out.';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != ownerUid) {
        return 'Please sign in again.';
      }
      final done = AuthService.isGoogleUser(user)
          ? await AuthService.instance.reconnectGoogleDrive()
          : await AuthService.instance.linkGoogleDrive();
      if (!done) return 'Google Drive was not connected.';
    } on AuthFailure catch (e) {
      return e.message;
    }
    notifyListeners();
    return grantDriveAccess();
  }

  /// Drive permission prompt for the linked Google account (no account
  /// choice), then resumes backup. Returns an error message or null.
  Future<String?> grantDriveAccess() async {
    if (_stopped) return 'You are signed out.';
    try {
      final session = await _cloud.openSession(
        ownerUid: ownerUid,
        requestPermission: true,
      );
      await _refreshQuota(session);
      session.close();
    } on BackupAccessException catch (e) {
      _setAccessIssue(e.issue);
      return _cloud.friendlyError(e, isBackup: true);
    } catch (e) {
      return _cloud.friendlyError(e, isBackup: true);
    }
    _authBlocked = false;
    _refreshIdleStatus();
    unawaited(syncNow());
    return null;
  }

  /// E-mail account without a linked Google Drive yet.
  bool get needsDriveLink {
    final user = FirebaseAuth.instance.currentUser;
    return user != null &&
        user.uid == ownerUid &&
        !AuthService.isGoogleUser(user);
  }

  static const _kDriveOffered = 'drive_connect_offered';

  /// The one-time "Connect Google Drive" question has not been shown yet.
  Future<bool> shouldOfferDriveConnect() async {
    if (!needsDriveLink || !enabled) return false;
    return !((await _ensurePrefs()).getBool(_key(_kDriveOffered)) ?? false);
  }

  Future<void> markDriveConnectOffered() => _persistBool(_kDriveOffered, true);

  Future<void> _refreshQuota(BackupSession session) async {
    final quota = await _cloud.getQuota(session);
    if (quota == null || _stopped) return;
    _driveQuota = quota;
    notifyListeners();
  }

  /// Explicit "restore from cloud": replaces local data with the signed-in
  /// user's cloud copy, even if there are unsent local changes (the UI asks
  /// for confirmation). Local data is replaced only after the complete
  /// backup has been downloaded and verified.
  Future<String?> forceRestore(void Function(String) onStatus) async {
    if (_stopped) return 'You are signed out.';
    if (_syncing) {
      return 'A backup is already running. Please try again in a moment.';
    }
    await _ensurePrefs();
    _beginSync();
    _setStatus(SyncStatus.syncing, 'Restoring…');

    BackupSession? session;
    try {
      onStatus('Connecting to Google Drive...');
      if (!await _isOnline()) {
        return 'No internet connection. Please connect and try restore again.';
      }
      session = await _cloud.openSession(ownerUid: ownerUid);

      onStatus('Searching for backup...');
      final remote = await _cloud.getRemoteInfo(session);
      if (remote == null) return 'No backup found for this account.';

      onStatus('Downloading backup...');
      await _pull(session, remote, force: true);
      onStatus('Restore completed successfully.');
      return null;
    } on BackupAccessException catch (e) {
      _setAccessIssue(e.issue);
      return _cloud.friendlyError(e, isBackup: false);
    } on BackupFileException catch (e) {
      // The downloaded backup was refused before the phone's data changed.
      return e.message;
    } catch (e) {
      debugPrint('Force restore error: $e');
      return _cloud.friendlyError(e, isBackup: false);
    } finally {
      session?.close();
      _endSync();
      if (_status == SyncStatus.syncing) _refreshIdleStatus();
    }
  }

  // ==========================================================
  // CORE SYNC
  // ==========================================================

  /// Runs one backup round.
  ///
  /// [scheduled] rounds are started by the chosen frequency; they do nothing
  /// when automatic backup is off. Manual rounds ("Back up now") always run.
  ///
  /// Order of work, cheapest first:
  ///  1. local fingerprint equals the last backed-up fingerprint -> nothing to
  ///     back up, no network is used at all;
  ///  2. otherwise compare with the cloud copy and upload only if the
  ///     content differs from what is already stored there.
  Future<void> syncNow({bool scheduled = false}) async {
    if (!_started || _stopped) return;
    if (scheduled && !enabled) return;
    if (FirebaseAuth.instance.currentUser?.uid != ownerUid) return;
    if (scheduled && _authBlocked) return;
    if (scheduled &&
        _driveFullUntil != null &&
        DateTime.now().isBefore(_driveFullUntil!)) {
      return;
    }

    if (_syncing) {
      if (!scheduled) _resync = true;
      return;
    }
    _beginSync();
    _retryTimer?.cancel();
    _retryAt = null;

    BackupSession? session;
    try {
      // Nothing new since the last backup: the backup is already current.
      if (scheduled && !_dirty && !await _localContentNeedsBackup()) {
        await _markScheduledRun();
        _refreshIdleStatus();
        return;
      }

      // A write that left the data identical to the last backup (for example
      // an edit that was undone) needs no backup and no network.
      if (_dirty && await _clearDirtyIfContentUnchanged()) {
        await _markScheduledRun();
        _refreshIdleStatus();
        return;
      }

      _setStatus(SyncStatus.syncing, 'Checking for changes…');

      if (!await _isOnline()) {
        _setOffline();
        _scheduleRetry();
        return;
      }

      session = await _cloud.openSession(ownerUid: ownerUid);
      await _refreshQuota(session);
      await _reconcile(session);
      _driveFullUntil = null;
      await _markScheduledRun();
    } catch (e) {
      _handleError(e, session);
    } finally {
      session?.close();
      _endSync();
      if (_resync && !_stopped) {
        _resync = false;
        unawaited(syncNow());
      }
    }
  }

  /// A completed round (scheduled or manual) restarts the schedule.
  Future<void> _markScheduledRun() async {
    _lastRunAt = DateTime.now();
    await _persistInt(_kLastRunAt, _lastRunAt!.millisecondsSinceEpoch);
  }

  Future<void> _reconcile(BackupSession session) async {
    final remote = await _cloud.getRemoteInfo(session);

    // Cloud copy untouched since our last sync, content already verified in
    // this run and nothing flagged since -> nothing to back up or download.
    // (Skips re-reading and hashing the whole database on every poll.)
    final remoteUntouched =
        remote != null &&
        _lastRemoteMs != null &&
        remote.modifiedMs == _lastRemoteMs;
    if (remoteUntouched && !_dirty && _localVerifiedThisRun) {
      _markSynced();
      return;
    }

    final versionAtStart = _dirtyVersion;
    final localSnapshot = await _localSnapshot();
    final snapshotIsCurrent = _dirtyVersion == versionAtStart;
    if (snapshotIsCurrent) _localVerifiedThisRun = true;
    final neverSynced = _lastRemoteMs == null;
    if (remote?.contentDigest == localSnapshot.digest && snapshotIsCurrent) {
      _lastRemoteMs = remote!.modifiedMs;
      await _persistInt(_kLastRemoteMs, remote.modifiedMs);
      await _persistBackupDigest(localSnapshot.digest);
      _dirty = false;
      await _persistBool(_kDirty, false);
      _markSynced();
      return;
    }
    final localDataAlreadyBackedUp =
        snapshotIsCurrent &&
        _lastBackupDigest != null &&
        localSnapshot.digest == _lastBackupDigest;

    // A fresh install has an empty DB -> nothing to protect -> may pull.
    // Existing data that was never synced counts as "local changes".
    var hasLocalChanges = hasUnbackedLocalChanges(
      dirtyFlag: _dirty,
      neverSynced: neverSynced,
      localDatabaseIsEmpty: localSnapshot.isEmpty,
      localDigest: localSnapshot.digest,
      lastSuccessfulBackupDigest: snapshotIsCurrent ? _lastBackupDigest : null,
      remoteBackupDigest: snapshotIsCurrent ? remote?.contentDigest : null,
    );

    // A previous version may leave a stale dirty flag behind after its
    // upload completed. The successful content fingerprint is authoritative.
    if (localDataAlreadyBackedUp && _dirty) {
      _dirty = false;
      await _persistBool(_kDirty, false);
    }

    // Data from an older app version has no verified baseline yet: back it up
    // once so every later check is a cheap local fingerprint comparison.
    if (!hasLocalChanges &&
        snapshotIsCurrent &&
        _lastBackupDigest == null &&
        !localSnapshot.isEmpty &&
        remote != null &&
        remote.modifiedMs == _lastRemoteMs &&
        remote.contentDigest != localSnapshot.digest) {
      hasLocalChanges = true;
    }

    // Content differs from the last backup but the flag was missing (e.g. the
    // app was killed right after a write): keep it flagged until uploaded so
    // routine checks can never skip it.
    if (hasLocalChanges && !_dirty) {
      _dirty = true;
      await _persistBool(_kDirty, true);
    }

    final remoteChanged =
        remote != null && (neverSynced || remote.modifiedMs != _lastRemoteMs);
    final action = decideSyncAction(
      remoteExists: remote != null,
      remoteChanged: remoteChanged,
      hasLocalChanges: hasLocalChanges,
    );

    switch (action) {
      case SyncAction.upload:
        _setStatus(SyncStatus.syncing, 'Backing up new data…');
        await _upload(session, remote?.id, versionAtStart);
      case SyncAction.markSynced:
        _markSynced();
      case SyncAction.pull:
        _setStatus(SyncStatus.syncing, 'Downloading changes…');
        await _pull(session, remote!);
      case SyncAction.preserveConflictAndUpload:
        _setStatus(SyncStatus.syncing, 'Backing up new data…');
        await _cloud.keepConflictCopy(session, remote!.id);
        await _upload(session, remote.id, versionAtStart);
    }
  }

  Future<void> _upload(
    BackupSession session,
    String? remoteId,
    int versionAtStart,
  ) async {
    final file = File(await _dbPath());
    if (!await file.exists()) {
      throw StateError('Local database not found');
    }

    final localSnapshot = await _localSnapshot();
    _ensureOwner();
    _setStatus(SyncStatus.syncing, 'Preparing backup…');
    final bytes = await _readCompleteDatabase(file);
    _setStatus(SyncStatus.syncing, 'Uploading backup…');
    final info = await _cloud.uploadBytes(
      session,
      bytes,
      remoteId,
      localSnapshot.digest,
      onProgress: (sent, total) => _setProgress('Uploaded', sent, total),
    );

    _lastRemoteMs = info.modifiedMs;
    await _persistInt(_kLastRemoteMs, info.modifiedMs);
    _lastBackupAt = DateTime.now();
    await _persistInt(_kLastBackupAt, _lastBackupAt!.millisecondsSinceEpoch);

    // Only clear the flag if nothing changed while we were uploading.
    if (_dirtyVersion == versionAtStart) {
      await _persistBackupDigest(localSnapshot.digest);
      _dirty = false;
      await _persistBool(_kDirty, false);
    }
    _markSynced();
  }

  Future<void> _pull(
    BackupSession session,
    RemoteBackupInfo remote, {
    bool force = false,
  }) async {
    final versionAtStart = _dirtyVersion;
    // Only a complete, checksum-verified download ever reaches this point.
    final bytes = await _cloud.downloadBytes(
      session,
      remote.id,
      onProgress: (got, total) => _setProgress('Downloaded', got, total),
    );

    // The user edited something while we were downloading -> don't clobber it.
    // The next sync round will treat it as a normal conflict.
    if (!force && (_dirty || _dirtyVersion != versionAtStart)) {
      _resync = true;
      return;
    }

    // A restore the user asked for may replace entries that were never
    // backed up, so what is on the phone is kept as a safety copy.
    await _installDatabase(bytes, keepSafetyCopy: force);

    _lastRemoteMs = remote.modifiedMs;
    final restoredDigest = (await _localSnapshot()).digest;
    _dirty = false;
    await _persistInt(_kLastRemoteMs, remote.modifiedMs);
    await _persistBackupDigest(restoredDigest);
    await _persistBool(_kDirty, false);

    _ensureOwner();
    await _reloadData();
    _markSynced();
  }

  // ==========================================================
  // BACKUP FILE  (export / import; needs no Google Drive)
  // ==========================================================

  /// What is on this phone right now.
  Future<KhataSummary> localSummary() async => summariseKhata(await _db());

  /// The signed-in user's customers and their history as one file. It can be
  /// saved or sent anywhere and imported into any Easy Khata account, e.g.
  /// after moving to a new Gmail. Throws [BackupFileException].
  Future<Uint8List> exportBackupBytes() async {
    try {
      final bytes = await _readCompleteDatabase(
        File(await _dbPath()),
        snapshotSuffix: '.export_snapshot',
      );
      return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    } catch (e) {
      debugPrint('Backup file export failed: $e');
      throw const BackupFileException(
        'The backup file could not be created. Please try again.',
      );
    }
  }

  /// Checks a picked file and reports what it holds; nothing on the phone
  /// changes. Throws [BackupFileException] for a file that cannot be used.
  Future<KhataSummary> inspectBackupBytes(Uint8List bytes) async {
    final probe = '${await _dbPath()}.inspect';
    try {
      await File(probe).writeAsBytes(bytes, flush: true);
      return await inspectBackupFile(probe);
    } finally {
      await _deleteDatabaseFiles(probe);
    }
  }

  /// Replaces this account's data with an exported backup file. The file is
  /// verified first and the data on the phone is kept as a safety copy
  /// ([undoLastReplace]). Returns an error message, or null on success.
  Future<String?> importBackupBytes(Uint8List bytes) => _replaceLocalData(
    () async => bytes,
    status: 'Importing backup file…',
    failure:
        'The backup file could not be imported. Your data was not changed.',
  );

  /// When the data on this phone was last replaced by a restore or an
  /// import and can still be brought back; null when there is nothing to undo.
  DateTime? get safetyCopyAt => _safetyCopyAt;

  /// Brings back the data that a restore / import replaced. The data it
  /// replaces becomes the new safety copy, so this can be undone as well.
  Future<String?> undoLastReplace() => _replaceLocalData(
    () async {
      final copy = File('${await _dbPath()}$_safetySuffix');
      if (!await copy.exists()) {
        throw const BackupFileException('There is nothing to undo.');
      }
      return copy.readAsBytes();
    },
    status: 'Bringing back previous data…',
    failure:
        'The previous data could not be brought back. Your data was not '
        'changed.',
  );

  Future<String?> _replaceLocalData(
    Future<Uint8List> Function() read, {
    required String status,
    required String failure,
  }) async {
    if (_stopped) return 'You are signed out.';
    if (_syncing) {
      return 'A backup is already running. Please try again in a moment.';
    }
    await _ensurePrefs();
    _beginSync();
    _setStatus(SyncStatus.syncing, status);

    try {
      final keptSafetyCopy = await _installDatabase(
        await read(),
        keepSafetyCopy: true,
      );
      try {
        _ensureOwner();
        await _reloadData();
      } catch (e) {
        if (e is _OwnerChanged || !keptSafetyCopy) rethrow;
        // The new data cannot be opened here: put the previous data back.
        debugPrint('Replaced data unusable, rolling back: $e');
        final copy = File('${await _dbPath()}$_safetySuffix');
        await _installDatabase(await copy.readAsBytes(), keepSafetyCopy: false);
        await _reloadData();
        return failure;
      }

      // This account now holds data its backup has never seen.
      _dirty = true;
      _dirtyVersion++;
      _localVerifiedThisRun = false;
      await _persistBool(_kDirty, true);
    } on BackupFileException catch (e) {
      return e.message;
    } on _OwnerChanged {
      return 'You are signed out.';
    } catch (e) {
      debugPrint('Replacing local data failed: $e');
      return failure;
    } finally {
      _endSync();
      if (_status == SyncStatus.syncing) _refreshIdleStatus();
    }

    if (_started && enabled) unawaited(syncNow());
    return null;
  }

  static const _safetySuffix = '.before_replace';
  DateTime? _safetyCopyAt;

  Future<void> _loadSafetyCopyTime() async {
    try {
      final copy = File('${await _dbPath()}$_safetySuffix');
      _safetyCopyAt = await copy.exists() ? await copy.lastModified() : null;
    } catch (_) {
      _safetyCopyAt = null;
    }
  }

  /// Verifies [bytes] as a complete khata database, then makes it the active
  /// local database. Throws (and leaves the phone's data untouched) when the
  /// file cannot be used. With [keepSafetyCopy] the data being replaced is
  /// saved first; returns whether such a copy was made.
  Future<bool> _installDatabase(
    List<int> bytes, {
    required bool keepSafetyCopy,
  }) async {
    // Never replace a database after its owner logged out.
    if (_stopped) throw const _OwnerChanged();
    final activePath = await _dbPath();
    final incoming = '$activePath.incoming';
    await _deleteDatabaseFiles(incoming);
    await File(incoming).writeAsBytes(bytes, flush: true);
    try {
      await inspectBackupFile(incoming);
    } catch (_) {
      await _deleteDatabaseFiles(incoming);
      rethrow;
    }
    await _deleteDatabaseFiles(incoming, keepMain: true);

    final kept = keepSafetyCopy && await _saveSafetyCopy(activePath);

    _ensureOwner();
    await _dbhelper.closeDB();
    await _deleteDatabaseFiles(activePath, keepMain: true);
    try {
      await File(incoming).rename(activePath);
    } catch (_) {
      await File(incoming).copy(activePath);
      await File(incoming).delete();
    }
    return kept;
  }

  /// Saves the data on this phone next to the database before it is
  /// replaced. Never blocks the replace: an unreadable database (the reason
  /// for many restores) simply has nothing worth keeping.
  Future<bool> _saveSafetyCopy(String activePath) async {
    final copy = File('$activePath$_safetySuffix');
    final tmp = File('${copy.path}.tmp');
    try {
      if (!await File(activePath).exists()) return false;
      final db = await _db();
      if ((await summariseKhata(db)).isEmpty) return false;
      if (await tmp.exists()) await tmp.delete();
      try {
        await db.execute('VACUUM INTO ?', [tmp.path]);
      } on _OwnerChanged {
        rethrow;
      } catch (_) {
        await _checkpoint();
        await File(activePath).copy(tmp.path);
      }
      if (await copy.exists()) await copy.delete();
      await tmp.rename(copy.path);
      _safetyCopyAt = DateTime.now();
      return true;
    } on _OwnerChanged {
      rethrow;
    } catch (e) {
      debugPrint('Safety copy skipped: $e');
      return false;
    }
  }

  /// Deletes a database file with its journal files ([keepMain]: only the
  /// journal files).
  Future<void> _deleteDatabaseFiles(String path, {bool keepMain = false}) async {
    for (final suffix in [if (!keepMain) '', '-wal', '-shm', '-journal']) {
      try {
        final f = File('$path$suffix');
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('Cleanup skipped: $e');
      }
    }
  }

  // ==========================================================
  // HELPERS
  // ==========================================================

  /// The active local database must still belong to [ownerUid].
  void _ensureOwner() {
    if (_stopped || _dbhelper.ownerUid != ownerUid) {
      throw const _OwnerChanged();
    }
  }

  Future<Database> _db() async {
    _ensureOwner();
    return _dbhelper.getDB();
  }

  Future<String> _dbPath() async {
    _ensureOwner();
    return _dbhelper.getDbPath();
  }

  void _beginSync() {
    _syncing = true;
    _syncDone = Completer<void>();
  }

  void _endSync() {
    _syncing = false;
    _progress = null;
    _progressLabel = null;
    final done = _syncDone;
    _syncDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<bool> _isOnline() async {
    final results = await Connectivity().checkConnectivity();
    if (!results.any((r) => r != ConnectivityResult.none)) return false;

    final client = HttpClient()..connectionTimeout = _connectivityProbeTimeout;
    try {
      return await hasStableInternetConnection(
        requiredSuccessfulProbes: _requiredSuccessfulProbes,
        probeTimeout: _connectivityProbeTimeout,
        interval: _probeInterval,
        probe: () async {
          final stopwatch = Stopwatch()..start();
          final request = await client.getUrl(
            Uri.https('www.google.com', '/generate_204'),
          );
          request.followRedirects = false;
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode == HttpStatus.noContent &&
              stopwatch.elapsed <= _maximumProbeLatency;
        },
      );
    } on IOException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    if (!enabled || _stopped) return;
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) {
      if (!_startupDelayElapsed) return;
      // Give the connection a moment to become usable, then sync
      // (uploads offline changes and pulls anything new).
      _connTimer?.cancel();
      _connTimer = Timer(
        const Duration(seconds: 2),
        _runIfDue,
      );
    } else if (!_syncing) {
      _setOffline();
    }
  }

  void _setOffline() {
    _setStatus(
      SyncStatus.offline,
      _dirty
          ? 'Internet unavailable or too slow — changes will sync when it improves'
          : 'Internet unavailable or too slow',
    );
  }

  void _setAccessIssue(BackupAccessIssue issue) {
    _authBlocked = true;
    switch (issue) {
      case BackupAccessIssue.connectDrive:
        _setStatus(
          SyncStatus.needsDriveConnection,
          'Connect Google Drive to back up your data',
        );
      case BackupAccessIssue.permission:
        _setStatus(
          SyncStatus.needsPermission,
          'Allow Google Drive access to back up your data',
        );
      case BackupAccessIssue.reLogin:
        _setStatus(
          SyncStatus.needsReLogin,
          'Log out and sign in again to resume backup',
        );
    }
  }

  void _setDriveFull() {
    // Do not hammer a full Drive; try again later or after "Back up now".
    _driveFullUntil = DateTime.now().add(const Duration(hours: 1));
    _setStatus(
      SyncStatus.driveFull,
      'Google Drive is full. Free up space to continue backups.',
    );
  }

  void _handleError(Object e, [BackupSession? session]) {
    if (e is _OwnerChanged || _stopped) return;
    debugPrint('AutoSync error: $e');

    if (e is BackupAccessException) {
      _setAccessIssue(e.issue);
      return;
    }

    if (e is DriveFullException || DriveBackupService.isQuotaError(e)) {
      if (e is DriveFullException && e.quota != null) _driveQuota = e.quota;
      _setDriveFull();
      return;
    }

    if (_cloud.isNetworkError(e)) {
      _setOffline();
      _scheduleRetry();
      return;
    }

    if (e is drive.DetailedApiRequestError && e.status == 401) {
      // Expired token: restore the linked account's session on the retry.
      unawaited(_cloud.invalidateSession(session));
      _setStatus(SyncStatus.error, 'Google Drive session expired. Retrying…');
      _scheduleRetry();
      return;
    }

    _setStatus(SyncStatus.error, 'Backup failed. Will retry automatically.');
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retryTimer?.cancel();
    final seconds = math.min(300, 15 * (1 << _retryAttempt));
    _retryAttempt = math.min(_retryAttempt + 1, 6);
    if (!enabled) return; // "Never": no automatic retries
    _retryAt = DateTime.now().add(Duration(seconds: seconds));
    _retryTimer = Timer(
      Duration(seconds: seconds),
      () => syncNow(scheduled: true),
    );
  }

  void _markSynced() {
    _retryAttempt = 0;
    _lastSyncedAt = DateTime.now();
    unawaited(
      _persistInt(_kLastSyncedAt, _lastSyncedAt!.millisecondsSinceEpoch),
    );
    _refreshIdleStatus();
  }

  void _refreshIdleStatus() {
    if (_frequency == null) {
      _setStatus(SyncStatus.disabled, 'Choose how often to back up');
    } else if (!enabled) {
      _setStatus(
        SyncStatus.disabled,
        _dirty
            ? 'Automatic backup is off. You have changes not backed up.'
            : 'Automatic backup is off',
      );
    } else if (_dirty) {
      _setStatus(
        SyncStatus.pending,
        'New changes will be backed up ${_frequency!.label.toLowerCase()}',
      );
    } else {
      _setStatus(SyncStatus.idle, 'All changes backed up');
    }
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  void _setProgress(String verb, int done, int total) {
    if (_stopped) return;
    _progress = total <= 0 ? null : (done / total).clamp(0.0, 1.0);
    _progressLabel = '$verb ${_size(done)} of ${_size(total)}';
    notifyListeners();
  }

  /// A complete, self-consistent copy of the local database.
  ///
  /// `VACUUM INTO` writes a transaction-consistent snapshot even while the
  /// app keeps writing; older SQLite versions fall back to the checkpointed
  /// file. Either way the bytes must look like a valid SQLite file.
  Future<List<int>> _readCompleteDatabase(
    File live, {
    String snapshotSuffix = '.backup_snapshot',
  }) async {
    final snapshot = File('${live.path}$snapshotSuffix');
    try {
      if (await snapshot.exists()) await snapshot.delete();
      final db = await _db();
      await db.execute('VACUUM INTO ?', [snapshot.path]);
      final bytes = await snapshot.readAsBytes();
      if (looksLikeSqlite(bytes)) return bytes;
    } on _OwnerChanged {
      rethrow;
    } catch (e) {
      debugPrint('VACUUM INTO unavailable, using checkpointed file: $e');
    } finally {
      try {
        if (await snapshot.exists()) await snapshot.delete();
      } catch (_) {}
    }

    await _checkpoint();
    _ensureOwner();
    final bytes = await live.readAsBytes();
    if (!looksLikeSqlite(bytes)) {
      throw StateError('Local database could not be read completely');
    }
    return bytes;
  }

  /// Flush the write-ahead log (if any) so the .db file is self-contained.
  Future<void> _checkpoint() async {
    try {
      final db = await _db();
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } on _OwnerChanged {
      rethrow;
    } catch (e) {
      debugPrint('Checkpoint skipped: $e');
    }
  }

  Future<({String digest, bool isEmpty})> _localSnapshot() async {
    final db = await _db();

    // Only the (fast) reads happen inside the transaction; the CPU-heavy
    // hashing runs on a background isolate so the UI never stutters.
    final data = await db.transaction((txn) async {
      final tables = <(String, String)>[
        (Dbhelper.tableCus, Dbhelper.colCustomerId),
        (Dbhelper.tableTrans, Dbhelper.colTransId),
        (Dbhelper.tableProducts, Dbhelper.colProductId),
        (Dbhelper.tableSales, Dbhelper.colSaleId),
        (Dbhelper.tableSaleItems, Dbhelper.colSaleItemId),
      ];
      final result = <String, List<Map<String, Object?>>>{};
      for (final (table, primaryKey) in tables) {
        final rows = await txn.query(table, orderBy: primaryKey);
        // Plain maps can be sent to another isolate.
        result[table] = [for (final row in rows) Map<String, Object?>.of(row)];
      }
      return result;
    });

    var rowCount = 0;
    for (final rows in data.values) {
      rowCount += rows.length;
    }
    final digest = await compute(_fingerprintInBackground, data);
    return (digest: digest, isEmpty: rowCount == 0);
  }

  /// Local-only check (no network): is there content that was never backed up?
  /// A device that never synced (e.g. fresh install) still needs a first
  /// sync so an existing cloud backup can be restored.
  Future<bool> _localContentNeedsBackup() async {
    if (_lastRemoteMs == null) return true;

    final versionAtStart = _dirtyVersion;
    final snapshot = await _localSnapshot();
    if (_dirtyVersion != versionAtStart) return true;

    final last = _lastBackupDigest;
    if (last == null) return !snapshot.isEmpty; // one-time baseline backup
    if (snapshot.isEmpty || snapshot.digest == last) return false;

    // New data that was never flagged (e.g. app killed right after a write).
    _dirty = true;
    await _persistBool(_kDirty, true);
    return true;
  }

  /// Local-only check (no network). When the current content fingerprint is
  /// identical to the last successfully backed-up one, the dirty flag is just
  /// noise: clear it and report `true` so no backup is attempted.
  Future<bool> _clearDirtyIfContentUnchanged() async {
    final last = _lastBackupDigest;
    if (last == null) return false;

    final versionAtStart = _dirtyVersion;
    final snapshot = await _localSnapshot();
    if (snapshot.digest != last || _dirtyVersion != versionAtStart) {
      return false;
    }

    _dirty = false;
    await _persistBool(_kDirty, false);
    return true;
  }

  Future<void> _persistBackupDigest(String digest) async {
    final saved = await (await _ensurePrefs()).setString(
      _key(_kLastBackupDigest),
      digest,
    );
    if (!saved) {
      throw StateError('Could not persist the successful backup fingerprint');
    }
    _lastBackupDigest = digest;
  }

  void _setStatus(SyncStatus status, String message) {
    if (_stopped) return;
    _status = status;
    _message = message;
    notifyListeners();
  }

  Future<SharedPreferences> _ensurePrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _persistBool(String key, bool value) async {
    try {
      await (await _ensurePrefs()).setBool(_key(key), value);
    } catch (e) {
      debugPrint('Pref write failed: $e');
    }
  }

  Future<void> _persistInt(String key, int value) async {
    try {
      await (await _ensurePrefs()).setInt(_key(key), value);
    } catch (e) {
      debugPrint('Pref write failed: $e');
    }
  }
}
