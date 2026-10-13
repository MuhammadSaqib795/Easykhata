import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// "250" or "12.5": a price as the user would type it.
String plainNumber(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// Add a product, or edit [product], in a bottom sheet. True when saved.
Future<bool> showProductEditor(BuildContext context, {Product? product}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _ProductForm(product: product),
  );
  if (saved == true && context.mounted) {
    showAppSnack(
      context,
      product == null ? 'Product added.' : 'Product updated.',
    );
  }
  return saved ?? false;
}

/// Asks, then removes [product]. Past sales keep their own item lines.
Future<bool> confirmDeleteProduct(BuildContext context, Product product) async {
  final id = product.id;
  if (id == null) return false;
  final provider = context.read<Dbprovider>();
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete ${product.name}?',
    message:
        'It is removed from your product list. Sales already saved keep this '
        'item.',
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (!confirmed) return false;
  final ok = await provider.deleteProduct(id);
  if (context.mounted) {
    showAppSnack(
      context,
      ok ? 'Product deleted.' : 'The product could not be deleted.',
      error: !ok,
    );
  }
  return ok;
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({this.product});

  final Product? product;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(
    text: widget.product == null ? '' : plainNumber(widget.product!.price),
  );
  String? _nameError;
  String? _priceError;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim()) ?? 0;
    setState(() {
      _nameError = name.isEmpty ? 'Enter the product name.' : null;
      _priceError = price <= 0 ? 'Enter a price above zero.' : null;
      _saveError = null;
    });
    if (name.isEmpty || price <= 0 || _saving) return;
    setState(() => _saving = true);
    final ok = await context.read<Dbprovider>().saveProduct(
      id: widget.product?.id,
      name: name,
      price: price,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _saveError = 'The product could not be saved. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            widget.product == null ? 'New product' : 'Edit product',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.product == null,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Product name',
              hintText: 'e.g. Sugar 1 kg',
              counterText: '',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
            ],
            decoration: InputDecoration(
              labelText: 'Price',
              prefixText: 'Rs. ',
              errorText: _priceError,
            ),
          ),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _saveError!,
                style: const TextStyle(color: AppColors.payable),
              ),
            ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: widget.product == null ? 'Add product' : 'Save changes',
            icon: Icons.check_rounded,
            busy: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
