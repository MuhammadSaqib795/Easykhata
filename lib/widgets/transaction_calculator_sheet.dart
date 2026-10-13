import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/widgets/return_date_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_simple_calculator/flutter_simple_calculator.dart';

/// Add a new GAVE / GOT entry, or (with [isEdit]) change an existing one.
///
/// Layout never overflows: the amount, date, note and calculator scroll
/// inside the sheet, and the save button always stays visible. The note is
/// free text written by the user.
Future<void> showTransactionCalculatorSheet({
  required BuildContext context,
  required String type,
  required String subject,
  required Future<void> Function(
    double amount,
    String description,
    DateTime date,
    DateTime? paymentDueDate,
    int? paymentDueMinute,
  )
  onSave,
  Color? accentColor,
  IconData? icon,
  bool isEdit = false,
  double? initialAmount,
  String? initialDescription,
  DateTime? initialPaymentDueDate,
  int? initialPaymentDueMinute,
}) async {
  final isGave = type == 'Gave';
  final color =
      accentColor ?? (isGave ? AppColors.payable : AppColors.receivable);
  final typeIcon =
      icon ??
      (isGave ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
  final label = isGave ? 'GAVE' : 'GOT';
  final meaning = isGave
      ? 'Money or goods you gave this $subject'
      : 'Money you received from this $subject';

  double tempValue = initialAmount ?? 0.0;
  bool isSaving = false;
  var entryDate = DateTime.now();
  DateTime? paymentDueDate = initialPaymentDueDate;
  int? paymentDueMinute = initialPaymentDueMinute;
  final descController = TextEditingController(text: initialDescription ?? '');
  // The chosen alert time went by before saving; shown on the due-date row.
  var alertTimePassed = false;
  // The user refused notification access; shown on the due-date row because
  // a snack bar would be hidden behind this sheet.
  var notificationsOff = false;
  // Owned here (not inside the builder) so the note field keeps its focus,
  // and the keyboard stays open, while the sheet re-lays out.
  final descFocus = FocusNode();
  final descFieldKey = GlobalKey();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setModalState) {
          Future<void> submit() async {
            if (isSaving) return;
            if (tempValue <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter an amount before saving.'),
                ),
              );
              return;
            }
            // An entry opened for editing keeps a return date that is already
            // overdue; only a newly chosen date and time must be in the future.
            final dueDate = paymentDueDate;
            final dueUnchanged =
                DateUtils.isSameDay(dueDate, initialPaymentDueDate) &&
                paymentDueMinute == initialPaymentDueMinute;
            if (dueDate != null && !dueUnchanged) {
              final reminderSettings = await PaymentReminderService.instance
                  .loadSettings();
              final selectedMinutes =
                  paymentDueMinute ??
                  reminderSettings.dueDayTime.hour * 60 +
                      reminderSettings.dueDayTime.minute;
              if (!isReminderTimeInFuture(
                dueDate: dueDate,
                dueDayMinutes: selectedMinutes,
                now: DateTime.now(),
              )) {
                // Nothing is saved: the user picks a new time or removes it.
                if (!sheetContext.mounted) return;
                setModalState(() => alertTimePassed = true);
                await showPassedTimeWarning(sheetContext, nothingSaved: true);
                return;
              }
            }
            if (!sheetContext.mounted) return;
            setModalState(() => isSaving = true);
            try {
              await onSave(
                tempValue,
                descController.text.trim(),
                entryDate,
                paymentDueDate,
                paymentDueMinute,
              );
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            } finally {
              if (sheetContext.mounted) {
                setModalState(() => isSaving = false);
              }
            }
          }

          Future<void> pickDate() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate: entryDate,
              firstDate: DateTime(2000),
              lastDate: now,
              helpText: 'Entry date',
            );
            if (picked == null) return;
            setModalState(() {
              entryDate = DateUtils.isSameDay(picked, now)
                  ? now
                  : DateTime(
                      picked.year,
                      picked.month,
                      picked.day,
                      now.hour,
                      now.minute,
                    );
            });
          }

          Future<void> pickPaymentDueDate() async {
            final today = DateUtils.dateOnly(DateTime.now());
            final initial =
                paymentDueDate != null && !paymentDueDate!.isBefore(today)
                ? DateUtils.dateOnly(paymentDueDate!)
                : today;
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate: initial,
              firstDate: today,
              lastDate: DateTime(today.year + 10, today.month, today.day),
              helpText: 'When is this payment due?',
              confirmText: 'Set due date',
            );
            if (picked == null || !sheetContext.mounted) return;
            final settings = await PaymentReminderService.instance
                .loadSettings();
            if (!sheetContext.mounted) return;
            final initialMinutes =
                paymentDueMinute ??
                settings.dueDayTime.hour * 60 + settings.dueDayTime.minute;
            final pickedTime = await showTimePicker(
              context: sheetContext,
              initialTime: TimeOfDay(
                hour: initialMinutes ~/ 60,
                minute: initialMinutes % 60,
              ),
              helpText: 'When should Easy Khata alert you?',
              confirmText: 'Set alert time',
            );
            if (pickedTime == null || !sheetContext.mounted) return;
            final selectedDueDate = DateUtils.dateOnly(picked);
            final selectedMinutes = pickedTime.hour * 60 + pickedTime.minute;
            if (!isReminderTimeInFuture(
              dueDate: selectedDueDate,
              dueDayMinutes: selectedMinutes,
              now: DateTime.now(),
            )) {
              await showPassedTimeWarning(sheetContext);
              return;
            }
            var allowed = false;
            try {
              allowed = await PaymentReminderService.instance
                  .requestPermissions();
            } catch (error, stackTrace) {
              debugPrint(
                'Requesting payment reminder permission failed: '
                '$error\n$stackTrace',
              );
            }
            if (!sheetContext.mounted) return;
            setModalState(() {
              paymentDueDate = selectedDueDate;
              paymentDueMinute = selectedMinutes;
              alertTimePassed = false;
              notificationsOff = !allowed;
            });
          }

          /// One-tap return date: [days] from today at the usual alert time.
          Future<void> quickDue(int days) async {
            final today = DateUtils.dateOnly(DateTime.now());
            final settings = await PaymentReminderService.instance
                .loadSettings();
            if (!sheetContext.mounted) return;
            final minutes =
                paymentDueMinute ??
                settings.dueDayTime.hour * 60 + settings.dueDayTime.minute;
            final date = DateTime(today.year, today.month, today.day + days);
            if (!isReminderTimeInFuture(
              dueDate: date,
              dueDayMinutes: minutes,
              now: DateTime.now(),
            )) {
              await showPassedTimeWarning(sheetContext);
              return;
            }
            var allowed = false;
            try {
              allowed = await PaymentReminderService.instance
                  .requestPermissions();
            } catch (error, stackTrace) {
              debugPrint(
                'Requesting payment reminder permission failed: '
                '$error\n$stackTrace',
              );
            }
            if (!sheetContext.mounted) return;
            setModalState(() {
              paymentDueDate = date;
              paymentDueMinute = minutes;
              alertTimePassed = false;
              notificationsOff = !allowed;
            });
          }

          final media = MediaQuery.of(sheetContext);
          final keyboardOpen = media.viewInsets.bottom > 0;
          final calcHeight = (media.size.height * 0.36).clamp(230.0, 340.0);
          final border = OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          );

          return Padding(
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- handle + header ----
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(typeIcon, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit ? 'Edit $label entry' : 'New $label entry',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            Text(
                              meaning,
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
                      IconButton(
                        tooltip: 'Close',
                        onPressed: isSaving
                            ? null
                            : () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),

                // ---- scrollable body ----
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Amount
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: color.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Amount',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        formatMoney(
                                          tempValue <= 0 ? 0 : tempValue,
                                        ),
                                        style: TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Date (new entries only)
                        Visibility(
                          visible: !isEdit,
                          maintainState: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: isSaving ? null : pickDate,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.event_outlined,
                                        size: 20,
                                        color: AppColors.muted,
                                      ),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Date',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        DateUtils.isSameDay(
                                              entryDate,
                                              DateTime.now(),
                                            )
                                            ? 'Today'
                                            : formatDate(entryDate),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.expand_more_rounded,
                                        color: AppColors.muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Payment due date and reminder
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isSaving ? null : pickPaymentDueDate,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.notifications_active_outlined,
                                      size: 20,
                                      color: paymentDueDate == null
                                          ? AppColors.muted
                                          : AppColors.navy,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Payment due date',
                                            style: TextStyle(
                                              color: AppColors.ink,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            paymentDueDate == null
                                                ? 'Optional · set a reminder'
                                                : '${formatDate(paymentDueDate!)}'
                                                      '${paymentDueMinute == null ? '' : ' · ${TimeOfDay(hour: paymentDueMinute! ~/ 60, minute: paymentDueMinute! % 60).format(sheetContext)}'}',
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (paymentDueDate != null &&
                                              (alertTimePassed ||
                                                  notificationsOff))
                                            Text(
                                              alertTimePassed
                                                  ? 'This time has passed. Choose a future time.'
                                                  : 'Notifications are off. Allow them in settings to get this alert.',
                                              style: const TextStyle(
                                                color: AppColors.payable,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (paymentDueDate != null)
                                      IconButton(
                                        tooltip: 'Remove due date',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: isSaving
                                            ? null
                                            : () => setModalState(() {
                                                paymentDueDate = null;
                                                paymentDueMinute = null;
                                                alertTimePassed = false;
                                                notificationsOff = false;
                                              }),
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 19,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColors.muted,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  ActionChip(
                                    label: const Text('Tomorrow'),
                                    onPressed: isSaving
                                        ? null
                                        : () => quickDue(1),
                                  ),
                                  ActionChip(
                                    label: const Text('In 1 week'),
                                    onPressed: isSaving
                                        ? null
                                        : () => quickDue(7),
                                  ),
                                  ActionChip(
                                    label: const Text('Pick date and time'),
                                    onPressed: isSaving
                                        ? null
                                        : pickPaymentDueDate,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'A return date is optional. With one, you get '
                                '3 reminders the day before and 1 on the day, '
                                'until the khata is settled.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Note (free text)
                        TextField(
                          key: descFieldKey,
                          controller: descController,
                          focusNode: descFocus,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          maxLength: 80,
                          onSubmitted: (_) => descFocus.unfocus(),
                          onTapOutside: (_) => descFocus.unfocus(),
                          onChanged: (_) => setModalState(() {}),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            hintText: 'Add a note (optional), e.g. Rice 5 kg',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                            ),
                            prefixIcon: const Icon(
                              Icons.notes_rounded,
                              color: AppColors.muted,
                            ),
                            suffixIcon: descController.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      descController.clear();
                                      setModalState(() {});
                                    },
                                  ),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: border.copyWith(
                              borderSide: const BorderSide(
                                color: AppColors.navy,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Calculator (hidden while typing the note)
                        Visibility(
                          visible: !keyboardOpen,
                          maintainState: true,
                          child: SizedBox(
                            height: calcHeight,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: SimpleCalculator(
                                value: tempValue,
                                hideExpression: false,
                                hideSurroundingBorder: true,
                                autofocus: false,
                                theme: CalculatorThemeData(
                                  borderColor: Colors.white,
                                  borderWidth: 1.5,
                                  displayColor: Colors.white,
                                  expressionColor: const Color(0xFFF8FAFC),
                                  numColor: const Color(0xFFF1F5F9),
                                  numStyle: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                  commandColor: const Color(0xFFE2E8F0),
                                  commandStyle: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF475569),
                                  ),
                                  operatorColor: AppColors.navy,
                                  operatorStyle: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  equalColor: color,
                                  equalStyle: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                  displayStyle: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                  expressionStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                  ),
                                ),
                                onChanged: (key, value, expression) {
                                  setModalState(() => tempValue = value ?? 0.0);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---- save (always visible) ----
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          disabledBackgroundColor: color.withValues(alpha: 0.7),
                          disabledForegroundColor: Colors.white,
                        ),
                        onPressed: isSaving ? null : submit,
                        child: isSaving
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Saving…'),
                                ],
                              )
                            : Text(
                                isEdit
                                    ? 'Update $label entry'
                                    : 'Save $label entry',
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
