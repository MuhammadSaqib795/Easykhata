import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:digitalkhata/db/dbhelper.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

@immutable
class ReminderTime {
  const ReminderTime(this.hour, this.minute);

  final int hour;
  final int minute;

  Map<String, int> toJson() => {'hour': hour, 'minute': minute};

  factory ReminderTime.fromJson(Map<String, dynamic> json) =>
      ReminderTime(json['hour'] as int, json['minute'] as int);
}

@immutable
class PaymentReminderSettings {
  const PaymentReminderSettings({
    required this.dayBeforeTimes,
    required this.dueDayTime,
  });

  static const defaults = PaymentReminderSettings(
    dayBeforeTimes: [
      ReminderTime(9, 0),
      ReminderTime(13, 0),
      ReminderTime(18, 0),
    ],
    dueDayTime: ReminderTime(9, 0),
  );

  final List<ReminderTime> dayBeforeTimes;
  final ReminderTime dueDayTime;

  Map<String, Object> toJson() => {
    'dayBeforeTimes': dayBeforeTimes.map((time) => time.toJson()).toList(),
    'dueDayTime': dueDayTime.toJson(),
  };

  factory PaymentReminderSettings.fromJson(Map<String, dynamic> json) {
    final times = (json['dayBeforeTimes'] as List<dynamic>)
        .map((value) => ReminderTime.fromJson(value as Map<String, dynamic>))
        .toList();
    final due = ReminderTime.fromJson(
      json['dueDayTime'] as Map<String, dynamic>,
    );
    _validateSettings(times, due);
    return PaymentReminderSettings(dayBeforeTimes: times, dueDayTime: due);
  }
}

@immutable
class ReminderOccurrence {
  const ReminderOccurrence({required this.slot, required this.dateTime});

  /// Slots 0-2 are the day-before reminders; slot 3 is the due-day reminder.
  final int slot;
  final DateTime dateTime;
}

bool isReminderTimeInFuture({
  required DateTime dueDate,
  required int dueDayMinutes,
  required DateTime now,
}) {
  if (dueDayMinutes < 0 || dueDayMinutes >= 24 * 60) return false;
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final today = DateTime(now.year, now.month, now.day);
  if (dueDay.isBefore(today)) return false;
  final reminderAt = DateTime(
    dueDay.year,
    dueDay.month,
    dueDay.day,
    dueDayMinutes ~/ 60,
    dueDayMinutes % 60,
  );
  return reminderAt.isAfter(now);
}

/// When the return is expected: the due day at its alert time, or the end of
/// the due day when the entry has no alert time of its own.
DateTime returnDeadline(DateTime dueDate, int? dueDayMinutes) {
  final valid =
      dueDayMinutes != null && dueDayMinutes >= 0 && dueDayMinutes < 24 * 60;
  return valid
      ? DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          dueDayMinutes ~/ 60,
          dueDayMinutes % 60,
        )
      : DateTime(dueDate.year, dueDate.month, dueDate.day + 1);
}

bool isReturnDateOverdue({
  required DateTime dueDate,
  required int? dueDayMinutes,
  required DateTime now,
}) => !returnDeadline(dueDate, dueDayMinutes).isAfter(now);

