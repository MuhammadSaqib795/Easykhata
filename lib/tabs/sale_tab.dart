import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/screens/sale_success_screen.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/customer_picker.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:digitalkhata/utills/format.dart';

/// Sale tab: tap products to build a sale, then charge it with the big
/// button pinned at the bottom (reachable with one hand).
class SaleTab extends StatefulWidget {
  const SaleTab({super.key, required this.onGoToProducts});

  /// Opens the Products tab when there is nothing to sell yet.
  final VoidCallback onGoToProducts;

  @override
  State<SaleTab> createState() => _SaleTabState();
}

class _SaleTabState extends State<SaleTab> {
  final _search = TextEditingController();

  /// Product id -> quantity in the sale being built.
  final Map<int, int> _cart = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _change(Product product, int change) {
    final id = product.id;
    if (id == null) return;
    setState(() {
      final qty = (_cart[id] ?? 0) + change;
      if (qty <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = qty;
      }
    });
  }

  Future<void> _charge(List<SaleLine> lines) async {
    final receipt = await showModalBottomSheet<SaleReceipt>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _PaymentSheet(lines: lines),
    );
    if (receipt == null || !mounted) return;
    setState(_cart.clear);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleSuccessScreen(receipt: receipt)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = context.select<Dbprovider, List<Product>>(
      (db) => db.products,
    );

    if (products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Nothing to sell yet',
        message: 'Add your products and prices first, then come back to sell.',
        actionLabel: 'Add products',
        onAction: widget.onGoToProducts,
      );
    }

    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in products)
        if (query.isEmpty || p.name.toLowerCase().contains(query)) p,
    ];
    // Built from the current product list, so an edited price is used and a
    // deleted product drops out of the sale.
    final lines = [
      for (final p in products)
        if ((_cart[p.id] ?? 0) > 0)
          SaleLine(name: p.name, price: p.price, qty: _cart[p.id]!),
    ];
    final itemCount = lines.fold<int>(0, (sum, l) => sum + l.qty);
    final total = lines.fold<double>(0, (sum, l) => sum + l.total);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search products',
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
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No product found',
                  message: 'Try another name.',
                )
              : GridView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 148,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final product = shown[i];
                    return _ProductCard(
                      key: ValueKey(product.id),
                      product: product,
                      qty: _cart[product.id] ?? 0,
                      onAdd: () => _change(product, 1),
                      onRemove: () => _change(product, -1),
                    );
                  },
                ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: lines.isEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.border)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(_cart.clear),
                            child: const Text('Clear'),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: AmountText(total, size: 22),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PrimaryButton(
                        label: 'Charge ${formatMoney(total)}',
                        icon: Icons.check_rounded,
                        color: AppColors.receivable,
                        onPressed: () => _charge(lines),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// A product to tap. Once in the sale it shows a − quantity + stepper.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    super.key,
    required this.product,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final Product product;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final inSale = qty > 0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      onTap: onAdd,
      borderColor: inSale ? AppColors.receivable : AppColors.border,
      color: inSale ? const Color(0xFFF0FDF4) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          AmountText(
            product.price,
            size: 15,
            color: AppColors.muted,
            align: Alignment.centerLeft,
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: inSale
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Remove one',
                        onPressed: onRemove,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      Text(
                        '$qty',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add one',
                        color: AppColors.receivable,
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_circle_rounded, size: 28),
                      ),
                    ],
                  )
                : const Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(
                      'Tap to add',
                      color: AppColors.navy,
                      icon: Icons.add_rounded,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Payment choice: cash, or onto a customer's khata. Saves the sale and
/// returns its receipt.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.lines});

  final List<SaleLine> lines;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  bool _onKhata = false;
  Customermodel? _customer;
  bool _saving = false;
  String? _error;

  Future<void> _chooseCustomer() async {
    final picked = await pickCustomer(context);
    if (picked != null && mounted) {
      setState(() {
        _customer = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_onKhata && _customer == null) {
      setState(() => _error = 'Choose the customer for this khata sale.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final customer = _onKhata ? _customer : null;
    final ok = await context.read<Dbprovider>().recordSale(
      widget.lines,
      customer: customer,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(
        context,
        SaleReceipt(
          lines: widget.lines,
          onKhata: customer != null,
          customerName: customer?.name,
        ),
      );
    } else {
      setState(() {
        _saving = false;
        _error = 'The sale could not be saved. Please try again.';
      });
    }
  }

  Widget _option({
    required bool khata,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _onKhata == khata;
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(14),
        borderColor: selected ? AppColors.navy : AppColors.border,
        color: selected ? AppColors.navy.withValues(alpha: 0.05) : Colors.white,
        onTap: _saving
            ? null
            : () => setState(() {
                _onKhata = khata;
                _error = null;
              }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.navy),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.lines.fold<double>(0, (sum, l) => sum + l.total);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'How is it paid?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(child: AmountText(total, size: 22)),
            ],
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _option(
                  khata: false,
                  icon: Icons.payments_outlined,
                  title: 'Cash',
                  subtitle: 'Paid now',
                ),
                const SizedBox(width: 12),
                _option(
                  khata: true,
                  icon: Icons.menu_book_outlined,
                  title: 'Khata',
                  subtitle: 'Pay later',
                ),
              ],
            ),
          ),
          if (_onKhata) ...[
            const SizedBox(height: 12),
            AppCard(
              onTap: _saving ? null : _chooseCustomer,
              child: Row(
                children: [
                  const Icon(Icons.person_outline_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _customer?.name ?? 'Choose customer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'The total is added to what they owe you.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.payable,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: _onKhata ? 'Save sale on khata' : 'Save cash sale',
            icon: Icons.check_rounded,
            color: AppColors.receivable,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
