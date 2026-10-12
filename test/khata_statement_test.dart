import 'package:digitalkhata/model/transactionmodel.dart';
import 'package:digitalkhata/services/khata_pdf_service.dart';
import 'package:digitalkhata/utills/running_balance.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionModel _tx(String type, double amount, int day) => TransactionModel(
  customerId: 1,
  amount: amount,
  type: type,
  desp: '',
  dateTime: DateTime(2026, 10, day),
);

void main() {
  group('buildLedgerLines', () {
    test('rebuilds running balances from the current balance', () {
      // Oldest -> newest: Gave 1000, Got 400, Gave 250  => balance 850.
      final newestFirst = [
        _tx('Gave', 250, 3),
        _tx('Got', 400, 2),
        _tx('Gave', 1000, 1),
      ];
      final lines = buildLedgerLines(newestFirst, 850);

      expect(lines.map((l) => l.after), [850, 600, 1000]);
      expect(lines.map((l) => l.before), [600, 1000, 0]);
    });

    test('no entries gives no lines', () {
      expect(buildLedgerLines(const [], 0), isEmpty);
    });

    test('payable balance stays negative', () {
      final lines = buildLedgerLines([_tx('Got', 300, 1)], -300);
      expect(lines.single.before, 0);
      expect(lines.single.after, -300);
    });
  });

  group('KhataPdfService.fileNameFor', () {
    final date = DateTime(2026, 10, 7);

    test('uses the Easy Khata pattern', () {
      expect(
        KhataPdfService.fileNameFor('Ali Khan', date),
        'EasyKhata_Ali_Khan_2026-10-07.pdf',
      );
    });

    test('removes characters that are invalid in file names', () {
      expect(
        KhataPdfService.fileNameFor('A/B:C*D?"E<F>G|H', date),
        'EasyKhata_ABCDEFGH_2026-10-07.pdf',
      );
    });

    test('falls back when nothing usable is left', () {
      expect(
        KhataPdfService.fileNameFor('  ///  ', date),
        'EasyKhata_Customer_2026-10-07.pdf',
      );
    });
  });
}
