import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Every sale made in the POS tab, newest first, with today's total on top.
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late final Future<List<Sale>> _sales;

  @override
  void initState() {
    super.initState();
    _sales = context.read<Dbprovider>().salesHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales history')),
      body: FutureBuilder<List<Sale>>(
        future: _sales,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Sales could not be loaded',
              message: 'Go back and open this screen again.',
            );
          }
          final sales = snapshot.data;
          if (sales == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (sales.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No sales yet',
              message: 'Sales you save in the POS tab appear here.',
            );
          }

          final today = [
            for (final sale in sales)
              if (DateUtils.isSameDay(sale.time, DateTime.now())) sale,
          ];
          final todayTotal = today.fold<double>(0, (sum, s) => sum + s.total);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: sales.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today · ${today.length} '
                        '${today.length == 1 ? 'sale' : 'sales'}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(todayTotal),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _SaleCard(sale: sales[i - 1]);
            },
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
    final color = sale.onKhata ? AppColors.accent : AppColors.receivable;
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
              sale.onKhata
                  ? Icons.menu_book_outlined
                  : Icons.payments_outlined,
              color: color,
              size: 20,
            ),
          ),
          title: Text(
            formatMoney(sale.total),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          subtitle: Text(
            '${sale.onKhata ? 'Khata · ${sale.customerName ?? 'Customer'}' : 'Cash'}'
            '\n${formatDateTime(sale.time)}',
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
                    Text(
                      formatMoney(line.total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
