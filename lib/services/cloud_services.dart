import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:digitalkhata/authentication/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;

/// Metadata of the user's current backup file in Google Drive.
class RemoteBackupInfo {
  const RemoteBackupInfo({
    required this.id,
    required this.modifiedMs,
    this.contentDigest,
  });

  /// Drive file id.
  final String id;
  final String? contentDigest;

  /// Drive's `modifiedTime` (epoch ms). Used to detect whether another
  /// device changed the backup since we last synced.
  final int modifiedMs;
}

/// Why the backup of the current user cannot reach Google Drive.
enum BackupAccessIssue {
  /// Signed out, or the session no longer belongs to the backup owner.
  reLogin,

  /// No Google account linked yet (e-mail account), or the linked Google
  /// account's session must be restored with one tap.
  connectDrive,

  /// The linked Google account has not granted Drive backup permission.
  permission,
}

class BackupAccessException implements Exception {
  const BackupAccessException(this.issue);
  final BackupAccessIssue issue;

  @override
  String toString() => 'BackupAccessException($issue)';
}

/// Google Drive storage of the signed-in user.
class DriveQuota {
  const DriveQuota({required this.usedBytes, this.limitBytes});

  final int usedBytes;

  /// Null for unlimited (e.g. some Workspace accounts).
  final int? limitBytes;

  int? get freeBytes =>
      limitBytes == null ? null : (limitBytes! - usedBytes).clamp(0, limitBytes!);

  /// True when less than 5% or less than 50 MB is left.
  bool get isAlmostFull {
    final free = freeBytes;
    if (free == null || limitBytes == null) return false;
    return free < 50 * 1024 * 1024 || free < limitBytes! * 0.05;
  }

  bool hasRoomFor(int bytes) => freeBytes == null || freeBytes! >= bytes;
}

/// Google Drive has no room for the backup. The previous backup is kept.
class DriveFullException implements Exception {
  const DriveFullException(this.quota);
  final DriveQuota? quota;

  @override
  String toString() => 'DriveFullException';
}

/// A short-lived authorised Drive connection for exactly one app user
/// ([ownerUid]). Always call [close].
class BackupSession {
  BackupSession(this.api, this._client, this.ownerUid, this.accessToken);

  final drive.DriveApi api;
  final gauth.AuthClient _client;
  final String ownerUid;
  final String accessToken;

  void close() => _client.close();
}

/// Backup in the app-private folder of the user's own Google Drive.
///
/// The Drive account is always the Google account of the signed-in user
/// (their Google login, or the Google account linked once to an e-mail
/// account), see [AuthService.driveAccountForCurrentUser].
///
/// Uploads are all-or-nothing: the new file is uploaded under a temporary
/// name, its checksum is verified, and only then does it become the backup
/// and the old one is removed. An interrupted upload never replaces a good
/// backup.
class DriveBackupService {
  static const String _backupName = 'DigitalKhata_Backup.db';
  static const String _tempName = 'DigitalKhata_Backup.uploading';
  static const String _conflictName = 'DigitalKhata_Conflict_Backup.db';
  static const String _digestProperty = 'digitalKhataContentSha256';
  static const String _shaProperty = 'digitalKhataFileSha256';
  static const String _ownerProperty = 'digitalKhataOwnerUid';
  static const int _progressChunk = 128 * 1024;
  static const _timeout = Duration(minutes: 5);

  // ==========================================================
  // ERRORS
  // ==========================================================

  bool isNetworkError(Object error) {
    if (error is TimeoutException ||
        error is io.SocketException ||
        error is io.HandshakeException) {
      return true;
    }
    if (error is PlatformException) {
      final m = '${error.code} ${error.message ?? ''}'.toLowerCase();
      return m.contains('network') || m.contains('unreachable');
    }
    final m = error.toString().toLowerCase();
    return m.contains('socketexception') ||
        m.contains('failed host lookup') ||
        m.contains('connection closed') ||
        m.contains('connection reset');
  }

  /// Google reported that the user's storage is full.
  static bool isQuotaError(Object error) {
    if (error is! drive.DetailedApiRequestError) return false;
    final reasons = [
      for (final e in error.errors) e.reason ?? '',
      error.message ?? '',
    ].join(' ').toLowerCase();
    return reasons.contains('storagequotaexceeded');
  }

