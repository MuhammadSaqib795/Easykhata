import 'package:digitalkhata/db/dbhelper.dart';

class TransactionModel {
  final int? id;
  final int? customerId;
  final double amount;
  final String desp;
  final String type;
  final DateTime dateTime;
  final DateTime? paymentDueDate;
  final int? paymentDueMinute;
  String get info => desp;

  TransactionModel({
    this.id,
    this.customerId,
    required this.amount,
    required this.dateTime,
    required this.desp,
    required this.type,
    this.paymentDueDate,
    this.paymentDueMinute,
  });

  TransactionModel copyWith({
    int? id,
    int? customerId,
    double? amount,
    String? desp,
    String? type,
    DateTime? dateTime,
    DateTime? paymentDueDate,
    int? paymentDueMinute,
  }) {
    return TransactionModel(
      customerId: customerId ?? this.customerId,
      amount: amount ?? this.amount,
      dateTime: dateTime ?? this.dateTime,
      paymentDueDate: paymentDueDate ?? this.paymentDueDate,
      paymentDueMinute: paymentDueMinute ?? this.paymentDueMinute,
      desp: desp ?? this.desp,
      type: type ?? this.type,
      id: id ?? this.id,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      Dbhelper.colTransId: id,
      Dbhelper.colTranCusId: customerId,
      Dbhelper.colAmount: amount,
      Dbhelper.colTranTime: dateTime.toIso8601String(),
      Dbhelper.colTranInfo: desp,
      Dbhelper.colTrantype: type,
      Dbhelper.colTranPaymentDueAt: paymentDueDate == null
          ? null
          : DateTime(
              paymentDueDate!.year,
              paymentDueDate!.month,
              paymentDueDate!.day,
            ).toIso8601String(),
      Dbhelper.colTranPaymentDueMinute: paymentDueDate == null
          ? null
          : paymentDueMinute,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      customerId: map[Dbhelper.colTranCusId] as int?,
      amount: (map[Dbhelper.colAmount] as num?)?.toDouble() ?? 0.0,
      dateTime: map[Dbhelper.colTranTime] != null
          ? DateTime.parse(map[Dbhelper.colTranTime])
          : DateTime.now(),
      desp: map[Dbhelper.colTranInfo] ?? "",
      type: map[Dbhelper.colTrantype] ?? "",
      id: map[Dbhelper.colTransId] as int?,
      paymentDueDate: map[Dbhelper.colTranPaymentDueAt] == null
          ? null
          : DateTime.parse(map[Dbhelper.colTranPaymentDueAt] as String),
      paymentDueMinute: (map[Dbhelper.colTranPaymentDueMinute] as num?)
          ?.toInt(),
    );
  }
}
