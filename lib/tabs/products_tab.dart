import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/empty_state.dart';
import 'package:digitalkhata/widgets/product_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Products tab: the list of things you sell, with price. Tap to edit.
/// The add button is the screen's floating action button (see Mainscreen).
class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
        onAction: () => showProductEditor(context),
      );
    }

    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in products)
        if (query.isEmpty || p.name.toLowerCase().contains(query)) p,
    ];

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
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  // Space so the add button never hides the last product.
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final product = shown[i];
                    return FadeIn(
                      key: ValueKey(product.id),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                          onTap: () => showProductEditor(
                            context,
                            product: product,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.navy.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.inventory_2_outlined,
                                  color: AppColors.navy,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: AmountText(product.price, size: 16),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Product options',
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: AppColors.muted,
                                ),
                                onSelected: (value) => value == 'edit'
                                    ? showProductEditor(context, product: product)
                                    : confirmDeleteProduct(context, product),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