  String friendlyError(Object error, {required bool isBackup}) {
    final action = isBackup ? 'backup' : 'restore';
    if (error is DriveFullException || isQuotaError(error)) {
      return 'Your Google Drive is full. Free up space, then back up again. '
          'Your previous backup is safe.';
    }
    if (error is BackupAccessException) {
      switch (error.issue) {
        case BackupAccessIssue.connectDrive:
          return 'Connect Google Drive to $action your data.';
        case BackupAccessIssue.permission:
          return 'Allow Google Drive access to $action your data.';
        case BackupAccessIssue.reLogin:
          return 'Please sign in again to $action your data.';
      }
    }
    if (isNetworkError(error)) {
      return 'No internet connection. Please connect and try $action again.';
    }
    return isBackup
        ? 'Backup could not be completed right now. Please try again.'
        : 'Restore could not be completed right now. Please try again.';
  }

  // ==========================================================
  // SESSION
  // ==========================================================

  /// Opens a Drive session for [ownerUid], who must be the signed-in user.
  /// Never shows an account chooser. With [requestPermission] the Drive
  /// permission prompt may be shown for the linked account.
  Future<BackupSession> openSession({
    required String ownerUid,
    bool requestPermission = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != ownerUid) {
      throw const BackupAccessException(BackupAccessIssue.reLogin);
    }
    if (!AuthService.isGoogleUser(user)) {
      throw const BackupAccessException(BackupAccessIssue.connectDrive);
    }

    final access = await AuthService.instance.driveAccessToken(
      prompt: requestPermission,
    );
    if (FirebaseAuth.instance.currentUser?.uid != ownerUid) {
      throw const BackupAccessException(BackupAccessIssue.reLogin);
    }
    final token = access.token;
    if (token == null) {
      throw BackupAccessException(
        access.needsConnect
            ? BackupAccessIssue.connectDrive
            : BackupAccessIssue.permission,
      );
    }

    final client = gauth.authenticatedClient(
      http.Client(),
      gauth.AccessCredentials(
        gauth.AccessToken(
          'Bearer',
          token,
          DateTime.now().toUtc().add(const Duration(minutes: 50)),
        ),
        null,
        AuthService.driveScopes,
      ),
    );
    return BackupSession(drive.DriveApi(client), client, ownerUid, token);
  }

  /// After a 401: forget this token so the next session gets a fresh one.
  Future<void> invalidateSession(BackupSession? session) =>
      AuthService.instance.invalidateDriveSession(session?.accessToken);

  // ==========================================================
  // STORAGE
  // ==========================================================

  Future<DriveQuota?> getQuota(BackupSession session) async {
    try {
      final about = await session.api.about
          .get($fields: 'storageQuota')
          .timeout(const Duration(seconds: 20));
      final q = about.storageQuota;
      if (q == null) return null;
      return DriveQuota(
        usedBytes: int.tryParse(q.usage ?? '') ?? 0,
        limitBytes: int.tryParse(q.limit ?? ''),
      );
    } catch (e) {
      if (isNetworkError(e)) rethrow;
      debugPrint('Drive quota unavailable: $e');
      return null;
    }
  }

  // ==========================================================
  // FILES
  // ==========================================================

  bool _belongsTo(drive.File f, String ownerUid) {
    final owner = f.appProperties?[_ownerProperty];
    return owner == null || owner == ownerUid;
  }

  Future<List<drive.File>> _find(BackupSession s, String name) async {
    final list = await s.api.files
        .list(
          q: "name = '$name' and trashed = false",
          spaces: 'appDataFolder',
          orderBy: 'modifiedTime desc',
          pageSize: 20,
          $fields: 'files(id,modifiedTime,size,md5Checksum,appProperties)',
        )
        .timeout(const Duration(seconds: 20));
    return [
      for (final f in list.files ?? const <drive.File>[])
        if (f.id != null && _belongsTo(f, s.ownerUid)) f,
    ];
  }

  Future<RemoteBackupInfo?> getRemoteInfo(BackupSession session) async {
    final files = await _find(session, _backupName);
    if (files.isEmpty) return null;
    final f = files.first;
    return RemoteBackupInfo(
      id: f.id!,
      modifiedMs: f.modifiedTime?.millisecondsSinceEpoch ?? 0,
      contentDigest: f.appProperties?[_digestProperty],
    );
  }

