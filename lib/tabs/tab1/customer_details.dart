import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/services/khata_pdf_service.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/party_ledger_page.dart';
import 'package:digitalkhata/widgets/return_date_sheet.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/dbprovider.dart';
import '../../model/transactionmodel.dart';
import '../../widgets/delete_confirmation_dialog.dart';
import '../../widgets/transaction_calculator_sheet.dart';

class Customerdetails extends StatefulWidget {
  final Customermodel item;

  /// Entry whose return date should be offered for extension as soon as the
  /// ledger opens (the user tapped that entry's reminder).
  final int? extendTransactionId;

  /// Set when the ledger sits in a side pane instead of its own screen:
  /// called instead of leaving the screen after the customer is deleted.
  final VoidCallback? onClosed;

  const Customerdetails({
    super.key,
    required this.item,
    this.extendTransactionId,
    this.onClosed,
  });

  @override
  State<Customerdetails> createState() => _CustomerdetailsState();
}

class _CustomerdetailsState extends State<Customerdetails> {
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final id = widget.item.id;
      if (id == null) return;
      final dbProvider = context.read<Dbprovider>();
      await dbProvider.getTransactionsByCusId(id);
      final focus = widget.extendTransactionId;
      if (!mounted || focus == null) return;
      final tx = dbProvider.customerTransactions
          .where((t) => t.id == focus)
          .firstOrNull;
      if (tx?.paymentDueDate != null) await _extendReturnDate(tx!);
    });
  }

  /// Moves an entry's return date further out and reschedules its reminders.
  Future<void> _extendReturnDate(TransactionModel tx) async {
    final dueDate = tx.paymentDueDate;
    if (dueDate == null) return;
    final dbProvider = context.read<Dbprovider>();
    final choice = await showExtendReturnDateSheet(
      context: context,
      partyName: widget.item.name,
      currentDueDate: dueDate,
      currentDueMinute: tx.paymentDueMinute,
    );
    if (choice == null || !mounted) return;

    var notificationsAllowed = true;
    try {
      notificationsAllowed = await PaymentReminderService.instance
          .requestPermissions();
    } catch (error, stackTrace) {
      debugPrint(
        'Requesting payment reminder permission failed: $error\n$stackTrace',
      );
    }
    final saved = await dbProvider.extendPaymentDueDate(
      tx,
      dueDate: choice.date,
      dueMinute: choice.minutes,
    );
    if (!mounted) return;
    if (!saved) {
      showAppSnack(
        context,
        'The return date could not be extended. Please try again.',
        error: true,
      );
      return;
    }
    final time = TimeOfDay(
      hour: choice.minutes ~/ 60,
      minute: choice.minutes % 60,
    ).format(context);
    showAppSnack(
      context,
      notificationsAllowed
          ? 'Return date extended to ${formatDate(choice.date)} · $time.'
          : 'Return date extended to ${formatDate(choice.date)} · $time, '
                'but notifications are off for Easy Khata.',
      error: !notificationsAllowed,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only when THIS customer or their history changes.
    final customer = context.select<Dbprovider, Customermodel>(
      (db) => db.allCustomers.firstWhere(
        (c) => c.id == widget.item.id,
        orElse: () => widget.item,
      ),
    );
    // Null until this customer's own entries are loaded.
    final transactions = context.select<Dbprovider, List<TransactionModel>?>(
      (db) => db.customerTransactionsOwner == widget.item.id
          ? db.customerTransactions
          : null,
    );

    return PartyLedgerPage(
      title: 'Customer khata',
      name: customer.name,
      subtitle: customer.phoneNo,
      balance: customer.currentBalance,
      transactions: transactions ?? const [],
      loading: transactions == null,
      onGave: () => _addEntry(customer, 'Gave'),
      onGot: () => _addEntry(customer, 'Got'),
      onEditEntry: _editTransaction,
      onExtendEntry: _extendReturnDate,
      actions: [
        IconButton(
          tooltip: 'Share PDF',
          onPressed: _generatingPdf ? null : () => _exportPdf(share: true),
          icon: const Icon(Icons.share_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            if (v == 'pdf') _exportPdf(share: false);
            if (v == 'share') _exportPdf(share: true);
            if (v == 'delete') _confirmDeleteCustomer(customer);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'pdf',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.picture_as_pdf_outlined),
                title: Text('Download PDF'),
              ),
            ),
            PopupMenuItem(
              value: 'share',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.share_outlined),
                title: Text('Share PDF'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline, color: Color(0xFFB91C1C)),
                title: Text(
                  'Delete customer',
                  style: TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
            ),
          ],
        ),
      ],
      historyTrailing: TextButton.icon(
        onPressed: _generatingPdf ? null : () => _exportPdf(share: false),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: const Text('PDF'),
      ),
    );
  }

  /// Builds the customer's statement from a fresh read of THIS customer's
  /// entries, then opens the save/print dialog or the share sheet.
  Future<void> _exportPdf({required bool share}) async {
    final id = widget.item.id;
    if (_generatingPdf || id == null) return;
    setState(() => _generatingPdf = true);

    final provider = context.read<Dbprovider>();
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 18),
              Text('Generating PDF…'),
            ],
          ),
        ),
      ),
    );

    var dialogOpen = true;
    try {
      final statement = await provider.customerStatement(id);
      if (statement == null) throw StateError('Customer not found');
      final (customer, entries) = statement;
      final now = DateTime.now();
      final bytes = await KhataPdfService.buildCustomerStatement(
        customer: customer,
        newestFirst: entries,
        generatedAt: now,
      );
      final fileName = KhataPdfService.fileNameFor(customer.name, now);
      navigator.pop();
      dialogOpen = false;
      if (share) {
        await KhataPdfService.share(bytes, fileName);
      } else {
        await KhataPdfService.saveOrPrint(bytes, fileName);
      }
    } catch (e, st) {
      debugPrint('PDF export failed: $e\n$st');
      if (dialogOpen) navigator.pop();
      if (mounted) {
        showAppSnack(
          context,
          'The PDF could not be created. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  /// A customer can be deleted only when their khata is zero, and then only
  /// after a warning and explicit permission.
  Future<void> _confirmDeleteCustomer(Customermodel customer) async {
    if (customer.id == null) return;
    final dbProvider = context.read<Dbprovider>();

    if (!isSettled(customer.currentBalance)) {
      await showKhataNotSettledDialog(
        context: context,
        name: customer.name,
        balance: customer.currentBalance,
      );
      return;
    }

    final entries = dbProvider.customerTransactions
        .where((t) => t.customerId == customer.id)
        .length;
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Delete ${customer.name}?',
      content:
          'This khata is settled (balance Rs. 0). Deleting it permanently '
          'removes the customer and '
          '${entries == 0 ? 'their record' : 'all $entries history entries'}. '
          'This cannot be undone.',
      acknowledgement: entries == 0
          ? 'I understand this customer will be deleted permanently.'
          : 'I understand all $entries entries will be deleted permanently.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    try {
      await dbProvider.deleteCustomer(customer.id!);
      if (!mounted) return;
      showAppSnack(context, 'Customer deleted.');
      final onClosed = widget.onClosed;
      if (onClosed != null) {
        onClosed();
      } else {
        Navigator.of(context).pop();
      }
    } on KhataNotSettledException catch (e) {
      // An entry was added meanwhile: the database refused the delete.
      if (!mounted) return;
      await showKhataNotSettledDialog(
        context: context,
        name: customer.name,
        balance: e.balance,
      );
    } catch (e) {
      debugPrint('Delete customer failed: $e');
      if (!mounted) return;
      showAppSnack(
        context,
        'The customer could not be deleted. Please try again.',
        error: true,
      );
    }
  }

  void _editTransaction(TransactionModel tx) {
    final dbProvider = context.read<Dbprovider>();
    showTransactionCalculatorSheet(
      context: context,
      type: tx.type,
      subject: 'customer',
      isEdit: true,
      initialAmount: tx.amount,
      initialDescription: tx.desp,
      initialPaymentDueDate: tx.paymentDueDate,
      initialPaymentDueMinute: tx.paymentDueMinute,
      onSave: (amount, description, _, paymentDueDate, paymentDueMinute) =>
          dbProvider.updateTransaction(
            tx,
            amount: amount,
            description: description,
            paymentDueDate: paymentDueDate,
            paymentDueMinute: paymentDueMinute,
          ),
    );
  }

  void _addEntry(Customermodel customer, String type) {
    final dbProvider = context.read<Dbprovider>();
    showTransactionCalculatorSheet(
      context: context,
      type: type,
      subject: 'customer',
      onSave: (amount, description, date, paymentDueDate, paymentDueMinute) =>
          dbProvider.addTransactionForCustomer(
            TransactionModel(
              customerId: customer.id!,
              amount: amount,
              type: type,
              desp: description,
              dateTime: date,
              paymentDueDate: paymentDueDate,
              paymentDueMinute: paymentDueMinute,
            ),
            customer,
          ),
    );
  }
}
