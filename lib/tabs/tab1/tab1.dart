import 'dart:async';

import 'package:digitalkhata/customerpagedaa.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/model/return_item.dart';
import 'package:digitalkhata/tabs/tab1/customer_details.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum _Filter {
  all('All'),
  toGet('To get'),
  toPay('To pay'),
  overdue('Overdue'),
  settled('Settled');

  const _Filter(this.label);
  final String label;
}

/// Khata tab: what is owed in total, then every customer with their balance
/// and status. On wide screens the customer's khata opens beside the list.
class Tab1 extends StatefulWidget {
  const Tab1({super.key});

  @override
  State<Tab1> createState() => _Tab1State();
}

class _Tab1State extends State<Tab1> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  List<Customermodel>? _seenCustomers;

  /// Customer id -> its most urgent open return.
  Map<int, ReturnUrgency> _urgency = const {};

  /// Customer open in the right-hand pane (wide screens only).
  int? _selectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadReturns() async {
    final items = await context.read<Dbprovider>().returnsDue();
    if (!mounted) return;
    final map = <int, ReturnUrgency>{};
    for (final item in items) {
      final u = item.urgency();
      final old = map[item.customerId];
      // overdue (index 0) beats due soon (1) beats later (2)
      if (old == null || u.index < old.index) map[item.customerId] = u;
    }
    setState(() => _urgency = map);
  }

  void _addCustomer() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddCustomerPage()),
    );
  }

  void _open(Customermodel c, bool wide) {
    if (wide) {
      setState(() => _selectedId = c.id);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => Customerdetails(item: c)),
      );
    }
  }

  bool _matches(Customermodel c) => switch (_filter) {
    _Filter.all => true,
    _Filter.toGet => c.currentBalance > 0,
    _Filter.toPay => c.currentBalance < 0,
    _Filter.overdue => _urgency[c.id] == ReturnUrgency.overdue,
    _Filter.settled => isSettled(c.currentBalance),
  };

  Widget _list(List<Customermodel> customers, bool wide) {
    final toReceive = context.select<Dbprovider, double>(
      (db) => db.customerToReceive,
    );
    final toPay = context.select<Dbprovider, double>((db) => db.customerToPay);
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final c in customers)
        if (_matches(c) &&
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
                            labelStyle: TextStyle(
                              color: _filter == filter
                                  ? Colors.white
                                  : AppColors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
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
                return FadeIn(
                  key: ValueKey(c.id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CustomerTile(
                      customer: c,
                      urgency: _urgency[c.id],
                      selected: wide && _selectedId == c.id,
                      onTap: () => _open(c, wide),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.select<Dbprovider, List<Customermodel>>(
      (db) => db.allCustomers,
    );
    // New list = something changed; the due status is read again.
    if (!identical(_seenCustomers, customers)) {
      _seenCustomers = customers;
      unawaited(_loadReturns());
    }

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

    final wide = isWideLayout(context);
    if (!wide) return _list(customers, false);

    final selected = customers.where((c) => c.id == _selectedId).firstOrNull;
    return Row(
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.4).clamp(320.0, 440.0),
          child: _list(customers, true),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'Select a customer',
                  message: 'Their khata opens here.',
                )
              : Customerdetails(
                  key: ValueKey(selected.id),
                  item: selected,
                  onClosed: () => setState(() => _selectedId = null),
                ),
        ),
      ],
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.urgency,
    required this.selected,
    required this.onTap,
  });

  final Customermodel customer;
  final ReturnUrgency? urgency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = customer.currentBalance;
    final color = AppColors.forBalance(balance);

    final StatusChip chip;
    if (urgency == ReturnUrgency.overdue) {
      chip = const StatusChip(
        'Overdue',
        color: AppColors.payable,
        icon: Icons.error_outline_rounded,
      );
    } else if (urgency == ReturnUrgency.dueSoon) {
      chip = const StatusChip(
        'Due soon',
        color: AppColors.dueSoon,
        icon: Icons.schedule_rounded,
      );
    } else {
      chip = StatusChip(balanceLabel(balance), color: color);
    }

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: selected ? AppColors.navy : AppColors.border,
      color: selected ? AppColors.navy.withValues(alpha: 0.04) : Colors.white,
      child: Row(
        children: [
          AppAvatar(name: customer.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (customer.phoneNo.isNotEmpty)
                  Text(
                    customer.phoneNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 136),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(balance.abs(), color: color, size: 15.5),
                const SizedBox(height: 4),
                chip,
              ],
            ),
          ),
        ],
      ),
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
    return AppCard(
      padding: const EdgeInsets.all(14),
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
          AmountText(amount, color: color, size: 21, align: Alignment.centerLeft),
        ],
      ),
    );
  }
}
