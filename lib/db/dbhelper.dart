import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class Dbhelper {
  Dbhelper._();
  static final Dbhelper getInstance = Dbhelper._();

  static const String tableCus = "customer";
  static const String tableTrans = "transactions";

  static const String colCustomerId = "id";
  static const String colCustomerName = "name";
  static const String colCustomerphoneNo = "num";
  static const String colCustomerdesp = "desp";
  static const String colCustomerImg = "img";
  static const String colCustomerTotalAmount = "amount";
  static const String colCustomerCreatedAt = "time";
  static const String colCustomerAddress = "address";
  static const String colCustomerCurrentBalance = "current";

  static const String colTransId = "transid";
  static const String colTranCusId = "cusid";
  static const String colAmount = "amount";
  static const String colTrantype = "type";
  static const String colTranTime = "tranTime";
  static const String colTranInfo = "info";
  static const String colTranPaymentDueAt = "paymentDueAt";
  static const String colTranPaymentDueMinute = "paymentDueMinute";

  /// Shared database of app versions without per-user databases. It is
  /// handed over once to the first user who logs in afterwards.
  static const String legacyDbFileName = "DigitalKhata_Active.db";
  static const int databaseVersion = 7;

  // Point of sale. A sale keeps its own copy of each item's name and price,
  // so editing or deleting a product never changes past sales.
  static const String tableProducts = "products";
  static const String colProductId = "id";
  static const String colProductName = "name";
  static const String colProductPrice = "price";

  static const String tableSales = "sales";
  static const String colSaleId = "id";
  static const String colSaleTime = "time";
  static const String colSaleTotal = "total";
  static const String colSalePayment = "payment";
  static const String colSaleCustomerId = "customerId";
  static const String colSaleCustomerName = "customerName";

  static const String tableSaleItems = "sale_items";
  static const String colSaleItemId = "id";
  static const String colSaleItemSaleId = "saleId";
  static const String colSaleItemName = "name";
  static const String colSaleItemPrice = "price";
  static const String colSaleItemQty = "qty";

  /// Raised by the database itself when a customer with a remaining balance
  /// is about to be deleted (see [_createSettlementLocks]).
  static const String notSettledError = 'khata_not_settled';

  static String dbFileNameFor(String uid) => "DigitalKhata_$uid.db";

  Database? _mydb;
  Future<Database>? _dbOpening;
  String? _ownerUid;

  /// Firebase UID whose database is active, or null when logged out.
  String? get ownerUid => _ownerUid;

  /// Makes [uid]'s own database the active one.
  Future<void> useAccount(String uid) async {
    if (_ownerUid == uid) return;
    await closeDB();
    await _adoptLegacyDatabase(uid);
    _ownerUid = uid;
  }

  /// Closes the active database on logout; nothing is readable afterwards.
  Future<void> clearAccount() async {
    await closeDB();
    _ownerUid = null;
  }

  Future<String> getDbPath() async {
    final uid = _ownerUid;
    if (uid == null) throw StateError('No signed-in user database');
    final directory = await getApplicationDocumentsDirectory();
    return join(directory.path, dbFileNameFor(uid));
  }

  Future<void> _adoptLegacyDatabase(String uid) async {
    final directory = await getApplicationDocumentsDirectory();
    final target = join(directory.path, dbFileNameFor(uid));
    final legacy = join(directory.path, legacyDbFileName);
    if (await File(target).exists() || !await File(legacy).exists()) return;

    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('$legacy$suffix');
      if (await f.exists()) await f.rename('$target$suffix');
    }
  }

  Future<Database> getDB() async {
    if (_mydb != null && _mydb!.isOpen) return _mydb!;
    if (_dbOpening != null) return await _dbOpening!;

    final opening = openDB();
    _dbOpening = opening;
    try {
      final db = await opening;
      _mydb = db;
      return db;
    } finally {
      _dbOpening = null;
    }
  }

  Future<void> closeDB() async {
    final opening = _dbOpening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {}
    }
    if (_mydb != null && _mydb!.isOpen) {
      await _mydb!.close();
      _mydb = null;
    }
  }

  Future<Database> openDB() async {
    // 🔥 Standardized Name: This prevents the "400 PKR" dummy data issue
    final path = await getDbPath();

    return await openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute("PRAGMA foreign_keys=ON");
        // Write-ahead logging: saving an entry needs one disk sync instead
        // of several, and reads are never blocked by a running backup.
        try {
          await db.setJournalMode('WAL');
        } catch (_) {
          // Not available on this device: the default journal still works.
        }
      },
      onCreate: (db, version) async => createSchema(db),
      onUpgrade: migrate,
      onDowngrade: (db, oldVersion, newVersion) async {
        throw StateError(
          'Database downgrade from $oldVersion to $newVersion is not '
          'supported. Local data was preserved.',
        );
      },
    );
  }

  static Future<void> migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion; version < newVersion; version++) {
      switch (version + 1) {
        case 2:
          await _createIndexes(db);
        case 3:
          await _createSettlementLocks(db);
        case 4:
          await _removeSupplierAndCommunityData(db);
        case 5:
          await _addPaymentDueDate(db);
        case 6:
          await _addPaymentDueMinute(db);
        case 7:
          await _createPosTables(db);
        default:
          throw StateError(
            'No database migration is defined for version ${version + 1}.',
          );
      }
    }
  }

  /// Full current schema (tables, indexes, delete locks) for a new database.
  static Future<void> createSchema(Database db) async {
    await _createTables(db);
    await _createIndexes(db);
    await _createSettlementLocks(db);
  }

  /// The database refuses to delete a customer whose khata is not settled.
  /// The limit matches `isSettled` (anything under half a paisa counts as
  /// zero).
  static Future<void> _createSettlementLocks(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TRIGGER IF NOT EXISTS trg_customer_keep_unsettled '
      'BEFORE DELETE ON $tableCus '
      'WHEN ABS(OLD.$colCustomerCurrentBalance) >= 0.005 '
      "BEGIN SELECT RAISE(ABORT, '$notSettledError'); END",
    );
  }

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_customer_time '
      'ON $tableTrans ($colTranCusId, $colTranTime)',
    );
  }

  static Future<void> _addPaymentDueDate(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE $tableTrans ADD COLUMN $colTranPaymentDueAt TEXT',
    );
  }

  static Future<void> _addPaymentDueMinute(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE $tableTrans ADD COLUMN $colTranPaymentDueMinute INTEGER',
    );
  }

  static Future<void> _createTables(Database db) async {
    await _createCustomerTable(db);
    await _createTransactionTable(db);
    await _createPosTables(db);
  }

  static Future<void> _createPosTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableProducts(
        $colProductId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colProductName TEXT NOT NULL,
        $colProductPrice REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSales(
        $colSaleId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colSaleTime TEXT NOT NULL,
        $colSaleTotal REAL NOT NULL,
        $colSalePayment TEXT NOT NULL,
        $colSaleCustomerId INTEGER,
        $colSaleCustomerName TEXT,
        FOREIGN KEY($colSaleCustomerId) REFERENCES $tableCus($colCustomerId)
          ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableSaleItems(
        $colSaleItemId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colSaleItemSaleId INTEGER NOT NULL,
        $colSaleItemName TEXT NOT NULL,
        $colSaleItemPrice REAL NOT NULL,
        $colSaleItemQty INTEGER NOT NULL,
        FOREIGN KEY($colSaleItemSaleId) REFERENCES $tableSales($colSaleId)
          ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale '
      'ON $tableSaleItems ($colSaleItemSaleId)',
    );
  }

  /// Drops supplier/community records and supplier-only transaction history.
  /// Customer records and customer-linked transactions are retained.
  static Future<void> _removeSupplierAndCommunityData(
    DatabaseExecutor db,
  ) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_supplier_keep_unsettled');
    await db.execute('DROP INDEX IF EXISTS idx_transactions_supplier_time');
    await db.execute('DROP TABLE IF EXISTS _customer_transactions');
    await db.execute('''
      CREATE TABLE _customer_transactions(
        $colTransId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colTranCusId INTEGER,
        $colTranInfo TEXT,
        $colTranTime TEXT NOT NULL,
        $colTrantype TEXT NOT NULL,
        $colAmount REAL NOT NULL,
        FOREIGN KEY($colTranCusId) REFERENCES $tableCus($colCustomerId)
          ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      INSERT INTO _customer_transactions(
        $colTransId, $colTranCusId, $colTranInfo, $colTranTime,
        $colTrantype, $colAmount
      )
      SELECT $colTransId, $colTranCusId, $colTranInfo, $colTranTime,
        $colTrantype, $colAmount
      FROM $tableTrans
      WHERE $colTranCusId IS NOT NULL
    ''');
    await db.execute('DROP TABLE $tableTrans');
    await db.execute(
      'ALTER TABLE _customer_transactions RENAME TO $tableTrans',
    );
    await db.execute('DROP TABLE IF EXISTS communities');
    await db.execute('DROP TABLE IF EXISTS suppliers');
    await _createIndexes(db);
    await _createSettlementLocks(db);
  }

  static Future<void> _createCustomerTable(Database db) async {
    await db.execute('''
      CREATE TABLE $tableCus(
        $colCustomerId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colCustomerName TEXT NOT NULL,
        $colCustomerImg TEXT,
        $colCustomerdesp TEXT,
        $colCustomerTotalAmount REAL NOT NULL DEFAULT 0,
        $colCustomerCreatedAt TEXT NOT NULL,
        $colCustomerphoneNo TEXT NOT NULL,
        $colCustomerCurrentBalance REAL NOT NULL DEFAULT 0,
        $colCustomerAddress TEXT
      )
    ''');
  }

  static Future<void> _createTransactionTable(Database db) async {
    await db.execute('''
      CREATE TABLE $tableTrans(
        $colTransId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colTranCusId INTEGER,
        $colTranInfo TEXT,
        $colTranTime TEXT NOT NULL,
        $colTrantype TEXT NOT NULL,
        $colAmount REAL NOT NULL,
        $colTranPaymentDueAt TEXT,
        $colTranPaymentDueMinute INTEGER,
        FOREIGN KEY($colTranCusId) REFERENCES $tableCus($colCustomerId) ON DELETE CASCADE
      )
    ''');
  }
}
