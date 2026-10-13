import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every sale made in the Sale tab, newest first, grouped by day with each
/// day's total.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late Future<List<Sale>> _sales;

  @override
  void initState() {
    super.initState();
    _sales = context.read<Dbprovider>().salesHistory();
  }

  void _reload() =>
      setState(() => _sales = context.read<Dbprovider>().salesHistory());

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(day, now)) return 'Today';
    if (DateUtils.isSameDay(day, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return formatDate(day);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales history')),
      body: FutureBuilder<List<Sale>>(
        future: _sales,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorView(onRetry: _reload);
          final sales = snapshot.data;
          if (sales == null) return const LoadingView();
          if (sales.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No sales yet',
              message: 'Sales you save in the Sale tab appear here.',
            );
          }

          // Newest first, so sales of one day are next to each other.
          final rows = <Object>[];
          for (var i = 0; i < sales.length; i++) {
            if (i == 0 || !DateUtils.isSameDay(sales[i - 1].time, sales[i].time)) {
              final total = sales
                  .where((s) => DateUtils.isSameDay(s.time, sales[i].time))
                  .fold<double>(0, (sum, s) => sum + s.total);
              rows.add((sales[i].time, total));
            }
            rows.add(sales[i]);
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  if (row is Sale) return _SaleCard(sale: row);
                  final (DateTime day, double total) = row as (DateTime, double);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dayLabel(day),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: AmountText(total, size: 15),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final color = sale.onKhata ? AppColors.dueSoon : AppColors.receivable;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        // Removes the lines ExpansionTile draws when it is open.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(
              sale.onKhata ? Icons.menu_book_outlined : Icons.payments_outlined,
              color: color,
              size: 20,
            ),
          ),
          title: Align(
            alignment: Alignment.centerLeft,
            child: AmountText(sale.total, size: 16, align: Alignment.centerLeft),
          ),
          subtitle: Text(
            '${sale.onKhata ? 'Khata · ${sale.customerName ?? 'Customer'}' : 'Cash'}'
            ' · ${formatDateTime(sale.time).split(', ').last}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final line in sale.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.qty} × ${line.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: AmountText(line.total, size: 14),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
