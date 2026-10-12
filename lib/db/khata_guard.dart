import 'package:digitalkhata/db/dbhelper.dart';
import 'package:sqflite/sqflite.dart';

/// A customer whose khata is not settled cannot be deleted, so no outstanding
/// amount or its history can be lost.
class KhataNotSettledException implements Exception {
  const KhataNotSettledException(this.balance);

  /// Remaining balance (> 0 you will get, < 0 you will pay).
  final double balance;

  @override
  String toString() => 'KhataNotSettledException($balance)';
}

/// Balances are stored as REAL; anything under half a paisa counts as zero.
bool isSettled(double balance) => balance.abs() < 0.005;

/// Deletes customer [id] together with their history, but ONLY when their
/// balance is zero. The balance is read inside the same DB transaction as
/// the delete, so an entry added at the same moment is always respected.
///
/// Returns the number of deleted customers (0 if it did not exist) or
/// throws [KhataNotSettledException].
Future<int> deleteSettledCustomer(Database db, int id) => _deleteIfSettled(
  db,
  table: Dbhelper.tableCus,
  idColumn: Dbhelper.colCustomerId,
  balanceColumn: Dbhelper.colCustomerCurrentBalance,
  id: id,
);

Future<int> _deleteIfSettled(
  Database db, {
  required String table,
  required String idColumn,
  required String balanceColumn,
  required int id,
}) {
  return db.transaction((txn) async {
    final rows = await txn.query(
      table,
      columns: [balanceColumn],
      where: '$idColumn = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final balance = (rows.first[balanceColumn] as num?)?.toDouble() ?? 0.0;
    if (!isSettled(balance)) throw KhataNotSettledException(balance);
    return txn.delete(table, where: '$idColumn = ?', whereArgs: [id]);
  });
}
