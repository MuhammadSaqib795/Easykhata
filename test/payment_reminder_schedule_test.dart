import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/model/transactionmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateReminderOccurrences', () {
    final settings = PaymentReminderSettings.defaults;

    test('schedules three previous-day and one due-day reminder', () {
      final occurrences = calculateReminderOccurrences(
        dueDate: DateTime(2026, 6, 16),
        settings: settings,
        now: DateTime(2026, 6, 14, 12),
      );

      expect(occurrences.map((item) => item.slot), [0, 1, 2, 3]);
      expect(occurrences.map((item) => item.dateTime), [
        DateTime(2026, 6, 15, 9),
        DateTime(2026, 6, 15, 13),
        DateTime(2026, 6, 15, 18),
        DateTime(2026, 6, 16, 9),
      ]);
    });

    group('isReminderTimeInFuture', () {
      test('accepts a future alert time today', () {
        expect(
          isReminderTimeInFuture(
            dueDate: DateTime(2026, 6, 16),
            dueDayMinutes: 17 * 60 + 30,
            now: DateTime(2026, 6, 16, 17, 29),
          ),
          isTrue,
        );
      });

      test('rejects an alert time that has passed today', () {
        expect(
          isReminderTimeInFuture(
            dueDate: DateTime(2026, 6, 16),
            dueDayMinutes: 17 * 60 + 30,
            now: DateTime(2026, 6, 16, 17, 30),
          ),
          isFalse,
        );
      });

      test('rejects a return date that is in the past', () {
        expect(
          isReminderTimeInFuture(
            dueDate: DateTime(2026, 6, 15),
            dueDayMinutes: 17 * 60 + 30,
            now: DateTime(2026, 6, 16, 8),
          ),
          isFalse,
        );
      });
    });

    test('does not schedule reminders in the past', () {
      final occurrences = calculateReminderOccurrences(
        dueDate: DateTime(2026, 6, 16),
        settings: settings,
        now: DateTime(2026, 6, 15, 14),
      );

      expect(occurrences.map((item) => item.slot), [2, 3]);
      expect(occurrences.map((item) => item.dateTime), [
        DateTime(2026, 6, 15, 18),
        DateTime(2026, 6, 16, 9),
      ]);
    });

    test('does not schedule a due-date reminder after its selected time', () {
      final occurrences = calculateReminderOccurrences(
        dueDate: DateTime(2026, 6, 16),
        settings: settings,
        now: DateTime(2026, 6, 16, 9),
      );

      expect(occurrences, isEmpty);
    });

    test('same-day return only schedules the selected due-time alert', () {
      final occurrences = calculateReminderOccurrences(
        dueDate: DateTime(2026, 6, 16),
        settings: settings,
        now: DateTime(2026, 6, 16, 8),
        dueDayMinutes: 17 * 60 + 30,
      );

      expect(occurrences.map((item) => item.slot), [3]);
      expect(occurrences.single.dateTime, DateTime(2026, 6, 16, 17, 30));
    });

    test(
      'same-day return skips the selected alert when its time has passed',
      () {
        final occurrences = calculateReminderOccurrences(
          dueDate: DateTime(2026, 6, 16),
          settings: settings,
          now: DateTime(2026, 6, 16, 17, 31),
          dueDayMinutes: 17 * 60 + 30,
        );

        expect(occurrences, isEmpty);
      },
    );

    test('uses the calendar day before a month boundary', () {
      final occurrences = calculateReminderOccurrences(
        dueDate: DateTime(2026, 7, 1),
        settings: settings,
        now: DateTime(2026, 6, 29, 12),
      );

      expect(occurrences[0].dateTime, DateTime(2026, 6, 30, 9));
      expect(occurrences[3].dateTime, DateTime(2026, 7, 1, 9));
    });
  });

  group('return date status', () {
    final due = DateTime(2026, 6, 16);
    const alertAt = 17 * 60 + 30;

    String describe(DateTime now, {int? minutes = alertAt}) =>
        describeReturnDate(dueDate: due, dueDayMinutes: minutes, now: now);

    test('counts the days left before the return date', () {
      expect(describe(DateTime(2026, 6, 11, 23)), 'Due in 5 days');
      expect(describe(DateTime(2026, 6, 15, 23, 59)), 'Due tomorrow');
      expect(describe(DateTime(2026, 6, 16, 17, 29)), 'Due today');
    });

    test('is overdue from the alert time onwards', () {
      expect(describe(DateTime(2026, 6, 16, 17, 30)), 'Overdue today');
      expect(describe(DateTime(2026, 6, 17, 0, 1)), 'Overdue by 1 day');
      expect(describe(DateTime(2026, 6, 19, 9)), 'Overdue by 3 days');
    });

    test('without an alert time the whole due day is allowed', () {
      expect(describe(DateTime(2026, 6, 16, 23, 59), minutes: null), 'Due today');
      expect(
        isReturnDateOverdue(
          dueDate: due,
          dueDayMinutes: null,
          now: DateTime(2026, 6, 17),
        ),
        isTrue,
      );
    });

    test('extending an overdue return schedules reminders again', () {
      final now = DateTime(2026, 6, 19, 9);
      expect(
        calculateReminderOccurrences(
          dueDate: due,
          settings: PaymentReminderSettings.defaults,
          now: now,
          dueDayMinutes: alertAt,
        ),
        isEmpty,
      );

      final extended = calculateReminderOccurrences(
        dueDate: DateTime(2026, 6, 22),
        settings: PaymentReminderSettings.defaults,
        now: now,
        dueDayMinutes: alertAt,
      );
      expect(extended.map((item) => item.slot), [0, 1, 2, 3]);
      expect(extended.last.dateTime, DateTime(2026, 6, 22, 17, 30));
    });
  });

  group('PaymentReminderSettings', () {
    test('rejects duplicate day-before times', () {
      expect(
        () => PaymentReminderSettings.fromJson({
          'dayBeforeTimes': [
            {'hour': 9, 'minute': 0},
            {'hour': 9, 'minute': 0},
            {'hour': 18, 'minute': 0},
          ],
          'dueDayTime': {'hour': 9, 'minute': 0},
        }),
        throwsArgumentError,
      );
    });
  });

  test('transaction preserves its custom return alert time', () {
    final transaction = TransactionModel(
      amount: 125,
      dateTime: DateTime(2026, 6, 15),
      desp: 'Opening Balance',
      type: 'Gave',
      paymentDueDate: DateTime(2026, 6, 16),
      paymentDueMinute: 17 * 60 + 30,
    );

    final restored = TransactionModel.fromMap(transaction.toMap());

    expect(restored.paymentDueDate, DateTime(2026, 6, 16));
    expect(restored.paymentDueMinute, 17 * 60 + 30);
  });
}
