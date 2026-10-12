enum SyncAction { upload, markSynced, pull, preserveConflictAndUpload }

bool hasUnbackedLocalChanges({
  required bool dirtyFlag,
  required bool neverSynced,
  required bool localDatabaseIsEmpty,
  required String localDigest,
  required String? lastSuccessfulBackupDigest,
  String? remoteBackupDigest,
}) {
  if (localDigest == lastSuccessfulBackupDigest ||
      localDigest == remoteBackupDigest) {
    return false;
  }
  // A previous successful backup is known and the content differs from it:
  // that is genuinely new data, whether or not a change flag survived.
  // An empty database with no flagged change is NOT treated as new data, so
  // a lost/unreadable local file can never overwrite a good cloud backup.
  if (lastSuccessfulBackupDigest != null) {
    return dirtyFlag || !localDatabaseIsEmpty;
  }
  return dirtyFlag || (neverSynced && !localDatabaseIsEmpty);
}

SyncAction decideSyncAction({
  required bool remoteExists,
  required bool remoteChanged,
  required bool hasLocalChanges,
}) {
  if (!remoteExists || !remoteChanged) {
    return hasLocalChanges ? SyncAction.upload : SyncAction.markSynced;
  }
  if (!hasLocalChanges) return SyncAction.pull;
  return SyncAction.preserveConflictAndUpload;
}
