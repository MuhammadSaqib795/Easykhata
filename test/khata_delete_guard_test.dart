import 'package:digitalkhata/db/dbhelper.dart';
import 'package:digitalkhata/db/khata_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: Dbhelper.databaseVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, _) => Dbhelper.createSchema(db),
      ),
    );
  });

  tearDown(() => db.close());

  Future<int> addCustomer(double balance) => db.insert(Dbhelper.tableCus, {
    Dbhelper.colCustomerName: 'Khawar',
    Dbhelper.colCustomerphoneNo: '03001234567',
    Dbhelper.colCustomerCreatedAt: DateTime(2026).toIso8601String(),
    Dbhelper.colCustomerCurrentBalance: balance,
  });

  Future<void> addEntry({int? customerId}) =>
      db.insert(Dbhelper.tableTrans, {
        Dbhelper.colTranCusId: customerId,
        Dbhelper.colTranInfo: 'Rice',
        Dbhelper.colTranTime: DateTime(2026).toIso8601String(),
        Dbhelper.colTrantype: 'Gave',
        Dbhelper.colAmount: 50.0,
      });

  Future<int> count(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']! as int;

  /// A delete that bypasses the app's own check, straight on the table.
  Future<int> rawDelete(String table, String idColumn, int id) =>
      db.delete(table, where: '$idColumn = ?', whereArgs: [id]);

  final refusedByDatabase = throwsA(
    isA<DatabaseException>().having(
      (e) => e.toString(),
      'message',
      contains(Dbhelper.notSettledError),
    ),
  );

  test('database itself refuses to delete an unsettled customer', () async {
    final id = await addCustomer(50);
    await addEntry(customerId: id);

    await expectLater(
      rawDelete(Dbhelper.tableCus, Dbhelper.colCustomerId, id),
      refusedByDatabase,
    );
    await expectLater(db.delete(Dbhelper.tableCus), refusedByDatabase);
    expect(await count(Dbhelper.tableCus), 1);
    expect(await count(Dbhelper.tableTrans), 1);
  });

  test('database allows deleting a settled customer', () async {
    final customer = await addCustomer(0);
    expect(
      await rawDelete(Dbhelper.tableCus, Dbhelper.colCustomerId, customer),
      1,
    );
  });

  test('customer with money to receive cannot be deleted; history stays', () async {
    final id = await addCustomer(50);
    await addEntry(customerId: id);

    await expectLater(
      deleteSettledCustomer(db, id),
      throwsA(
        isA<KhataNotSettledException>().having((e) => e.balance, 'balance', 50),
      ),
    );
    expect(await count(Dbhelper.tableCus), 1);
    expect(await count(Dbhelper.tableTrans), 1);
  });

  test('customer with money to pay cannot be deleted', () async {
    final id = await addCustomer(-30);
    await expectLater(
      deleteSettledCustomer(db, id),
      throwsA(isA<KhataNotSettledException>()),
    );
    expect(await count(Dbhelper.tableCus), 1);
  });

  test('settled customer can be deleted (with history)', () async {
    final id = await addCustomer(0);
    await addEntry(customerId: id);

    expect(await deleteSettledCustomer(db, id), 1);
    expect(await count(Dbhelper.tableCus), 0);
    expect(await count(Dbhelper.tableTrans), 0);
  });

  test('floating-point dust counts as settled', () async {
    final id = await addCustomer(0.0000001);
    expect(await deleteSettledCustomer(db, id), 1);
  });

  test('missing customer returns 0', () async {
    expect(await deleteSettledCustomer(db, 999), 0);
  });

  test('isSettled', () {
    expect(isSettled(0), isTrue);
    expect(isSettled(0.004), isTrue);
    expect(isSettled(-0.004), isTrue);
    expect(isSettled(0.01), isFalse);
    expect(isSettled(-50), isFalse);
  });
}