/// "Overdue by 3 days", "Overdue today", "Due today", "Due tomorrow",
/// "Due in 5 days".
String describeReturnDate({
  required DateTime dueDate,
  required int? dueDayMinutes,
  required DateTime now,
}) {
  // Whole calendar days, counted in UTC so a daylight-saving change cannot
  // shorten a day.
  final days = DateTime.utc(
    dueDate.year,
    dueDate.month,
    dueDate.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  if (isReturnDateOverdue(
    dueDate: dueDate,
    dueDayMinutes: dueDayMinutes,
    now: now,
  )) {
    if (days >= 0) return 'Overdue today';
    return 'Overdue by ${-days} ${days == -1 ? 'day' : 'days'}';
  }
  if (days <= 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}

@immutable
class ReminderRescheduleResult {
  const ReminderRescheduleResult({
    required this.failedTransactions,
    required this.passedAlertTimes,
    this.firstFailure,
  });

  final int failedTransactions;
  final int passedAlertTimes;
  final String? firstFailure;
}

List<ReminderOccurrence> calculateReminderOccurrences({
  required DateTime dueDate,
  required PaymentReminderSettings settings,
  required DateTime now,
  int? dueDayMinutes,
}) {
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final today = DateTime(now.year, now.month, now.day);
  if (dueDay.isBefore(today)) return const [];

  final occurrences = <ReminderOccurrence>[];

  if (dueDay.isAfter(today)) {
    final previousDay = DateTime(dueDay.year, dueDay.month, dueDay.day - 1);
    for (var i = 0; i < settings.dayBeforeTimes.length; i++) {
      final time = settings.dayBeforeTimes[i];
      final reminderAt = DateTime(
        previousDay.year,
        previousDay.month,
        previousDay.day,
        time.hour,
        time.minute,
      );
      if (reminderAt.isAfter(now)) {
        occurrences.add(ReminderOccurrence(slot: i, dateTime: reminderAt));
      }
    }
  }

  final dueMinutes =
      dueDayMinutes ??
      settings.dueDayTime.hour * 60 + settings.dueDayTime.minute;
  if (dueMinutes < 0 || dueMinutes >= 24 * 60) {
    throw ArgumentError.value(dueMinutes, 'dueDayMinutes');
  }
  final dueReminderAt = DateTime(
    dueDay.year,
    dueDay.month,
    dueDay.day,
    dueMinutes ~/ 60,
    dueMinutes % 60,
  );
  if (dueReminderAt.isAfter(now)) {
    occurrences.add(ReminderOccurrence(slot: 3, dateTime: dueReminderAt));
  }
  return occurrences;
}

void _validateSettings(List<ReminderTime> before, ReminderTime due) {
  if (before.length != 3) {
    throw ArgumentError(
      'Exactly three day-before reminder times are required.',
    );
  }
  for (final time in [...before, due]) {
    if (time.hour < 0 ||
        time.hour > 23 ||
        time.minute < 0 ||
        time.minute > 59) {
      throw ArgumentError('Reminder time is outside the valid time range.');
    }
  }
  final beforeMinutes = before
      .map((time) => time.hour * 60 + time.minute)
      .toSet();
  if (beforeMinutes.length != before.length) {
    throw ArgumentError('Day-before reminders must use different times.');
  }
}

class PaymentReminderService {
  PaymentReminderService._();

  static final instance = PaymentReminderService._();
  static const _settingsKey = 'payment_reminder_settings_v1';
  static const _channelId = 'payment_due_reminders';
  static const _channelName = 'Payment reminders';
  static const _channelDescription =
      'Reminders for customer payments due soon.';
  // White-on-transparent drawable; a launcher icon shows as a blank square
  // in the Android status bar.
  static const _smallIcon = 'ic_stat_payment_reminder';
  static const _payloadPrefix = 'payment:';
  static const _notificationCount = 4;
  // Above every id [_notificationId] can produce.
  static const _testNotificationId = 0x7fffffff;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _exactAlarmAccessRequested = false;

  /// Transaction whose reminder the user tapped, until a screen opens it.
  final ValueNotifier<int?> tappedTransactionId = ValueNotifier<int?>(null);

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    final initializing = _initializing;
    if (initializing != null) return initializing;
    final pending = _initialize();
    _initializing = pending;
    return pending.whenComplete(() {
      if (!_initialized) _initializing = null;
    });
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } on Object catch (error, stackTrace) {
      // Reminders are scheduled as exact instants, so they still fire at the
      // right moment when the zone name is unknown and UTC stays in use.
      debugPrint('Reading the device time zone failed: $error\n$stackTrace');
    }
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_smallIcon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _recordTap(response.payload),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    _initialized = true;
    try {
      // The app was closed and a reminder tap started it.
      final launch = await _notifications.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _recordTap(launch?.notificationResponse?.payload);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Reading the launch notification failed: $error\n$stackTrace');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  void _recordTap(String? payload) {
    if (payload == null || !payload.startsWith(_payloadPrefix)) return;
    final id = int.tryParse(payload.substring(_payloadPrefix.length));
    if (id != null) tappedTransactionId.value = id;
  }

  NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: _smallIcon,
      color: const Color(0xFF111827),
      category: AndroidNotificationCategory.reminder,
      // Shows the whole message instead of cutting it to one line.
      styleInformation: BigTextStyleInformation(body),
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
  );

  /// Exact alarms need a separate permission on Android 12+. Without it an
  /// exact request throws, so reminders fall back to inexact delivery (a few
  /// minutes late at most) instead of never being scheduled.
  Future<AndroidScheduleMode> _scheduleMode() async {
    if (!Platform.isAndroid) return AndroidScheduleMode.exactAllowWhileIdle;
    try {
      final exact = await _android?.canScheduleExactNotifications() ?? false;
      return exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } on Object catch (error) {
      debugPrint('Checking exact-alarm access failed: $error');
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  /// Whether the user currently lets Easy Khata show notifications.
  Future<bool> notificationsEnabled() async {
    await initialize();
    if (Platform.isAndroid) {
      return await _android?.areNotificationsEnabled() ?? true;
    }
    if (Platform.isIOS) {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    return true;
  }

  /// Shows a notification right away so the user can confirm alerts work.
  Future<void> showTestNotification() async {
    await initialize();
    const body =
        'Payment reminders are working. You will be alerted like this '
        'before a return date and on the day itself.';
    await _notifications.show(
      id: _testNotificationId,
      title: 'Easy Khata reminders are on',
      body: body,
      notificationDetails: _details(body),
    );
  }

  Future<bool> requestPermissions() async {
    await initialize();
    if (Platform.isAndroid) {
      final android = _android;
      final notificationsAllowed =
          await android?.requestNotificationsPermission() ?? true;
      if (!notificationsAllowed) return false;
      // Exact-alarm access only makes alerts punctual; reminders still arrive
      // without it. Asking opens a system settings page, so ask once per run.
      if (!_exactAlarmAccessRequested &&
          !(await android?.canScheduleExactNotifications() ?? true)) {
        _exactAlarmAccessRequested = true;
        await android?.requestExactAlarmsPermission();
      }
      return true;
    }
    if (Platform.isIOS) {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: false,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<PaymentReminderSettings> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_settingsKey);
    if (stored == null) return PaymentReminderSettings.defaults;
    try {
      return PaymentReminderSettings.fromJson(
        jsonDecode(stored) as Map<String, dynamic>,
      );
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Reading payment reminder settings failed: $error\n$stackTrace',
      );
      return PaymentReminderSettings.defaults;
    }
  }

  Future<void> saveSettings(PaymentReminderSettings settings) async {
    _validateSettings(settings.dayBeforeTimes, settings.dueDayTime);
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _settingsKey,
      jsonEncode(settings.toJson()),
    );
    if (!saved) throw StateError('Could not save payment reminder settings.');
  }

  Future<bool> scheduleTransaction({
    required int transactionId,
    required String customerName,
    required double amount,
    required String type,
    required DateTime dueDate,
    int? dueDayMinutes,
  }) async {
    await initialize();
    if (transactionId <= 0) {
      throw ArgumentError.value(transactionId, 'transactionId');
    }
    final settings = await loadSettings();
    final occurrences = calculateReminderOccurrences(
      dueDate: dueDate,
      settings: settings,
      now: DateTime.now(),
      dueDayMinutes: dueDayMinutes,
    );
    final isGave = type == 'Gave';
    final scheduledSlots = <int>{};
    final scheduleMode = occurrences.isEmpty
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : await _scheduleMode();

    for (final occurrence in occurrences) {
      final dueDay = occurrence.slot == 3;
      final title = isGave
          ? 'Payment due from $customerName'
          : 'Payment due to $customerName';
      final when = dueDay ? 'Due today' : 'Due tomorrow';
      final message = isGave
          ? '$when: $customerName should pay you ${formatMoney(amount)}.'
          : '$when: you need to pay $customerName ${formatMoney(amount)}.';
      final body = dueDay
          ? '$message Tap to extend the return date.'
          : message;
      await _notifications.zonedSchedule(
        id: _notificationId(transactionId, occurrence.slot),
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(occurrence.dateTime, tz.local),
        notificationDetails: _details(body),
        androidScheduleMode: scheduleMode,
        payload: '$_payloadPrefix$transactionId',
      );
      scheduledSlots.add(occurrence.slot);
    }

    final baseId = _notificationId(transactionId, 0);
    for (var slot = 0; slot < _notificationCount; slot++) {
      if (!scheduledSlots.contains(slot)) {
        await _notifications.cancel(id: baseId + slot);
      }
    }
    return scheduledSlots.contains(3);
  }

  Future<void> cancelTransaction(int transactionId) async {
    await initialize();
    final base = _notificationId(transactionId, 0);
    for (var slot = 0; slot < _notificationCount; slot++) {
      await _notifications.cancel(id: base + slot);
    }
  }

  Future<void> cancelAll() async {
    await initialize();
    await _notifications.cancelAll();
  }

  Future<ReminderRescheduleResult> rescheduleAll(DatabaseExecutor db) async {
    await initialize();
    final rows = await db.rawQuery('''
      SELECT t.${Dbhelper.colTransId}, t.${Dbhelper.colAmount},
        t.${Dbhelper.colTrantype}, t.${Dbhelper.colTranPaymentDueAt},
        t.${Dbhelper.colTranPaymentDueMinute},
        c.${Dbhelper.colCustomerName}
      FROM ${Dbhelper.tableTrans} t
      INNER JOIN ${Dbhelper.tableCus} c
        ON c.${Dbhelper.colCustomerId} = t.${Dbhelper.colTranCusId}
      WHERE t.${Dbhelper.colTranPaymentDueAt} IS NOT NULL
    ''');

    final activeTransactionIds = rows
        .map((row) => (row[Dbhelper.colTransId] as num).toInt())
        .toSet();
    final pending = await _notifications.pendingNotificationRequests();
    for (final notification in pending) {
      final transactionId = notification.id ~/ _notificationCount;
      if (!activeTransactionIds.contains(transactionId)) {
        await _notifications.cancel(id: notification.id);
      }
    }

    String? firstFailure;
    var failedCount = 0;
    var passedAlertTimes = 0;
    for (final row in rows) {
      try {
        final id = (row[Dbhelper.colTransId] as num).toInt();
        final dueDate = DateTime.parse(
          row[Dbhelper.colTranPaymentDueAt] as String,
        );
        final storedMinute = (row[Dbhelper.colTranPaymentDueMinute] as num?)
            ?.toInt();
        final dueMinute =
            storedMinute != null && storedMinute >= 0 && storedMinute < 24 * 60
            ? storedMinute
            : null;
        final dueReminderScheduled = await scheduleTransaction(
          transactionId: id,
          customerName: row[Dbhelper.colCustomerName] as String,
          amount: (row[Dbhelper.colAmount] as num).toDouble(),
          type: row[Dbhelper.colTrantype] as String,
          dueDate: dueDate,
          dueDayMinutes: dueMinute,
        );
        if (!dueReminderScheduled) passedAlertTimes++;
      } catch (error, stackTrace) {
        failedCount++;
        firstFailure ??= error.toString();
        debugPrint(
          'Restoring a payment reminder failed for transaction '
          '${row[Dbhelper.colTransId]}: $error\n$stackTrace',
        );
      }
    }
    return ReminderRescheduleResult(
      failedTransactions: failedCount,
      passedAlertTimes: passedAlertTimes,
      firstFailure: firstFailure,
    );
  }

  static int _notificationId(int transactionId, int slot) {
    final maxId = 0x7fffffff;
    if (transactionId > (maxId - _notificationCount) ~/ _notificationCount) {
      throw RangeError('Transaction id is too large for a reminder.');
    }
    return transactionId * _notificationCount + slot;
  }
}
