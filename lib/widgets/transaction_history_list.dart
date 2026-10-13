import 'package:digitalkhata/model/transactionmodel.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/utills/running_balance.dart';
import 'package:flutter/material.dart';

/// Ledger-style history: every entry shows what was paid/received, why
/// (description) and how the running balance moved:
///
///     Previous balance  ->  +/- amount  ->  Balance after
///
/// Balance convention (same as the rest of the app):
///   Gave  = balance goes UP   (+)  -> they owe you more
///   Got   = balance goes DOWN (-)  -> they owe you less / you owe them
///   balance > 0 : you will receive,  balance < 0 : you will pay
class TransactionHistoryList extends StatelessWidget {
  const TransactionHistoryList({
    super.key,
    required this.transactions,
    required this.currentBalance,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 20),
  });

  /// Called when an entry is tapped (used to modify amount / description).
  final void Function(TransactionModel transaction)? onTap;

  /// Newest first.
  final List<TransactionModel> transactions;

  /// The party's present balance (balance after the newest entry).
  final double currentBalance;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final lines = buildLedgerLines(transactions, currentBalance);

    return ListView.separated(
      padding: padding,
      itemCount: transactions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final line = lines[i];
        return _HistoryTile(
          tx: line.transaction,
          before: line.before,
          after: line.after,
          onTap: onTap == null ? null : () => onTap!(line.transaction),
        );
      },
    );
  }
}

/// The same history as [TransactionHistoryList], as a sliver, so a whole
/// ledger screen scrolls as one page and never overflows.
class TransactionHistorySliver extends StatelessWidget {
  const TransactionHistorySliver({
    super.key,
    required this.transactions,
    required this.currentBalance,
    this.onTap,
    this.onExtend,
  });

  final List<TransactionModel> transactions;
  final double currentBalance;
  final void Function(TransactionModel transaction)? onTap;

  /// Called to move an entry's return date further out.
  final void Function(TransactionModel transaction)? onExtend;

  @override
  Widget build(BuildContext context) {
    final lines = buildLedgerLines(transactions, currentBalance);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverList.separated(
        itemCount: lines.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final line = lines[i];
          final tx = line.transaction;
          // The money is still owed in this entry's direction. Once the khata
          // is settled a past return date is history, not overdue.
          final outstanding = tx.type == 'Gave'
              ? currentBalance > 0
              : currentBalance < 0;
          final tile = _HistoryTile(
            tx: tx,
            before: line.before,
            after: line.after,
            onTap: onTap == null ? null : () => onTap!(tx),
            onExtend: onExtend == null || !outstanding
                ? null
                : () => onExtend!(tx),
          );
          // Entries are newest first: a header starts each new day.
          final newDay =
              i == 0 ||
              !DateUtils.isSameDay(
                lines[i - 1].transaction.dateTime,
                tx.dateTime,
              );
          if (!newDay) return tile;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(2, i == 0 ? 0 : 8, 2, 8),
                child: Text(
                  _dayLabel(tx.dateTime),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              tile,
            ],
          );
        },
      ),
    );
  }

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(day, now)) return 'Today';
    if (DateUtils.isSameDay(day, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return formatDate(day);
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.tx,
    required this.before,
    required this.after,
    this.onTap,
    this.onExtend,
  });

  final VoidCallback? onTap;

  /// Null when the return date cannot be extended (nothing is owed any more).
  final VoidCallback? onExtend;
  final TransactionModel tx;
  final double before;
  final double after;

  bool get _isGave => tx.type == 'Gave';

  @override
  Widget build(BuildContext context) {
    final color = _isGave ? AppColors.payable : AppColors.receivable;
    final desp = tx.desp.trim();
    final isOpening = desp.toLowerCase() == 'opening balance';
    final typeLabel = _isGave ? 'You Gave' : 'You Got';
    final sign = _isGave ? '+' : '−';

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOpening
                      ? Icons.flag_outlined
                      : (_isGave
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded),
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desp.isEmpty ? typeLabel : desp,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desp.isEmpty
                          ? formatDateTime(tx.dateTime)
                          : '$typeLabel  •  ${formatDateTime(tx.dateTime)}',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    if (tx.paymentDueDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.notifications_active_outlined,
                            size: 13,
                            color: AppColors.navy,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Payment due ${formatDate(tx.paymentDueDate!)}'
                              '${tx.paymentDueMinute == null ? '' : ' · ${TimeOfDay(hour: tx.paymentDueMinute! ~/ 60, minute: tx.paymentDueMinute! % 60).format(context)}'}',
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              Text(
                '$sign ${formatMoney(tx.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
          if (tx.paymentDueDate != null && onExtend != null)
            _ReturnDateStatus(tx: tx, onExtend: onExtend!),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEF0F3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _BalanceCell(label: 'Previous', value: before),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: const Color(0xFF94A3B8),
                ),
                Expanded(
                  child: _BalanceCell(
                    label: 'Balance after',
                    value: after,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

/// "Overdue by 3 days" / "Due tomorrow" with the action to extend the date.
class _ReturnDateStatus extends StatelessWidget {
  const _ReturnDateStatus({required this.tx, required this.onExtend});

  final TransactionModel tx;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final overdue = isReturnDateOverdue(
      dueDate: tx.paymentDueDate!,
      dueDayMinutes: tx.paymentDueMinute,
      now: now,
    );
    final color = overdue ? AppColors.payable : AppColors.navy;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: overdue ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.error_outline_rounded : Icons.schedule_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              describeReturnDate(
                dueDate: tx.paymentDueDate!,
                dueDayMinutes: tx.paymentDueMinute,
                now: now,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onExtend,
            style: TextButton.styleFrom(
              foregroundColor: color,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.update_rounded, size: 16),
            label: const Text(
              'Extend',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCell extends StatelessWidget {
  const _BalanceCell({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final double value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final color = value > 0
        ? AppColors.receivable
        : (value < 0 ? AppColors.payable : AppColors.settled);
    final note = value > 0
        ? 'you will get'
        : (value < 0 ? 'you will pay' : 'settled');

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatMoney(value.abs()),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: color,
            ),
          ),
        ),
        Text(note, style: TextStyle(fontSize: 10.5, color: color)),
      ],
    );
  }
}
