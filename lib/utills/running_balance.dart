import 'package:digitalkhata/model/transactionmodel.dart';

/// One ledger line with the balance before and after it.
class LedgerLine {
  const LedgerLine({
    required this.transaction,
    required this.before,
    required this.after,
  });

  final TransactionModel transaction;
  final double before;
  final double after;

  bool get isGave => transaction.type == 'Gave';
}

/// Balance convention used throughout the app:
///   Gave = balance goes UP   (+) -> they owe you more
///   Got  = balance goes DOWN (-) -> they owe you less / you owe them
///   balance > 0 : you will receive,  balance < 0 : you will pay
double ledgerDelta(TransactionModel t) =>
    t.type == 'Gave' ? t.amount : -t.amount;

double roundMoney(double v) => (v * 100).roundToDouble() / 100;

/// Rebuilds each entry's previous/after balance by walking from the newest
/// entry back in time, starting at the party's present [currentBalance].
///
/// [newestFirst] must be ordered newest first (as the app loads them); the
/// result keeps that order.
List<LedgerLine> buildLedgerLines(
  List<TransactionModel> newestFirst,
  double currentBalance,
) {
  final lines = <LedgerLine>[];
  var after = roundMoney(currentBalance);
  for (final t in newestFirst) {
    final before = roundMoney(after - ledgerDelta(t));
    lines.add(
      LedgerLine(
        transaction: t,
        before: before,
        after: roundMoney(before + ledgerDelta(t)),
      ),
    );
    after = before;
  }
  return lines;
}
