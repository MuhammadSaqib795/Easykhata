import 'package:digitalkhata/services/backup_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final last = DateTime(2026, 1, 31, 10, 30);

  test('next run per frequency', () {
    expect(BackupFrequency.hourly.nextAfter(last), DateTime(2026, 1, 31, 11, 30));
    expect(BackupFrequency.daily.nextAfter(last), DateTime(2026, 2, 1, 10, 30));
    expect(BackupFrequency.weekly.nextAfter(last), DateTime(2026, 2, 7, 10, 30));
    // 31 Jan + 1 month clamps to the last day of February.
    expect(BackupFrequency.monthly.nextAfter(last), DateTime(2026, 2, 28, 10, 30));
    expect(BackupFrequency.yearly.nextAfter(last), DateTime(2027, 1, 31, 10, 30));
    expect(BackupFrequency.never.nextAfter(last), isNull);
  });

  test('monthly rolls over the year', () {
    expect(
      BackupFrequency.monthly.nextAfter(DateTime(2026, 12, 15)),
      DateTime(2027, 1, 15),
    );
  });

  test('due logic', () {
    expect(BackupFrequency.daily.isDue(lastRun: null, now: last), isTrue);
    expect(
      BackupFrequency.daily.isDue(
        lastRun: last,
        now: last.add(const Duration(hours: 23)),
      ),
      isFalse,
    );
    expect(
      BackupFrequency.daily.isDue(
        lastRun: last,
        now: last.add(const Duration(days: 1)),
      ),
      isTrue,
    );
    expect(BackupFrequency.never.isDue(lastRun: null, now: last), isFalse);
  });

  test('names round-trip for saved settings', () {
    for (final f in BackupFrequency.values) {
      expect(BackupFrequency.fromName(f.name), f);
    }
    expect(BackupFrequency.fromName('bogus'), isNull);
  });
}
