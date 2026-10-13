import 'package:digitalkhata/db/dbhelper.dart';

/// Something the shop sells, with its usual price.
class Product {
  const Product({this.id, required this.name, required this.price});

  final int? id;
  final String name;
  final double price;

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map[Dbhelper.colProductId] as int?,
    name: map[Dbhelper.colProductName] as String? ?? '',
    price: (map[Dbhelper.colProductPrice] as num?)?.toDouble() ?? 0,
  );
}

/// One line of a sale: the item as it was sold, at the price of that moment.
class SaleLine {
  const SaleLine({required this.name, required this.price, required this.qty});

  final String name;
  final double price;
  final int qty;

  double get total => price * qty;

  factory SaleLine.fromMap(Map<String, Object?> map) => SaleLine(
    name: map[Dbhelper.colSaleItemName] as String? ?? '',
    price: (map[Dbhelper.colSaleItemPrice] as num?)?.toDouble() ?? 0,
    qty: (map[Dbhelper.colSaleItemQty] as num?)?.toInt() ?? 0,
  );
}

/// A finished sale, paid in cash or written onto a customer's khata.
class Sale {
  const Sale({
    required this.id,
    required this.time,
    required this.total,
    required this.onKhata,
    required this.customerName,
    required this.lines,
  });

  static const paymentCash = 'Cash';
  static const paymentKhata = 'Khata';

  final int id;
  final DateTime time;
  final double total;
  final bool onKhata;
  final String? customerName;
  final List<SaleLine> lines;
}
