# Easy Khata

Easy Khata is an offline-first ledger app for managing customer ledgers,
balances, and transactions. The local SQLite database is the
working copy; a private Google Drive app-folder backup of the signed-in user is the backup and
cross-device sync target.

## Requirements

- Flutter SDK compatible with the constraint in `pubspec.yaml`
- Android Studio / Android SDK for Android builds
- Firebase project configuration for the platforms you build

## Local setup

1. Clone the repository and install the Flutter SDK.
2. Configure Firebase for the target platforms. Keep platform configuration
   files and credentials in line with your organization's secret-management
   policy.
3. Run `flutter pub get`.
4. Run `flutter analyze` and `flutter test`.
5. Run the app with `flutter run`.

## Data, backup, and recovery

- Ledger changes are saved locally first, so normal data entry works offline.
- Automatic Google Drive backup starts after local data loads and the main screen has
  rendered. It requires a usable internet connection and a signed-in account.
- Sync uploads the initial local database and subsequent local modifications;
  it stores a fingerprint of the successfully synced local table contents
  locally and in the backup metadata, and does not repeatedly upload
  unchanged data after app restarts or local app-state loss.
- Backup is content-based: a backup happens only when the data differs from the last
  backed-up (or cloud) copy. Opening the app, resuming it, or saving unchanged values
  does not upload anything. Routine checks run silently, are rate limited, and show a
  spinner only during a real upload or download.
- Sign-in is Firebase email/password (with password reset) or Google. The signed-in
  user is always the backup and restore owner; there is no separate backup account. Each user (Firebase UID) has
  their own local database and backup state. Fingerprinting and upload run off the UI thread.
- Tap a history entry to modify its amount or description; the balance is corrected
  atomically. The description is free text written by the user.
- Pending changes remain local while offline or while the connection is too
  slow. Sync retries when connectivity improves.
- If both devices changed since the last sync, the service preserves a cloud
  conflict copy before applying the local database.
- Restore replaces local data with the signed-in account's Google Drive backup. Confirm the
  overwrite prompt only after reviewing what will be replaced.
- To use another account, log out and sign in with it; backup follows automatically.
- **Backup file (no Easy Khata Google Drive connection needed):** In Backup &
  restore, choose *Export backup file* and save or share customer ledgers and
  their entries as one `.ekb` file. You can put it in a different Google Drive
  or another location accessible to the new phone. On that phone, sign in to
  the intended Easy Khata account, choose *Import backup file*, and select the
  `.ekb` (for example, from Google Drive). This replaces that account's local
  khata. The file is verified (complete, undamaged, a real Easy Khata backup,
  not from a newer app version) before anything on the phone changes.
- After importing, tap *Back up now* to upload the imported data to Easy
  Khata's private Google Drive backup for that signed-in account. Before a
  restore or import replaces local data, that data is saved as a safety copy;
  *Undo last restore / import* brings it back.
- A customer can be deleted only when their balance is zero. The app checks
  this, and the database enforces it again with a trigger (schema version 4),
  so no code path can remove a khata that still has an amount to get or to pay.
- The schema version 4 upgrade permanently removes supplier/community records
  and supplier-only transaction history from local databases and imported
  older backups. Customer data and customer-linked history are retained.
- An older Google Drive backup is replaced with the customer-only database
  when the next successful backup runs. If automatic backup is disabled, tap
  *Back up now* after upgrading to update the Drive copy.
- Customer Khata statements can be saved, printed or shared as PDF from the
  customer screen.

Cloud backup is not a substitute for a tested export and recovery
policy. Before a production rollout, exercise restore and conflict handling
with test accounts and non-production data.

## Database changes

The SQLite schema version is declared in `lib/db/dbhelper.dart`. For every
schema version increase:

1. Add a migration step for each prior supported version.
2. Keep each migration transactional and safe to retry.
3. Add an upgrade test that starts from the old schema and verifies intended
   rows and relationships are preserved (and intentional deletions are checked).
4. Never use a destructive downgrade in a production app. Downgrades currently
   fail explicitly rather than deleting user data; distribute a forward
   migration or a tested recovery plan instead.

## Android release signing

Release builds must be signed with a private upload/release key. Do not use the
debug key and never commit the keystore, passwords, or `android/key.properties`.

Create `android/key.properties` locally (or provide it from your CI secret
store) with:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=your-store-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

The release Gradle configuration fails when a release task is requested and
these properties are missing or incomplete. Keep a secure backup of the
keystore and signing credentials: losing them can prevent future app updates.
Build with `flutter build appbundle --release` after setting up signing.

## Quality checks

Run these before merging:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

GitHub Actions runs formatting, analysis, and tests on pushes and pull requests.

## Google Drive backup setup

1. Firebase Console → Authentication → Sign-in method → enable **Email/Password**
   and **Google**.
2. Google Cloud Console (same project) → APIs & Services → enable **Google Drive API**.
3. Google Auth Platform → **Data access**: add the scope `.../auth/drive.appdata`.
4. Google Auth Platform → **Audience** → **Publish app** (In production).
   While the app is in *Testing*, only listed test users can grant Drive access;
   everyone else sees "Access blocked: 403 access_denied".
5. Branding: set the app name to **Easy Khata**.

Backup account rules: Google users back up to their own Drive. E-mail/password
users connect a Google account once; it is linked to their Easy Khata account
(Firebase account linking) and cannot be swapped. A full Google Drive pauses
backups with a warning; the previous backup is kept.

## iOS setup (one time)

1. Firebase Console → Project settings → **Add app → iOS**, bundle id
   `com.devcastle.digitalkhata`. Download **GoogleService-Info.plist** and add it
   to `ios/Runner` in Xcode (target *Runner*, "Copy items if needed").
2. Open `ios/Flutter/GoogleSignIn.xcconfig` and paste `CLIENT_ID` and
   `REVERSED_CLIENT_ID` from that plist.
3. In Google Cloud Console make sure the iOS OAuth client exists (Firebase
   creates it) and the Google Drive API is enabled.
4. `cd ios && pod install`, then `flutter run` on an iPhone (iOS 15+).

The Drive backup account is remembered: Android asks the system for access to
the linked account by e-mail (no account picker after the first grant), and iOS
silently restores the previous Google session.
