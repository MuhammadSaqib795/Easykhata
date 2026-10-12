import 'dart:io';

import 'package:digitalkhata/db/dbhelper.dart';
import 'package:digitalkhata/services/backup_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;

  setUpAll(sqfliteFfiInit);
  setUp(() async => dir = await Directory.systemTemp.createTemp('khata_test'));
  tearDown(() => dir.delete(recursive: true));

  Future<Database> open(String name, {int? version}) =>
      databaseFactoryFfi.openDatabase(
        p.join(dir.path, name),
        options: OpenDatabaseOptions(
          version: version ?? Dbhelper.databaseVersion,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, _) => Dbhelper.createSchema(db),
          onUpgrade: Dbhelper.migrate,
        ),
      );

  /// A khata with one owing customer and one entry.
  Future<Database> khata(String name) async {
    final db = await open(name);
    final customer = await db.insert(Dbhelper.tableCus, {
      Dbhelper.colCustomerName: 'Khawar',
      Dbhelper.colCustomerphoneNo: '03001234567',
      Dbhelper.colCustomerCreatedAt: DateTime(2026).toIso8601String(),
      Dbhelper.colCustomerCurrentBalance: 50.0,
    });
    await db.insert(Dbhelper.tableTrans, {
      Dbhelper.colTranCusId: customer,
      Dbhelper.colTranInfo: 'Rice',
      Dbhelper.colTranTime: DateTime(2026).toIso8601String(),
      Dbhelper.colTrantype: 'Gave',
      Dbhelper.colAmount: 50.0,
    });
    return db;
  }

  Future<KhataSummary> inspect(String name) =>
      inspectBackupFile(p.join(dir.path, name), factory: databaseFactoryFfi);

  Matcher refusedWith(String text) => throwsA(
    isA<BackupFileException>().having((e) => e.message, 'message', contains(text)),
  );

  test('an exported file is accepted and reports customer data', () async {
    final db = await khata('live.db');
    // Exactly how the app exports: a complete snapshot of the open database.
    await db.execute('VACUUM INTO ?', [p.join(dir.path, 'export.ekb')]);
    await db.close();

    final summary = await inspect('export.ekb');
    expect(summary.customers, 1);
    expect(summary.entries, 1);
    expect(summary.unsettled, 1);
    expect(summary.isEmpty, isFalse);
    expect(summary.description, '1 customer, 1 entry');
  });

  test('an exported file opens as a working khata (export -> import)', () async {
    final db = await khata('live.db');
    await db.execute('VACUUM INTO ?', [p.join(dir.path, 'imported.db')]);
    await db.close();
    await inspect('imported.db');

    final imported = await open('imported.db');
    final customers = await imported.query(Dbhelper.tableCus);
    expect(customers.single[Dbhelper.colCustomerName], 'Khawar');
    expect(customers.single[Dbhelper.colCustomerCurrentBalance], 50.0);
    expect(await imported.query(Dbhelper.tableTrans), hasLength(1));
    final tables = await imported.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(tables.map((row) => row['name']), isNot(contains('suppliers')));
    expect(tables.map((row) => row['name']), isNot(contains('communities')));
    final columns = await imported.rawQuery(
      'PRAGMA table_info(${Dbhelper.tableTrans})',
    );
    expect(columns.map((row) => row['name']), isNot(contains('suppid')));
    // The delete lock travels with the file.
    await expectLater(imported.delete(Dbhelper.tableCus), throwsA(anything));
    await imported.close();
  });

  test('a file that is not a database is refused', () async {
    await File(p.join(dir.path, 'photo.jpg')).writeAsString('not a khata' * 50);
    await expectLater(inspect('photo.jpg'), refusedWith('not an Easy Khata'));
    await expectLater(inspect('missing.ekb'), refusedWith('not an Easy Khata'));
  });

  test('another app\'s database is refused', () async {
    final other = await databaseFactoryFfi.openDatabase(
      p.join(dir.path, 'other.db'),
    );
    await other.execute('CREATE TABLE notes(id INTEGER PRIMARY KEY)');
    await other.close();
    await expectLater(inspect('other.db'), refusedWith('not an Easy Khata'));
  });

  test('a cut-off (incomplete) file is refused', () async {
    final db = await khata('live.db');
    final customer = (await db.query(Dbhelper.tableCus)).single;
    for (var i = 0; i < 400; i++) {
      await db.insert(Dbhelper.tableTrans, {
        Dbhelper.colTranCusId: customer[Dbhelper.colCustomerId],
        Dbhelper.colTranInfo: 'Transaction $i with a long enough description',
        Dbhelper.colTranTime: DateTime(2026, 1, 1, 0, i % 60)
            .toIso8601String(),
        Dbhelper.colTrantype: 'Gave',
        Dbhelper.colAmount: 1.0,
      });
    }
    await db.execute('VACUUM INTO ?', [p.join(dir.path, 'full.ekb')]);
    await db.close();

    final bytes = await File(p.join(dir.path, 'full.ekb')).readAsBytes();
    await File(
      p.join(dir.path, 'cut.ekb'),
    ).writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    await expectLater(inspect('cut.ekb'), throwsA(isA<BackupFileException>()));
  });

  test('a file from a newer app version is refused', () async {
    final db = await khata('newer.db');
    await db.setVersion(Dbhelper.databaseVersion + 1);
    await db.close();
    await expectLater(inspect('newer.db'), refusedWith('newer version'));
  });

  test('inspecting never changes the file', () async {
    final db = await khata('live.db');
    await db.execute('VACUUM INTO ?', [p.join(dir.path, 'export.ekb')]);
    await db.close();
    final file = File(p.join(dir.path, 'export.ekb'));
    final before = await file.readAsBytes();
    await inspect('export.ekb');
    expect(await file.readAsBytes(), before);
  });

  test('file name', () {
    expect(
      backupFileName(DateTime(2026, 10, 2, 9, 5)),
      'EasyKhata_Backup_2026-10-02_0905.ekb',
    );
  });
}
