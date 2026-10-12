import 'dart:async';

import 'package:digitalkhata/db/dbhelper.dart';
import 'package:digitalkhata/db/khata_guard.dart';

export 'package:digitalkhata/db/khata_guard.dart'
    show KhataNotSettledException, isSettled;
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/model/transactionmodel.dart';
import 'package:digitalkhata/services/auto_sync_service.dart';
import 'package:digitalkhata/services/cloud_services.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

class Dbprovider extends ChangeNotifier {
  final Dbhelper dbhelper = Dbhelper.getInstance;
  final DriveBackupService _backupService = DriveBackupService();
  final PaymentReminderService _paymentReminders =
      PaymentReminderService.instance;

  /// Scheduled Google Drive backup of the signed-in user (upload on schedule,
  /// pull on reconnect/resume). Null while nobody is signed in.
  AutoSyncService? _autoSync;
  AutoSyncService? get autoSync => _autoSync;

  /// Firebase UID whose data is loaded, or null when signed out.
  String? _activeUid;
  String? get activeUid => _activeUid;

  StreamSubscription<User?>? _authSub;

  /// Serialises [openForUser] / [closeSession].
  Future<void> _sessionChange = Future<void>.value();

  // --- Data Lists ---
  List<Customermodel> _allcustomers = [];
  List<TransactionModel> _customerTransactions = [];

  // --- Getters ---
  List<Customermodel> get allCustomers => _allcustomers;
  List<TransactionModel> get customerTransactions => _customerTransactions;

  /// Whose history [customerTransactions] hold. A ledger screen shows the
  /// list only once it belongs to its own customer.
  int? _customerTransactionsOwner;
  int? get customerTransactionsOwner => _customerTransactionsOwner;

  // --- Pro Stats ---
  double _customerToReceive = 0.0;
  double _customerToPay = 0.0;
  double get customerToReceive => _customerToReceive;
  double get customerToPay => _customerToPay;

  bool _isLoadingInitialData = true;
  String? _initialLoadError;
  String? _operationError;
  bool get isLoadingInitialData => _isLoadingInitialData;
  String? get initialLoadError => _initialLoadError;
  String? get operationError => _operationError;

  Future<void> _initialization = Future<void>.value();
  Future<void> get initialization => _initialization;

