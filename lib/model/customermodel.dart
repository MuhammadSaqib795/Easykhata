import 'package:digitalkhata/db/dbhelper.dart';

final class Customermodel {
  final int? id;
  final String name;
  final String? img;
  final String phoneNo;
  final String? address;
  final double totalAmount;
  final double currentBalance;
  final String desp;
  final DateTime creationTime;

  Customermodel({
    this.id,
    required this.name,
    required this.desp,
    required this.phoneNo,
    this.address,
    this.img,
    this.currentBalance = 0.0,
    this.totalAmount = 0.0,
    required this.creationTime,
  });
  Customermodel copyWith({
    int? id,
    String? name,
    String? phoneNo,
    String? desp,
    String? img,
    String? address,
    DateTime? creationTime,
    double? currentBalance,
    double? totalAmount,
  }) {
    return Customermodel(
      name: name ?? this.name,
      desp: desp ?? this.desp,
      phoneNo: phoneNo ?? this.phoneNo,
      creationTime: creationTime ?? this.creationTime,
      address: address ?? this.address,
      id: id ?? this.id,
      img: img ?? this.img,
      totalAmount: totalAmount ?? this.totalAmount,
      currentBalance: currentBalance ?? this.currentBalance,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      Dbhelper.colCustomerId: id,
      Dbhelper.colCustomerName: name,
      Dbhelper.colCustomerdesp: desp,
      Dbhelper.colCustomerphoneNo: phoneNo,
      Dbhelper.colCustomerAddress: address,
      Dbhelper.colCustomerImg: img,
      Dbhelper.colCustomerTotalAmount: totalAmount,
      Dbhelper.colCustomerCreatedAt: creationTime.toIso8601String(),
      Dbhelper.colCustomerCurrentBalance: currentBalance,
    };
  }

  factory Customermodel.fromMap(Map<String, dynamic> map) {
    return Customermodel(
      id: map[Dbhelper.colCustomerId],
      name: map[Dbhelper.colCustomerName] ?? "",
      desp: map[Dbhelper.colCustomerdesp] ?? "",
      phoneNo: map[Dbhelper.colCustomerphoneNo] ?? "",
      address: map[Dbhelper.colCustomerAddress] ?? "",
      img: map[Dbhelper.colCustomerImg] ?? "",
      totalAmount: (map[Dbhelper.colCustomerTotalAmount] ?? 0.0).toDouble(),
      creationTime: map[Dbhelper.colCustomerCreatedAt] != null
          ? DateTime.parse(map[Dbhelper.colCustomerCreatedAt])
          : DateTime.now(),
      currentBalance: (map[Dbhelper.colCustomerCurrentBalance] ?? 0.0)
          .toDouble(),
    );
  }
}
