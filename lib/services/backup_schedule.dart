/// How often automatic backup runs. The user chooses this; [never] means
/// manual backup only.
enum BackupFrequency {
  hourly('Hourly', 'Every hour'),
  daily('Daily', 'Once a day'),
  weekly('Weekly', 'Once a week'),
  monthly('Monthly', 'Once a month'),
  yearly('Yearly', 'Once a year'),
  never('Never', 'Only when you tap "Back up now"');

  const BackupFrequency(this.label, this.description);

  final String label;
  final String description;

  static BackupFrequency? fromName(String? name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// When the next automatic backup is due after a run at [last].
  /// Months and years follow the calendar (31 Jan + 1 month = 28/29 Feb).
  DateTime? nextAfter(DateTime last) {
    switch (this) {
      case BackupFrequency.hourly:
        return last.add(const Duration(hours: 1));
      case BackupFrequency.daily:
        return last.add(const Duration(days: 1));
      case BackupFrequency.weekly:
        return last.add(const Duration(days: 7));
      case BackupFrequency.monthly:
        return _addMonths(last, 1);
      case BackupFrequency.yearly:
        return _addMonths(last, 12);
      case BackupFrequency.never:
        return null;
    }
  }

  /// True when an automatic backup should run now. A user who never had a
  /// successful run is due immediately.
  bool isDue({required DateTime? lastRun, required DateTime now}) {
    if (this == BackupFrequency.never) return false;
    if (lastRun == null) return true;
    return !now.isBefore(nextAfter(lastRun)!);
  }

  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(
      year,
      month,
      day,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
    );
  }
}
