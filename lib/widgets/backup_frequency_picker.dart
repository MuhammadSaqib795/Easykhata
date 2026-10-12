import 'package:digitalkhata/services/backup_schedule.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Lets the user choose how often automatic backup runs.
///
/// With [firstTime] the sheet cannot be dismissed without a choice (shown
/// once after signing in when no frequency is set yet).
Future<BackupFrequency?> showBackupFrequencyPicker(
  BuildContext context, {
  BackupFrequency? current,
  bool firstTime = false,
}) {
  return showModalBottomSheet<BackupFrequency>(
    context: context,
    isScrollControlled: true,
    isDismissible: !firstTime,
    enableDrag: !firstTime,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => PopScope(
      canPop: !firstTime,
      child: _FrequencySheet(
        initial: current ?? BackupFrequency.daily,
        firstTime: firstTime,
      ),
    ),
  );
}

class _FrequencySheet extends StatefulWidget {
  const _FrequencySheet({required this.initial, required this.firstTime});

  final BackupFrequency initial;
  final bool firstTime;

  @override
  State<_FrequencySheet> createState() => _FrequencySheetState();
}

class _FrequencySheetState extends State<_FrequencySheet> {
  late BackupFrequency _selected = widget.initial;

  static const _icons = {
    BackupFrequency.hourly: Icons.schedule_rounded,
    BackupFrequency.daily: Icons.today_rounded,
    BackupFrequency.weekly: Icons.date_range_rounded,
    BackupFrequency.monthly: Icons.calendar_month_rounded,
    BackupFrequency.yearly: Icons.event_repeat_rounded,
    BackupFrequency.never: Icons.block_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.cloud_sync_outlined,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.firstTime
                        ? 'How often should we back up?'
                        : 'Backup frequency',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Your khata is backed up automatically to your signed-in account. '
              'You can change this anytime from Backup.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            for (final f in BackupFrequency.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Option(
                  icon: _icons[f]!,
                  title: f.label,
                  subtitle: f.description,
                  selected: _selected == f,
                  recommended: f == BackupFrequency.daily,
                  onTap: () => setState(() => _selected = f),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy.withValues(alpha: 0.05) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.navy : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: selected ? AppColors.navy : AppColors.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.receivable.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Recommended',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.receivable,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.navy : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