  /// Uploads [bytes] and makes them the backup only once the complete file
  /// is verified in Drive. Throws [DriveFullException] when Drive has no
  /// room; the previous backup is never touched in that case.
  Future<RemoteBackupInfo> uploadBytes(
    BackupSession session,
    List<int> bytes,
    String? existingId,
    String contentDigest, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final data = Uint8List.fromList(bytes);
    final md5Hex = md5.convert(data).toString();
    final shaHex = sha256.convert(data).toString();

    // Remove leftovers of an earlier interrupted upload.
    for (final f in await _find(session, _tempName)) {
      await _safeDelete(session, f.id!);
    }

    final quota = await getQuota(session);
    if (quota != null && !quota.hasRoomFor(data.length)) {
      throw DriveFullException(quota);
    }

    final meta = drive.File()
      ..name = _tempName
      ..parents = ['appDataFolder']
      ..mimeType = 'application/x-sqlite3'
      ..appProperties = {
        _digestProperty: contentDigest,
        _shaProperty: shaHex,
        _ownerProperty: session.ownerUid,
      };

    final drive.File uploaded;
    try {
      uploaded = await session.api.files
          .create(
            meta,
            uploadMedia: drive.Media(
              _progressStream(data, onProgress),
              data.length,
            ),
            uploadOptions: drive.UploadOptions.resumable,
            $fields: 'id,size,md5Checksum',
          )
          .timeout(_timeout);
    } catch (e) {
      if (isQuotaError(e)) throw DriveFullException(quota);
      rethrow;
    }

    // Verify the complete file arrived before it becomes the backup.
    final ok =
        uploaded.id != null &&
        uploaded.md5Checksum == md5Hex &&
        int.tryParse(uploaded.size ?? '') == data.length;
    if (!ok) {
      if (uploaded.id != null) await _safeDelete(session, uploaded.id!);
      throw StateError('Uploaded backup failed verification');
    }

    final finalized = await session.api.files
        .update(
          drive.File()..name = _backupName,
          uploaded.id!,
          $fields: 'id,modifiedTime',
        )
        .timeout(const Duration(minutes: 1));

    // The new backup is in place; older copies are no longer needed.
    for (final f in await _find(session, _backupName)) {
      if (f.id != uploaded.id) await _safeDelete(session, f.id!);
    }

    return RemoteBackupInfo(
      id: uploaded.id!,
      modifiedMs:
          finalized.modifiedTime?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      contentDigest: contentDigest,
    );
  }

  Stream<List<int>> _progressStream(
    Uint8List data,
    void Function(int sent, int total)? onProgress,
  ) async* {
    onProgress?.call(0, data.length);
    for (var from = 0; from < data.length; from += _progressChunk) {
      final to = from + _progressChunk > data.length
          ? data.length
          : from + _progressChunk;
      yield Uint8List.sublistView(data, from, to);
      onProgress?.call(to, data.length);
    }
  }

  /// Downloads a complete backup and verifies its checksum. Throws (and
  /// returns nothing) for an incomplete or corrupted file.
  Future<List<int>> downloadBytes(
    BackupSession session,
    String fileId, {
    void Function(int received, int total)? onProgress,
  }) async {
    final info =
        await session.api.files
                .get(fileId, $fields: 'size,md5Checksum,appProperties')
                .timeout(const Duration(seconds: 20))
            as drive.File;
    final size = int.tryParse(info.size ?? '') ?? 0;

    final media =
        await session.api.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final builder = BytesBuilder(copy: false);
    onProgress?.call(0, size);
    await for (final chunk in media.stream.timeout(_timeout)) {
      builder.add(chunk);
      onProgress?.call(builder.length, size);
    }
    final bytes = builder.takeBytes();

    final sha = info.appProperties?[_shaProperty];
    final valid =
        (size == 0 || bytes.length == size) &&
        (info.md5Checksum == null ||
            md5.convert(bytes).toString() == info.md5Checksum) &&
        (sha == null || sha256.convert(bytes).toString() == sha);
    if (!valid) throw StateError('Backup file is incomplete or damaged');
    return bytes;
  }

  /// Before the local copy overwrites a backup that another device changed,
  /// keep that copy as `DigitalKhata_Conflict_Backup.db` (latest only).
  Future<void> keepConflictCopy(BackupSession session, String fileId) async {
    final old = await _find(session, _conflictName);
    await session.api.files
        .copy(
          drive.File()
            ..name = _conflictName
            ..parents = ['appDataFolder'],
          fileId,
        )
        .timeout(const Duration(minutes: 1));
    for (final f in old) {
      await _safeDelete(session, f.id!);
    }
  }

  Future<void> _safeDelete(BackupSession session, String id) async {
    try {
      await session.api.files.delete(id).timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('Drive cleanup skipped: $e');
    }
  }
}
