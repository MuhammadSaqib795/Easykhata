import 'package:digitalkhata/db/dbhelper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() {
  late Directory dir;

  setUpAll(sqfliteFfiInit);
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('khata_migrate'),
  );
  tearDown(() => dir.delete(recursive: true));

  test('version 3 migration removes supplier/community data only', () async {
    final path = p.join(dir.path, 'legacy.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE customer(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              img TEXT,
              desp TEXT,
              amount REAL NOT NULL DEFAULT 0,
              time TEXT NOT NULL,
              num TEXT NOT NULL,
              current REAL NOT NULL DEFAULT 0,
              address TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE suppliers(
              supplierId INTEGER PRIMARY KEY AUTOINCREMENT,
              supplierName TEXT NOT NULL,
              supplierPhone TEXT NOT NULL,
              supplierNote TEXT,
              supplierBalance REAL NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE communities(
              communityId INTEGER PRIMARY KEY AUTOINCREMENT,
              communityName TEXT NOT NULL,
              communityNote TEXT,
              communityMembers INTEGER NOT NULL DEFAULT 0,
              communityTarget REAL NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE transactions(
              transid INTEGER PRIMARY KEY AUTOINCREMENT,
              cusid INTEGER,
              suppid INTEGER,
              info TEXT,
              tranTime TEXT NOT NULL,
              type TEXT NOT NULL,
              amount REAL NOT NULL,
              FOREIGN KEY(cusid) REFERENCES customer(id) ON DELETE CASCADE,
              FOREIGN KEY(suppid) REFERENCES suppliers(supplierId)
                ON DELETE CASCADE
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_transactions_customer_time '
            'ON transactions (cusid, tranTime)',
          );
          await db.execute(
            'CREATE INDEX idx_transactions_supplier_time '
            'ON transactions (suppid, tranTime)',
          );
          await db.execute('''
            CREATE TRIGGER trg_supplier_keep_unsettled
            BEFORE DELETE ON suppliers WHEN ABS(OLD.supplierBalance) >= 0.005
            BEGIN SELECT RAISE(ABORT, 'khata_not_settled'); END
          ''');
          final customerId = await db.insert('customer', {
            'name': 'Customer stays',
            'num': '03001234567',
            'time': DateTime(2026).toIso8601String(),
            'current': 45.0,
          });
          final supplierId = await db.insert('suppliers', {
            'supplierName': 'Supplier removed',
            'supplierPhone': '03007654321',
            'supplierBalance': 30.0,
          });
          await db.insert('communities', {
            'communityName': 'Community removed',
          });
          await db.insert('transactions', {
            'cusid': customerId,
            'info': 'Customer history stays',
            'tranTime': DateTime(2026).toIso8601String(),
            'type': 'Gave',
            'amount': 45.0,
          });
          await db.insert('transactions', {
            'suppid': supplierId,
            'info': 'Supplier history removed',
            'tranTime': DateTime(2026).toIso8601String(),
            'type': 'Got',
            'amount': 30.0,
          });
        },
      ),
    );
    await legacy.close();

    final upgraded = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: Dbhelper.databaseVersion,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onUpgrade: Dbhelper.migrate,
      ),
    );
    addTearDown(upgraded.close);

    expect(await upgraded.getVersion(), Dbhelper.databaseVersion);
    expect(await upgraded.query(Dbhelper.tableCus), hasLength(1));
    expect(
      (await upgraded.query(Dbhelper.tableCus)).single['name'],
      'Customer stays',
    );
    final transactions = await upgraded.query(Dbhelper.tableTrans);
    expect(transactions, hasLength(1));
    expect(transactions.single['info'], 'Customer history stays');

    final tables = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(tables.map((row) => row['name']), isNot(contains('suppliers')));
    expect(tables.map((row) => row['name']), isNot(contains('communities')));
    final columns = await upgraded.rawQuery(
      'PRAGMA table_info(${Dbhelper.tableTrans})',
    );
    expect(columns.map((row) => row['name']), isNot(contains('suppid')));
    expect(
      columns.map((row) => row['name']),
      contains(Dbhelper.colTranPaymentDueAt),
    );
    expect(
      columns.map((row) => row['name']),
      contains(Dbhelper.colTranPaymentDueMinute),
    );
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
