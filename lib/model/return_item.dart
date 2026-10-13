import 'package:digitalkhata/services/payment_reminder_service.dart';

enum ReturnUrgency { overdue, dueSoon, later }

/// One entry that still has money owed and a return date, for the dashboard
/// and the Overdue filter. Read-only view of existing data.
class ReturnItem {
  const ReturnItem({
    required this.transactionId,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.type,
    required this.dueDate,
    required this.dueMinute,
  });

  final int transactionId;
  final int customerId;
  final String customerName;
  final double amount;

  /// 'Gave' (they owe you) or 'Got' (you owe them).
  final String type;
  final DateTime dueDate;
  final int? dueMinute;

  bool get isToGet => type == 'Gave';

  DateTime get deadline => returnDeadline(dueDate, dueMinute);

  ReturnUrgency urgency([DateTime? now]) {
    final at = now ?? DateTime.now();
    if (isReturnDateOverdue(
      dueDate: dueDate,
      dueDayMinutes: dueMinute,
      now: at,
    )) {
      return ReturnUrgency.overdue;
    }
    return deadline.difference(at).inHours <= 72
        ? ReturnUrgency.dueSoon
        : ReturnUrgency.later;
  }

  String label([DateTime? now]) => describeReturnDate(
    dueDate: dueDate,
    dueDayMinutes: dueMinute,
    now: now ?? DateTime.now(),
  );
}
