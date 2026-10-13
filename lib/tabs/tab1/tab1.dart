import 'package:digitalkhata/customerpagedaa.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/tabs/tab1/customer_details.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _Filter {
  all('All'),
  toReceive('You will get'),
  toPay('You will pay'),
  settled('Settled');

  const _Filter(this.label);
  final String label;

  bool matches(double balance) => switch (this) {
    all => true,
    toReceive => balance > 0,
    toPay => balance < 0,
    settled => isSettled(balance),
  };
}

/// Khata tab: what is owed in total, then every customer with their balance.
/// Search and the filter chips narrow the list.
class Tab1 extends StatefulWidget {
  const Tab1({super.key});

  @override
  State<Tab1> createState() => _Tab1State();
}

class _Tab1State extends State<Tab1> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _addCustomer() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddCustomerPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (customers, toReceive, toPay) = context
        .select<Dbprovider, (List<Customermodel>, double, double)>(
          (db) => (db.allCustomers, db.customerToReceive, db.customerToPay),
        );

    if (customers.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'No customers yet',
        message:
            'Add your first customer to start their khata and keep track of '
            'what they owe you.',
        actionLabel: 'Add customer',
        onAction: _addCustomer,
      );
    }

    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final c in customers)
        if (_filter.matches(c.currentBalance) &&
            (query.isEmpty ||
                c.name.toLowerCase().contains(query) ||
                c.phoneNo.contains(query)))
          c,
    ];

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _TotalCard(
                        label: 'You will get',
                        amount: toReceive,
                        color: AppColors.receivable,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TotalCard(
                        label: 'You will pay',
                        amount: toPay,
                        color: AppColors.payable,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search name or phone',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(_search.clear),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                  child: Text(
                    shown.length == customers.length
                        ? '${customers.length} '
                              '${customers.length == 1 ? 'customer' : 'customers'}'
                        : '${shown.length} of ${customers.length} customers',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shown.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No customer found',
              message: 'Try another name, phone number or filter.',
            ),
          )
        else
          SliverPadding(
            // Bottom space so the last customer is not hidden by the button.
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final c = shown[i];
                return PartyTile(
                  key: ValueKey(c.id),
                  name: c.name,
                  subtitle: c.phoneNo,
                  amount: formatMoney(c.currentBalance.abs()),
                  amountLabel: balanceLabel(c.currentBalance),
                  amountColor: AppColors.forBalance(c.currentBalance),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => Customerdetails(item: c)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(amount),
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
