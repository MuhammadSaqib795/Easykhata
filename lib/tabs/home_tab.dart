import 'package:digitalkhata/customerpagedaa.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/model/return_item.dart';
import 'package:digitalkhata/tabs/tab1/customer_details.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/customer_picker.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class _HomeData {
  const _HomeData({
    required this.todayTotal,
    required this.todayCount,
    required this.returns,
  });

  final double todayTotal;
  final int todayCount;
  final List<ReturnItem> returns;
}

/// Home dashboard: today at a glance, quick actions, and the returns that
/// are overdue or coming up.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.refreshToken,
    required this.onNewSale,
  });

  /// Changes whenever the tab is opened, so the figures are read again.
  final int refreshToken;
  final VoidCallback onNewSale;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Future<_HomeData>? _data;
  List<Customermodel>? _seenCustomers;

  Future<_HomeData> _load() async {
    final provider = context.read<Dbprovider>();
    final sales = await provider.salesHistory();
    final today = [
      for (final Sale s in sales)
        if (DateUtils.isSameDay(s.time, DateTime.now())) s,
    ];
    return _HomeData(
      todayTotal: today.fold<double>(0, (sum, s) => sum + s.total),
      todayCount: today.length,
      returns: await provider.returnsDue(),
    );
  }

  @override
  void didUpdateWidget(HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _data = _load();
  }

  Future<void> _addEntry() async {
    final customer = await pickCustomer(context, title: 'Add entry for…');
    if (customer == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Customerdetails(item: customer)),
    );
  }

  void _openReturn(ReturnItem item, List<Customermodel> customers) {
    final customer = customers.where((c) => c.id == item.customerId).firstOrNull;
    if (customer == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Customerdetails(
          item: customer,
          extendTransactionId: item.transactionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<Dbprovider>();
    // A changed customer list means a balance or entry changed.
    if (_data == null || !identical(_seenCustomers, db.allCustomers)) {
      _seenCustomers = db.allCustomers;
      _data = _load();
    }
    final name = (FirebaseAuth.instance.currentUser?.displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first;

    return FutureBuilder<_HomeData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(onRetry: () => setState(() => _data = _load()));
        }
        final data = snapshot.data;
        if (data == null) return const LoadingView();

        final overdue = data.returns
            .where((r) => r.urgency() == ReturnUrgency.overdue)
            .length;
        final upcoming = data.returns.take(5).toList();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  name.isEmpty ? 'Welcome back' : 'Hello, $name',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Here is your shop today.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: "Today's sales",
                        amount: data.todayTotal,
                        note:
                            '${data.todayCount} '
                            '${data.todayCount == 1 ? 'sale' : 'sales'}',
                        color: AppColors.navy,
                        icon: Icons.point_of_sale_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Overdue returns',
                        count: overdue,
                        note: overdue == 0 ? 'All on time' : 'Needs follow-up',
                        color: overdue == 0
                            ? AppColors.receivable
                            : AppColors.payable,
                        icon: Icons.event_busy_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'You will get',
                        amount: db.customerToReceive,
                        note: 'From customers',
                        color: AppColors.receivable,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'You will pay',
                        amount: db.customerToPay,
                        note: 'To customers',
                        color: AppColors.payable,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
                const SectionHeader('Quick actions'),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.add_shopping_cart_rounded,
                        label: 'New sale',
                        onTap: widget.onNewSale,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Add customer',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddCustomerPage(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickAction(
                        icon: Icons.edit_note_rounded,
                        label: 'Add entry',
                        onTap: _addEntry,
                      ),
                    ),
                  ],
                ),
                const SectionHeader('Upcoming returns'),
                if (upcoming.isEmpty)
                  const AppCard(
                    child: Row(
                      children: [
                        Icon(Icons.event_available_rounded, color: AppColors.muted),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No return dates to follow up. Set one on a '
                            'khata entry to get a reminder.',
                            style: TextStyle(color: AppColors.muted, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < upcoming.length; i++)
                    FadeIn(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReturnTile(
                          item: upcoming[i],
                          onTap: () => _openReturn(upcoming[i], db.allCustomers),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.note,
    required this.color,
    required this.icon,
    this.amount,
    this.count,
  });

  final String label;
  final String note;
  final Color color;
  final IconData icon;
  final double? amount;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
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
          const SizedBox(height: 12),
          if (amount != null)
            AmountText(amount!, color: color, size: 22, align: Alignment.centerLeft)
          else
            Text(
              '${count ?? 0}',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: AppColors.navy, size: 26),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ReturnTile extends StatelessWidget {
  const _ReturnTile({required this.item, required this.onTap});

  final ReturnItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgency = item.urgency();
    final statusColor = switch (urgency) {
      ReturnUrgency.overdue => AppColors.payable,
      ReturnUrgency.dueSoon => AppColors.dueSoon,
      ReturnUrgency.later => AppColors.muted,
    };
    final amountColor = item.isToGet ? AppColors.receivable : AppColors.payable;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          AppAvatar(name: item.customerName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                StatusChip(item.label(), color: statusColor),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(item.amount, color: amountColor, size: 15),
                Text(
                  item.isToGet ? 'You will get' : 'You will pay',
                  style: TextStyle(color: amountColor, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