  Dbprovider() {
    // The data and backup owner always follow the authenticated user.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final active = _activeUid;
      if (active == null) return; // splash / login open the first session
      if (user == null) {
        unawaited(closeSession());
      } else if (user.uid != active) {
        unawaited(openForUser(user.uid));
      }
    });
  }

  /// Loads [uid]'s own local database and starts a backup service bound to
  /// that user. Safe to call repeatedly.
  Future<void> openForUser(String uid) => _serialised(() async {
    if (_activeUid == uid) {
      await _initialization;
      return;
    }
    await _closeSessionNow();

    try {
      await dbhelper.useAccount(uid);
    } catch (e) {
      // _init() below reports the unusable database to the user.
      debugPrint('Opening database for user failed: $e');
    }
    _activeUid = uid;
    _autoSync = AutoSyncService(
      ownerUid: uid,
      dbhelper: dbhelper,
      cloud: _backupService,
      reloadData: _reloadDataAfterRestore,
    );
    _initialization = _init();
    await _initialization;
  });

  /// Logout: stops backup work for the current user and closes their data.
  Future<void> closeSession() => _serialised(_closeSessionNow);

  Future<void> _closeSessionNow() async {
    final sync = _autoSync;
    // A reminder tapped under this account must not open the next one's data.
    if (_activeUid != null) _paymentReminders.tappedTransactionId.value = null;
    _autoSync = null;
    _activeUid = null;
    if (sync != null) {
      await sync.shutdown();
      sync.dispose();
    }
    try {
      await _paymentReminders.cancelAll();
    } catch (error, stackTrace) {
      debugPrint('Cancelling payment reminders failed: $error\n$stackTrace');
    }
    await dbhelper.clearAccount();
    _clearLoadedData();
    _initialization = Future<void>.value();
    notifyListeners();
  }

  void _reportReminderTimePassed() {
    _operationError =
        'The selected payment alert time has passed. The entry was saved, '
        'but no notification was scheduled. Edit it to choose a future time.';
    notifyListeners();
  }

  Future<void> _serialised(Future<void> Function() action) {
    final next = _sessionChange.catchError((_) {}).then((_) => action());
    _sessionChange = next;
    return next;
  }

  void _clearLoadedData() {
    _allcustomers = [];
    _customerTransactions = [];
    _customerTransactionsOwner = null;
    _calculateStats();
    _isLoadingInitialData = true;
    _initialLoadError = null;
    _operationError = null;
  }

  Future<void> _init() async {
    _isLoadingInitialData = true;
    _initialLoadError = null;
    notifyListeners();

    try {
      final db = await dbhelper.getDB();
      final customerRows = await db.query(
        Dbhelper.tableCus,
        orderBy:
            "${Dbhelper.colCustomerCreatedAt} DESC, ${Dbhelper.colCustomerId} DESC",
      );

      _allcustomers = customerRows
          .map((row) => Customermodel.fromMap(row))
          .toList();
      _calculateStats();
      // Not awaited: this talks to the OS once per reminder, and waiting for
      // it kept the splash screen up long after the data was ready.
      unawaited(_restoreReminders(db));
    } catch (error, stackTrace) {
      debugPrint('Initial database load failed: $error\n$stackTrace');
      _initialLoadError =
          'Your local data could not be loaded. Check available storage and retry.';
    } finally {
      _isLoadingInitialData = false;
      notifyListeners();
    }
  }

  Future<void> _restoreReminders(DatabaseExecutor db) async {
    final uid = _activeUid;
    try {
      // Return dates that have passed are not reported here: each one is
      // marked overdue on its entry, where it can be extended.
      final result = await _paymentReminders.rescheduleAll(db);
      if (result.failedTransactions > 0 && uid == _activeUid) {
        debugPrint(
          'Could not restore ${result.failedTransactions} payment '
          'reminders. First error: ${result.firstFailure}',
        );
        _operationError =
            '${result.failedTransactions} payment reminder(s) could not be '
            'scheduled. Check their return dates and notification access.';
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('Restoring payment reminders failed: $error\n$stackTrace');
      if (uid == _activeUid) {
        _reportOperationError('Restoring payment reminders', error);
      }
    }
  }

  /// A balance change can settle a khata or reopen it, so the reminders of
  /// every entry of that customer are cancelled or scheduled to match.
  Future<void> _syncCustomerReminders(DatabaseExecutor db, int customerId) async {
    try {
      await _paymentReminders.rescheduleAll(db, customerId: customerId);
    } catch (error, stackTrace) {
      debugPrint('Refreshing customer reminders failed: $error\n$stackTrace');
    }
  }

  Future<void> retryInitialization() => _init();

  Future<void> _reloadDataAfterRestore() async {
    await _init();
    if (_initialLoadError != null) {
      throw StateError(_initialLoadError!);
    }
  }

  void clearOperationError() {
    if (_operationError == null) return;
    _operationError = null;
    notifyListeners();
  }

  void _reportOperationError(String operation, Object error) {
    debugPrint('$operation failed: $error');
    _operationError =
        '$operation could not be completed. Check your data and try again.';
    notifyListeners();
  }

  // ==========================================
  // SYNC SECTION
  // ==========================================

  /// Manual "Sync now" (auto-sync does this on its own).
  Future<String?> syncToCloud({required Function(String) onStatus}) async {
    final sync = _autoSync;
    if (sync == null) return 'You are signed out.';
    return sync.syncNowManual();
  }

  /// Manual restore: replaces the signed-in user's local data with their
  /// cloud backup.
  Future<String?> restoreFromCloud({
    required Function(String) onStatus,
  }) async {
    final sync = _autoSync;
    if (sync == null) return 'You are signed out.';
    return sync.forceRestore((m) => onStatus(m));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _autoSync?.dispose();
    super.dispose();
  }

  // ==========================================
  // CUSTOMER SECTION
  // ==========================================

  Future<void> getAllCustomers() async {
    try {
      final db = await dbhelper.getDB();
      final data = await db.query(
        Dbhelper.tableCus,
        orderBy:
            "${Dbhelper.colCustomerCreatedAt} DESC, ${Dbhelper.colCustomerId} DESC",
      );
      _allcustomers = data.map((e) => Customermodel.fromMap(e)).toList();
      _calculateStats();
      notifyListeners();
    } catch (e) {
      _reportOperationError('Loading customers', e);
    }
  }

  void _calculateStats() {
    double receive = 0;
    double pay = 0;
    for (var customer in _allcustomers) {
      if (customer.currentBalance > 0) {
        receive += customer.currentBalance;
      } else if (customer.currentBalance < 0) {
        pay += customer.currentBalance.abs();
      }
    }
    _customerToReceive = receive;
    _customerToPay = pay;
  }

  Future<void> addTransactionForCustomer(
    TransactionModel transaction,
    Customermodel customer,
  ) async {
    if (customer.id == null) return;

    final db = await dbhelper.getDB();

    try {
      final transactionId = await db.transaction((txn) async {
        // 1. Log the transaction
        final id = await txn.insert(Dbhelper.tableTrans, transaction.toMap());

        // 2. Move the stored balance by this entry. Relative update in the
        // same DB transaction, so a stale copy of the customer on screen can
        // never overwrite the balance.
        final change = transaction.type == "Gave"
            ? transaction.amount
            : -transaction.amount;
        await txn.rawUpdate(
          'UPDATE ${Dbhelper.tableCus} SET '
          '${Dbhelper.colCustomerCurrentBalance} = '
          '${Dbhelper.colCustomerCurrentBalance} + ? '
          'WHERE ${Dbhelper.colCustomerId} = ?',
          [change, customer.id],
        );
        return id;
      });

      _autoSync?.markDirty();
      if (transaction.paymentDueDate != null) {
        try {
          final scheduled = await _paymentReminders.scheduleTransaction(
            transactionId: transactionId,
            customerName: customer.name,
            amount: transaction.amount,
            type: transaction.type,
            dueDate: transaction.paymentDueDate!,
            dueDayMinutes: transaction.paymentDueMinute,
          );
          if (!scheduled) {
            _reportReminderTimePassed();
          }
        } catch (error, stackTrace) {
          debugPrint('Scheduling payment reminder failed: $error\n$stackTrace');
          _reportOperationError('Scheduling payment reminder', error);
        }
      }

      // Only this customer changed: refresh that row and their history,
      // then update the screen once.
      await _syncCustomerReminders(db, customer.id!);
      await _refreshCustomer(db, customer.id!);
      await _loadCustomerTransactions(db, customer.id!);
      notifyListeners();
    } catch (e) {
      _reportOperationError('Saving customer transaction', e);
    }
  }

  /// Modifies the amount and/or description of an existing customer entry and
  /// keeps the customer's balance exact, all in one DB transaction.
  Future<void> updateTransaction(
    TransactionModel original, {
    required double amount,
    required String description,
    required DateTime? paymentDueDate,
    required int? paymentDueMinute,
  }) async {
    final id = original.id;
    if (id == null || amount <= 0) return;

    double effect(double value) => original.type == "Gave" ? value : -value;
    final balanceChange = effect(amount) - effect(original.amount);

    try {
      final db = await dbhelper.getDB();
      await db.transaction((txn) async {
        await txn.update(
          Dbhelper.tableTrans,
          {
            Dbhelper.colAmount: amount,
            Dbhelper.colTranInfo: description,
            Dbhelper.colTranPaymentDueAt: paymentDueDate == null
                ? null
                : DateTime(
                    paymentDueDate.year,
                    paymentDueDate.month,
                    paymentDueDate.day,
                  ).toIso8601String(),
            Dbhelper.colTranPaymentDueMinute: paymentDueDate == null
                ? null
                : paymentDueMinute,
          },
          where: "${Dbhelper.colTransId} = ?",
          whereArgs: [id],
        );
        if (original.customerId != null && balanceChange != 0) {
          await txn.rawUpdate(
            'UPDATE ${Dbhelper.tableCus} SET '
            '${Dbhelper.colCustomerCurrentBalance} = '
            '${Dbhelper.colCustomerCurrentBalance} + ? '
            'WHERE ${Dbhelper.colCustomerId} = ?',
            [balanceChange, original.customerId],
          );
        }
      });

      _autoSync?.markDirty();

      if (original.customerId != null) {
        await _refreshCustomer(db, original.customerId!);
        await _loadCustomerTransactions(db, original.customerId!);
        try {
          if (paymentDueDate == null) {
            await _paymentReminders.cancelTransaction(id);
          } else {
            final customerRows = await db.query(
              Dbhelper.tableCus,
              columns: [Dbhelper.colCustomerName],
              where: "${Dbhelper.colCustomerId} = ?",
              whereArgs: [original.customerId],
              limit: 1,
            );
            final customerName = customerRows.first[Dbhelper.colCustomerName]
                as String;
            final scheduled = await _paymentReminders.scheduleTransaction(
              transactionId: id,
              customerName: customerName,
              amount: amount,
              type: original.type,
              dueDate: paymentDueDate,
              dueDayMinutes: paymentDueMinute,
            );
            // An unchanged return date may already be overdue; that is shown
            // on the entry itself and is not a failed save.
            final dueChanged =
                !DateUtils.isSameDay(paymentDueDate, original.paymentDueDate) ||
                paymentDueMinute != original.paymentDueMinute;
            if (!scheduled && dueChanged) {
              _reportReminderTimePassed();
            }
          }
        } catch (error, stackTrace) {
          debugPrint('Updating payment reminder failed: $error\n$stackTrace');
          _reportOperationError('Updating payment reminder', error);
        }
        await _syncCustomerReminders(db, original.customerId!);
      }
      notifyListeners();
    } catch (e) {
      _reportOperationError('Updating transaction', e);
    }
  }

  /// Moves an entry's return date to [dueDate] at [dueMinute] and reschedules
  /// its reminders. Returns whether the new date was stored.
  Future<bool> extendPaymentDueDate(
    TransactionModel transaction, {
    required DateTime dueDate,
    required int dueMinute,
  }) async {
    await updateTransaction(
      transaction,
      amount: transaction.amount,
      description: transaction.desp,
      paymentDueDate: dueDate,
      paymentDueMinute: dueMinute,
    );
    return _customerTransactions.any(
      (saved) =>
          saved.id == transaction.id &&
          DateUtils.isSameDay(saved.paymentDueDate, dueDate) &&
          saved.paymentDueMinute == dueMinute,
    );
  }

  /// The customer whose ledger holds [transactionId], or null when the entry
  /// or its customer no longer exists.
  Future<Customermodel?> customerForTransaction(int transactionId) async {
    try {
      final db = await dbhelper.getDB();
      final rows = await db.query(
        Dbhelper.tableTrans,
        columns: [Dbhelper.colTranCusId],
        where: "${Dbhelper.colTransId} = ?",
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final customerId = rows.first[Dbhelper.colTranCusId] as int?;
      return _allcustomers.where((c) => c.id == customerId).firstOrNull;
    } catch (error, stackTrace) {
      debugPrint('Finding the reminder customer failed: $error\n$stackTrace');
      return null;
    }
  }

  Future<void> getTransactionsByCusId(int customerId) async {
    try {
      await _loadCustomerTransactions(await dbhelper.getDB(), customerId);
      notifyListeners();
    } catch (e) {
      _reportOperationError('Loading customer transactions', e);
    }
  }

  Future<void> _loadCustomerTransactions(
    DatabaseExecutor db,
    int customerId,
  ) async {
    final data = await db.query(
      Dbhelper.tableTrans,
      where: "${Dbhelper.colTranCusId} = ?",
      whereArgs: [customerId],
      orderBy: "${Dbhelper.colTranTime} DESC, ${Dbhelper.colTransId} DESC",
    );
    _customerTransactions = data
        .map((e) => TransactionModel.fromMap(e))
        .toList();
    _customerTransactionsOwner = customerId;
  }

  /// Re-reads one customer and swaps it into the list, instead of loading
  /// every customer again after each change. Does not notify.
  Future<void> _refreshCustomer(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      Dbhelper.tableCus,
      where: "${Dbhelper.colCustomerId} = ?",
      whereArgs: [id],
      limit: 1,
    );
    _allcustomers = _withRow(
      _allcustomers,
      _allcustomers.indexWhere((c) => c.id == id),
      rows.isEmpty ? null : Customermodel.fromMap(rows.first),
      newestFirst: true,
    );
    _calculateStats();
  }

  /// A new list with the item at [index] replaced by [fresh] (removed when
  /// [fresh] is null, added when [index] is -1). The lists handed to the UI
  /// are never modified in place, so screens can tell when theirs changed.
  static List<T> _withRow<T>(
    List<T> items,
    int index,
    T? fresh, {
    required bool newestFirst,
  }) {
    final list = List<T>.of(items);
    if (fresh == null) {
      if (index >= 0) list.removeAt(index);
    } else if (index >= 0) {
      list[index] = fresh;
    } else if (newestFirst) {
      list.insert(0, fresh);
    } else {
      list.add(fresh);
    }
    return list;
  }

  /// Fresh copy of one customer's ledger (customer + entries, newest first)
  /// for reports. Does not touch the lists shown on screen.
  Future<(Customermodel, List<TransactionModel>)?> customerStatement(
    int customerId,
  ) async {
    final db = await dbhelper.getDB();
    final customerRows = await db.query(
      Dbhelper.tableCus,
      where: "${Dbhelper.colCustomerId} = ?",
      whereArgs: [customerId],
      limit: 1,
    );
    if (customerRows.isEmpty) return null;
    final rows = await db.query(
      Dbhelper.tableTrans,
      where: "${Dbhelper.colTranCusId} = ?",
      whereArgs: [customerId],
      orderBy: "${Dbhelper.colTranTime} DESC, ${Dbhelper.colTransId} DESC",
    );
    return (
      Customermodel.fromMap(customerRows.first),
      rows.map((e) => TransactionModel.fromMap(e)).toList(),
    );
  }

  Future<void> addCustomer(Customermodel newCustomer) async {
    final db = await dbhelper.getDB();
    final id = await db.insert(Dbhelper.tableCus, newCustomer.toMap());
    _autoSync?.markDirty();
    await _refreshCustomer(db, id);
    notifyListeners();
  }

  /// Adds a customer and, if [openingAmount] > 0, records it as an
  /// "Opening Balance" transaction so the ledger history matches the balance.
  /// [openingType] is "Gave" (customer owes you) or "Got" (you owe customer).
  Future<void> addCustomerWithOpeningBalance(
    Customermodel newCustomer, {
    double openingAmount = 0,
    String? openingType,
    DateTime? paymentDueDate,
    int? paymentDueMinute,
  }) async {
    final db = await dbhelper.getDB();
    final hasOpening = openingAmount > 0 && openingType != null;
    final signedBalance = !hasOpening
        ? 0.0
        : (openingType == "Gave" ? openingAmount : -openingAmount);

    final (newId, openingTransactionId) = await db.transaction((txn) async {
      final id = await txn.insert(
        Dbhelper.tableCus,
        newCustomer.copyWith(currentBalance: signedBalance).toMap(),
      );
      int? transactionId;
      if (hasOpening) {
        transactionId = await txn.insert(
          Dbhelper.tableTrans,
          TransactionModel(
            customerId: id,
            amount: openingAmount,
            type: openingType,
            desp: "Opening Balance",
            dateTime: DateTime.now(),
            paymentDueDate: paymentDueDate,
            paymentDueMinute: paymentDueMinute,
          ).toMap(),
        );
      }
      return (id, transactionId);
    });

    _autoSync?.markDirty();
    if (openingTransactionId != null && paymentDueDate != null) {
      try {
        final scheduled = await _paymentReminders.scheduleTransaction(
          transactionId: openingTransactionId,
          customerName: newCustomer.name,
          amount: openingAmount,
          type: openingType!,
          dueDate: paymentDueDate,
          dueDayMinutes: paymentDueMinute,
        );
        if (!scheduled) {
          _reportReminderTimePassed();
        }
      } catch (error, stackTrace) {
        debugPrint('Scheduling payment reminder failed: $error\n$stackTrace');
        _reportOperationError('Scheduling payment reminder', error);
      }
    }
    await _refreshCustomer(db, newId);
    notifyListeners();
  }

  Future<void> updateCustomer(Customermodel customer, int id) async {
    final db = await dbhelper.getDB();
    final changedRows = await db.update(
      Dbhelper.tableCus,
      customer.toMap(),
      where: "${Dbhelper.colCustomerId} = ?",
      whereArgs: [id],
    );
    if (changedRows > 0) _autoSync?.markDirty();
    await _refreshCustomer(db, id);
    notifyListeners();
  }

  /// Deletes a customer and their history, ONLY when their khata is zero.
  /// Throws [KhataNotSettledException] otherwise (checked inside the same DB
  /// transaction as the delete, so a just-added entry is always respected).
  /// The database enforces the same rule on its own as a second lock.
  Future<void> deleteCustomer(int id) async {
    final db = await dbhelper.getDB();
    final deletedRows = await deleteSettledCustomer(db, id);
    if (deletedRows > 0) _autoSync?.markDirty();
    if (deletedRows > 0) {
      try {
        await _paymentReminders.rescheduleAll(db);
      } catch (error, stackTrace) {
        debugPrint(
          'Refreshing reminders after customer deletion failed: '
          '$error\n$stackTrace',
        );
        _reportOperationError('Refreshing payment reminders', error);
      }
    }
    await _refreshCustomer(db, id);
    notifyListeners();
  }

}
