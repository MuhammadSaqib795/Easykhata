import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Point of sale: tap products to build a sale, then charge it as cash or
/// onto a customer's khata.
class PosTab extends StatefulWidget {
  const PosTab({super.key});

  @override
  State<PosTab> createState() => _PosTabState();
}

class _PosTabState extends State<PosTab> {
  final _search = TextEditingController();

  /// Product id -> quantity in the sale being built.
  final Map<int, int> _cart = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _changeQty(Product product, int change) {
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

  /// Add a product, or change [product]'s name and price.
  Future<void> _editProduct([Product? product]) async {
    final name = TextEditingController(text: product?.name ?? '');
    final price = TextEditingController(
      text: product == null ? '' : _plainNumber(product.price),
    );
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(product == null ? 'New product' : 'Edit product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    hintText: 'e.g. Sugar 1 kg',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: 'Rs. ',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.payable,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () async {
                final newName = name.text.trim();
                final newPrice = double.tryParse(price.text.trim()) ?? 0;
                if (newName.isEmpty || newPrice <= 0) {
                  setDialogState(
                    () => error = newName.isEmpty
                        ? 'Enter the product name.'
                        : 'Enter a price above zero.',
                  );
                  return;
                }
                final ok = await context.read<Dbprovider>().saveProduct(
                  id: product?.id,
                  name: newName,
                  price: newPrice,
                );
                if (!dialogContext.mounted) return;
                if (ok) {
                  Navigator.pop(dialogContext, true);
                } else {
                  setDialogState(
                    () => error = 'The product could not be saved. Try again.',
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // The controllers are not disposed here: the dialog still uses them
    // while its closing animation runs.
    if (saved == true && mounted) {
      showAppSnack(
        context,
        product == null ? 'Product added.' : 'Product updated.',
      );
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final id = product.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${product.name}?'),
        content: const Text(
          'It is removed from the product list. Sales already saved keep '
          'this item.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: AppColors.payable,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await context.read<Dbprovider>().deleteProduct(id);
    if (!mounted) return;
    if (ok) setState(() => _cart.remove(id));
    showAppSnack(
      context,
      ok ? 'Product deleted.' : 'The product could not be deleted.',
      error: !ok,
    );
  }

  Future<void> _checkout(List<SaleLine> lines) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CheckoutSheet(lines: lines),
    );
    if (saved != true || !mounted) return;
    setState(_cart.clear);
    showAppSnack(context, 'Sale saved.');
  }

  @override
  Widget build(BuildContext context) {
    final products = context.select<Dbprovider, List<Product>>(
      (db) => db.products,
    );

    if (products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        message:
            'Add the things you sell with their prices. Then a sale takes '
            'only a few taps.',
        actionLabel: 'Add product',
        onAction: _editProduct,
      );
    }

    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? products
        : [
            for (final p in products)
              if (p.name.toLowerCase().contains(query)) p,
          ];
    // Built from the current product list, so an edited price is used and a
    // deleted product drops out of the sale.
    final lines = [
      for (final p in products)
        if ((_cart[p.id] ?? 0) > 0)
          SaleLine(name: p.name, price: p.price, qty: _cart[p.id]!),
    ];
    final itemCount = lines.fold<int>(0, (sum, line) => sum + line.qty);
    final total = lines.fold<double>(0, (sum, line) => sum + line.total);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
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
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Add product',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  minimumSize: const Size(50, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _editProduct,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No product found',
                  message: 'Try another name, or add it as a new product.',
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final product = shown[i];
                    return _ProductTile(
                      key: ValueKey(product.id),
                      product: product,
                      qty: _cart[product.id] ?? 0,
                      onAdd: () => _changeQty(product, 1),
                      onRemove: () => _changeQty(product, -1),
                      onEdit: () => _editProduct(product),
                      onDelete: () => _deleteProduct(product),
                    );
                  },
                ),
        ),
        if (lines.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Clear sale',
                  onPressed: () => setState(_cart.clear),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatMoney(total),
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    backgroundColor: AppColors.receivable,
                  ),
                  onPressed: () => _checkout(lines),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Charge'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "250" or "12.5": a price as the user would type it.
String _plainNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// A product row: tap to add one, then use − and + to set the quantity.
class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final inSale = qty > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: inSale ? AppColors.receivable : AppColors.border,
                width: inSale ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(product.price),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (inSale) ...[
                  IconButton(
                    tooltip: 'Remove one',
                    onPressed: onRemove,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 26),
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Add one',
                  onPressed: onAdd,
                  color: AppColors.receivable,
                  icon: const Icon(Icons.add_circle_rounded, size: 28),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Product options',
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.muted,
                  ),
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Review of the sale and the choice between cash and a customer's khata.
class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.lines});

  final List<SaleLine> lines;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  bool _onKhata = false;
  Customermodel? _customer;
  bool _saving = false;
  String? _error;

  Future<void> _pickCustomer() async {
    final customers = context.read<Dbprovider>().allCustomers;
    final picked = await showDialog<Customermodel>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choose customer'),
        children: [
          if (customers.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'No customers yet. Add one in the Khata tab first.',
              ),
            ),
          for (final c in customers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, c),
              child: Row(
                children: [
                  AppAvatar(name: c.name, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
    final ok = await context.read<Dbprovider>().recordSale(
      widget.lines,
      customer: _onKhata ? _customer : null,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = 'The sale could not be saved. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.lines.fold<double>(0, (sum, l) => sum + l.total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Confirm sale',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final line in widget.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.qty} × ${line.name}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.ink),
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
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                formatMoney(total),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.payments_outlined),
                label: Text('Cash'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.menu_book_outlined),
                label: Text('On khata'),
              ),
            ],
            selected: {_onKhata},
            onSelectionChanged: _saving
                ? null
                : (selection) => setState(() {
                    _onKhata = selection.first;
                    _error = null;
                  }),
          ),
          if (_onKhata) ...[
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.border),
                ),
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(
                  _customer?.name ?? 'Choose customer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'The total is added to what they owe you.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _saving ? null : _pickCustomer,
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
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54),
              backgroundColor: AppColors.receivable,
            ),
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? 'Saving…'
                  : _onKhata
                  ? 'Save sale on khata'
                  : 'Save cash sale',
            ),
          ),
        ],
      ),
    );
  }
}
