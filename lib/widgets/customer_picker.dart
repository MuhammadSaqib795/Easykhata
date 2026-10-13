import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Bottom sheet with a searchable list of customers. Null when dismissed.
Future<Customermodel?> pickCustomer(
  BuildContext context, {
  String title = 'Choose customer',
}) {
  return showModalBottomSheet<Customermodel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _CustomerPickerSheet(title: title),
  );
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet({required this.title});

  final String title;

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.read<Dbprovider>().allCustomers;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final c in customers)
        if (query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            c.phoneNo.contains(query))
          c,
    ];
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search name or phone',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'No customer found',
                        message:
                            'Add customers in the Khata tab, or try another name.',
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final c = shown[i];
                        return ListTile(
                          minTileHeight: 56,
                          leading: AppAvatar(name: c.name, size: 40),
                          title: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: c.phoneNo.isEmpty ? null : Text(c.phoneNo),
                          trailing: SizedBox(
                            width: 96,
                            child: AmountText(
                              c.currentBalance.abs(),
                              color: AppColors.forBalance(c.currentBalance),
                              size: 14,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Rs. 500 · You will get" for a customer's balance.
String balanceSummary(double balance) =>
    '${formatMoney(balance.abs())} · ${balanceLabel(balance)}';
