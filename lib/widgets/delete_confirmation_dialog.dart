import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:flutter/material.dart';

/// Standard "are you sure?" dialog for destructive actions.
///
/// With [acknowledgement] the user must tick that statement before the
/// delete button is enabled (explicit permission).
Future<bool> showDeleteConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  required String confirmLabel,
  String? acknowledgement,
}) async {
  var agreed = acknowledgement == null;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.payable,
          size: 34,
        ),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(content, style: const TextStyle(height: 1.45)),
            if (acknowledgement != null) ...[
              const SizedBox(height: 14),
              Material(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  value: agreed,
                  onChanged: (v) => setState(() => agreed = v ?? false),
                  activeColor: AppColors.payable,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    acknowledgement,
                    style: const TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.payable,
              minimumSize: const Size(0, 44),
            ),
            onPressed: agreed
                ? () => Navigator.of(dialogContext).pop(true)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Explains why a khata with a remaining balance cannot be deleted.
Future<void> showKhataNotSettledDialog({
  required BuildContext context,
  required String name,
  required double balance,
}) {
  final willGet = balance > 0;
  final amount = formatMoney(balance.abs());
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(
        Icons.lock_outline_rounded,
        color: AppColors.navy,
        size: 34,
      ),
      title: const Text('Khata is not settled'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$name cannot be deleted while an amount is still remaining. '
            'This protects the balance and its full history.',
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.forBalance(balance).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              willGet ? 'You will get $amount' : 'You will pay $amount',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.forBalance(balance),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            willGet
                ? 'Record a GOT entry for $amount when you receive it. Once the '
                      'balance is zero, you can delete this khata.'
                : 'Record a GAVE entry for $amount when you pay it. Once the '
                      'balance is zero, you can delete this khata.',
            style: const TextStyle(height: 1.45, color: AppColors.muted),
          ),
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
