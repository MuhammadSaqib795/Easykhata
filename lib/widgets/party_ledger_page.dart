import 'package:digitalkhata/model/transactionmodel.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/transaction_history_list.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';

/// Shared layout of customer ledger screens.
///
/// Everything above the entries scrolls together with them (one
/// CustomScrollView), and GAVE / GOT stay fixed at the bottom, so the
/// screen never overflows on small phones or with large system fonts.
class PartyLedgerPage extends StatelessWidget {
  const PartyLedgerPage({
    super.key,
    required this.title,
    required this.name,
    required this.subtitle,
    required this.balance,
    required this.transactions,
    required this.onGave,
    required this.onGot,
    required this.onEditEntry,
    this.onExtendEntry,
    this.actions = const [],
    this.historyTrailing,
    this.loading = false,
  });

  /// The entries are still being read: show a spinner, not "No transactions".
  final bool loading;

  final String title;
  final String name;
  final String subtitle;
  final double balance;

  /// Newest first.
  final List<TransactionModel> transactions;
  final VoidCallback onGave;
  final VoidCallback onGot;
  final void Function(TransactionModel) onEditEntry;

  /// Extends the return date of an entry that has one.
  final void Function(TransactionModel)? onExtendEntry;
  final List<Widget> actions;
  final Widget? historyTrailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LedgerHeader(
              name: name,
              subtitle: subtitle,
              balance: balance,
            ),
          ),
          SliverToBoxAdapter(
            child: SectionTitle(
              transactions.isEmpty
                  ? 'Khata history'
                  : 'Khata history (${transactions.length})',
              trailing: historyTrailing,
            ),
          ),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (transactions.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions yet.',
                message:
                    'Tap GAVE or GOT below to record the first entry. Tap an '
                    'entry later to change its amount or note.',
              ),
            )
          else
            TransactionHistorySliver(
              transactions: transactions,
              currentBalance: balance,
              onTap: onEditEntry,
              onExtend: onExtendEntry,
            ),
        ],
      ),
      bottomNavigationBar: GaveGotBar(onGave: onGave, onGot: onGot),
    );
  }
}
