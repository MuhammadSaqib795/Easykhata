import 'dart:io';

import 'package:digitalkhata/db/dbhelper.dart';
import 'package:sqflite/sqflite.dart';

/// A backup file cannot be used. [message] is safe to show to the user.
class BackupFileException implements Exception {
  const BackupFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What one khata database holds (this phone, or a backup file).
class KhataSummary {
  const KhataSummary({
    required this.customers,
    required this.entries,
    required this.unsettled,
  });

  final int customers;

  /// Customer GAVE / GOT history entries.
  final int entries;

  /// Customers with an amount still to get or to pay.
  final int unsettled;

  bool get isEmpty => customers + entries == 0;

  /// "12 customers, 148 entries"
  String get description {
    String part(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    return '${part(customers, 'customer', 'customers')}, '
        '${part(entries, 'entry', 'entries')}';
  }
}

/// File extension of an exported backup ("Easy Khata backup").
const String backupFileExtension = 'ekb';

/// `EasyKhata_Backup_2026-10-12_1530.ekb`
String backupFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'EasyKhata_Backup_${now.year}-${two(now.month)}-${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}.$backupFileExtension';
}

bool looksLikeSqlite(List<int> bytes) {
  const header = 'SQLite format 3';
  if (bytes.length < header.length) return false;
  for (var i = 0; i < header.length; i++) {
    if (bytes[i] != header.codeUnitAt(i)) return false;
  }
  return true;
}

Future<int> _count(DatabaseExecutor db, String table, [String? where]) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM $table${where == null ? '' : ' WHERE $where'}',
  );
  return (rows.first['n'] as num?)?.toInt() ?? 0;
}

Future<KhataSummary> summariseKhata(DatabaseExecutor db) async {
  // Same limit as `isSettled`.
  String owing(String balance) => 'ABS($balance) >= 0.005';
  return KhataSummary(
    customers: await _count(db, Dbhelper.tableCus),
    entries: await _count(
      db,
      Dbhelper.tableTrans,
      '${Dbhelper.colTranCusId} IS NOT NULL',
    ),
    unsettled: await _count(
      db,
      Dbhelper.tableCus,
      owing(Dbhelper.colCustomerCurrentBalance),
    ),
  );
}

/// Columns a file must have to be opened as a khata by this app.
const _requiredColumns = <String, List<String>>{
  Dbhelper.tableCus: [
    Dbhelper.colCustomerId,
    Dbhelper.colCustomerName,
    Dbhelper.colCustomerphoneNo,
    Dbhelper.colCustomerCurrentBalance,
  ],
  Dbhelper.tableTrans: [
    Dbhelper.colTransId,
    Dbhelper.colTranCusId,
    Dbhelper.colAmount,
    Dbhelper.colTrantype,
    Dbhelper.colTranTime,
  ],
};

/// Checks that the file at [path] is a complete, undamaged Easy Khata backup
/// this app version can open, and reports what it holds. The file itself is
/// never changed. Throws [BackupFileException] otherwise.
///
/// [path] must be a private working copy: the check may leave journal files
/// next to it.
Future<KhataSummary> inspectBackupFile(
  String path, {
  DatabaseFactory? factory,
}) async {
  const notABackup = BackupFileException(
    'This file is not an Easy Khata backup. Choose a file that was exported '
    'from Easy Khata.',
  );
  const damaged = BackupFileException(
    'This backup file is damaged or incomplete. Export it again and retry.',
  );

  final file = File(path);
  if (!await file.exists()) throw notABackup;
  final head = await file.openRead(0, 16).fold<List<int>>(
    <int>[],
    (all, chunk) => all..addAll(chunk),
  );
  if (!looksLikeSqlite(head)) throw notABackup;

  final Database db;
  try {
    db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  } catch (_) {
    throw damaged;
  }

  try {
    final check = await db.rawQuery('PRAGMA integrity_check');
    if (check.length != 1 || check.first.values.first != 'ok') throw damaged;

    final tables = {
      for (final row in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'],
    };
    final version = await db.getVersion();
    if (version > Dbhelper.databaseVersion) {
      throw const BackupFileException(
        'This backup was made with a newer version of Easy Khata. Update the '
        'app, then import the file again.',
      );
    }
    if (version < 1) throw notABackup;

    if (version == Dbhelper.databaseVersion) {
      if (tables.contains('suppliers') || tables.contains('communities')) {
        throw notABackup;
      }
      final transactionColumns = await db.rawQuery(
        'PRAGMA table_info(${Dbhelper.tableTrans})',
      );
      if (transactionColumns.any((row) => row['name'] == 'suppid')) {
        throw notABackup;
      }
    }

    for (final MapEntry(key: table, value: columns)
        in _requiredColumns.entries) {
      if (!tables.contains(table)) throw notABackup;
      try {
        await db.query(table, columns: columns, limit: 1);
      } on DatabaseException {
        throw notABackup;
      }
    }

    return await summariseKhata(db);
  } on BackupFileException {
    rethrow;
  } catch (_) {
    throw damaged;
  } finally {
    await db.close();
  }
}
