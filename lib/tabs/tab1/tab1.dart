import 'package:digitalkhata/customerpagedaa.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/tabs/tab1/customer_details.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/dbprovider.dart';

class Tab1 extends StatelessWidget {
  const Tab1({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.select<Dbprovider, List<Customermodel>>(
      (db) => db.allCustomers,
    );

    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline_rounded,
        title: "No customers yet.",
        message:
            "No customers have been added yet. Add your first customer to start their khata.",
        actionLabel: "Add Customer",
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddCustomerPage()),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 460),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF0F5F4)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.045),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.people_alt_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Customer directory',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'People and their current balances',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutBack,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Container(
                        key: ValueKey(items.length),
                        constraints: const BoxConstraints(minWidth: 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${items.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final c = items[i - 1];
        return TweenAnimationBuilder<double>(
          key: ValueKey(c.id),
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (i.clamp(0, 6) * 45)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - value)),
              child: child,
            ),
          ),
          child: PartyTile(
            name: c.name,
            subtitle: c.phoneNo,
            amount: formatMoney(c.currentBalance.abs()),
            amountLabel: balanceLabel(c.currentBalance),
            amountColor: AppColors.forBalance(c.currentBalance),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => Customerdetails(item: c)),
            ),
          ),
        );
      },
    );
  }
}
