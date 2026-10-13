import 'package:digitalkhata/model/pos_models.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/app_widgets.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// What was just sold, kept for the success screen and the shared receipt.
class SaleReceipt {
  SaleReceipt({
    required this.lines,
    required this.onKhata,
    this.customerName,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final List<SaleLine> lines;
  final bool onKhata;
  final String? customerName;
  final DateTime time;

  double get total => lines.fold<double>(0, (sum, line) => sum + line.total);

  String get paidWith => onKhata
      ? 'On khata${customerName == null ? '' : ' · $customerName'}'
      : 'Cash';

  String asText() {
    final buffer = StringBuffer()
      ..writeln('${AppBrand.name} · Receipt')
      ..writeln(formatDateTime(time))
      ..writeln();
    for (final line in lines) {
      buffer.writeln(
        '${line.qty} × ${line.name}  ${formatMoney(line.total)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Total: ${formatMoney(total)}')
      ..write('Paid: $paidWith');
    return buffer.toString();
  }
}

/// Shown after a sale is saved: confirmation, receipt and what to do next.
class SaleSuccessScreen extends StatelessWidget {
  const SaleSuccessScreen({super.key, required this.receipt});

  final SaleReceipt receipt;

  Future<void> _share(BuildContext context) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: receipt.asText(), subject: 'Receipt'),
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, 'The receipt could not be shared.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sale saved')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.md),
              children: [
                const SizedBox(height: AppSpace.md),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.receivable.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 40,
                      color: AppColors.receivable,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Center(
                  child: AmountText(
                    receipt.total,
                    size: 32,
                    color: AppColors.ink,
                    align: Alignment.center,
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: StatusChip(
                    receipt.paidWith,
                    color: receipt.onKhata
                        ? AppColors.dueSoon
                        : AppColors.receivable,
                    icon: receipt.onKhata
                        ? Icons.menu_book_outlined
                        : Icons.payments_outlined,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                AppCard(
                  child: Column(
                    children: [
                      for (final line in receipt.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
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
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: AmountText(line.total, size: 14),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                OutlinedButton.icon(
                  onPressed: () => _share(context),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share receipt'),
                ),
                const SizedBox(height: AppSpace.sm + 4),
                PrimaryButton(
                  label: 'New sale',
                  icon: Icons.add_shopping_cart_rounded,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
