import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:flutter/material.dart';

/// A return date and the minute of that day the alert fires.
typedef ReturnDateChoice = ({DateTime date, int minutes});

/// Tells the user the chosen alert time is already in the past. A dialog, not
/// a snack bar: snack bars are hidden behind an open bottom sheet.
///
/// With [nothingSaved] the user had pressed save and the save was refused.
Future<void> showPassedTimeWarning(
  BuildContext context, {
  bool nothingSaved = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.accent,
        size: 34,
      ),
      title: const Text('That time has already passed'),
      content: Text(
        nothingSaved
            ? 'The return date and alert time you selected are in the past, '
                  'so nothing was saved. Choose a future date and time, or '
                  'remove the return date, then save again.'
            : 'A reminder cannot be set for a time in the past. Choose a '
                  'future date and time.',
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

String _formatMinutes(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

/// Lets the user push a return date further out, before or after it has
/// passed. Returns the new date and alert time, or null when dismissed.
Future<ReturnDateChoice?> showExtendReturnDateSheet({
  required BuildContext context,
  required String partyName,
  required DateTime currentDueDate,
  required int? currentDueMinute,
}) async {
  final settings = await PaymentReminderService.instance.loadSettings();
  if (!context.mounted) return null;

  final storedMinute = currentDueMinute;
  final minutes =
      storedMinute != null && storedMinute >= 0 && storedMinute < 24 * 60
      ? storedMinute
      : settings.dueDayTime.hour * 60 + settings.dueDayTime.minute;
  final now = DateTime.now();
  final today = DateUtils.dateOnly(now);
  final currentDay = DateUtils.dateOnly(currentDueDate);
  final overdue = isReturnDateOverdue(
    dueDate: currentDay,
    dueDayMinutes: currentDueMinute,
    now: now,
  );
  // An overdue date is extended from today, an upcoming one from itself, so
  // every quick choice lands in the future.
  final base = currentDay.isBefore(today) ? today : currentDay;
  const quickChoices = [
    ('1 day', 1),
    ('3 days', 3),
    ('1 week', 7),
    ('30 days', 30),
  ];

  return showModalBottomSheet<ReturnDateChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      Future<void> pickCustom() async {
        final tomorrow = DateTime(base.year, base.month, base.day + 1);
        final picked = await showDatePicker(
          context: sheetContext,
          initialDate: tomorrow,
          firstDate: today,
          lastDate: DateTime(today.year + 10, today.month, today.day),
          helpText: 'New return date',
          confirmText: 'Set return date',
        );
        if (picked == null || !sheetContext.mounted) return;
        final pickedTime = await showTimePicker(
          context: sheetContext,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          helpText: 'When should Easy Khata alert you?',
          confirmText: 'Set alert time',
        );
        if (pickedTime == null || !sheetContext.mounted) return;
        final pickedMinutes = pickedTime.hour * 60 + pickedTime.minute;
        if (!isReminderTimeInFuture(
          dueDate: picked,
          dueDayMinutes: pickedMinutes,
          now: DateTime.now(),
        )) {
          await showPassedTimeWarning(sheetContext);
          return;
        }
        Navigator.of(
          sheetContext,
        ).pop((date: DateUtils.dateOnly(picked), minutes: pickedMinutes));
      }

      return SingleChildScrollView(
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
              'Extend return date',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Give $partyName more time. Reminders move to the new date.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: overdue
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: overdue
                      ? AppColors.payable.withValues(alpha: 0.25)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    overdue
                        ? Icons.error_outline_rounded
                        : Icons.event_available_rounded,
                    size: 20,
                    color: overdue ? AppColors.payable : AppColors.navy,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current: ${formatDate(currentDay)} · '
                          '${_formatMinutes(sheetContext, minutes)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          describeReturnDate(
                            dueDate: currentDay,
                            dueDayMinutes: currentDueMinute,
                            now: now,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: overdue
                                ? AppColors.payable
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              overdue ? 'EXTEND FROM TODAY BY' : 'EXTEND BY',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final (label, days) in quickChoices)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.update_rounded, color: AppColors.navy),
                title: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${formatDate(DateTime(base.year, base.month, base.day + days))}'
                  ' · ${_formatMinutes(sheetContext, minutes)}',
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                ),
                onTap: () => Navigator.of(sheetContext).pop((
                  date: DateTime(base.year, base.month, base.day + days),
                  minutes: minutes,
                )),
              ),
            const Divider(height: 8),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(
                Icons.edit_calendar_rounded,
                color: AppColors.navy,
              ),
              title: const Text(
                'Choose date and time',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
              onTap: pickCustom,
            ),
          ],
        ),
      );
    },
  );
}
