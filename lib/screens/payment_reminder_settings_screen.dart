import 'package:digitalkhata/db/dbhelper.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:flutter/material.dart';

class PaymentReminderSettingsScreen extends StatefulWidget {
  const PaymentReminderSettingsScreen({super.key});

  @override
  State<PaymentReminderSettingsScreen> createState() =>
      _PaymentReminderSettingsScreenState();
}

class _PaymentReminderSettingsScreenState
    extends State<PaymentReminderSettingsScreen> {
  final _service = PaymentReminderService.instance;
  late Future<PaymentReminderSettings> _settingsFuture;
  List<ReminderTime> _dayBeforeTimes =
      PaymentReminderSettings.defaults.dayBeforeTimes;
  ReminderTime _dueDayTime = PaymentReminderSettings.defaults.dueDayTime;
  bool _loaded = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
  }

  Future<PaymentReminderSettings> _loadSettings() async {
    final settings = await _service.loadSettings();
    if (mounted) {
      setState(() {
        _dayBeforeTimes = List.of(settings.dayBeforeTimes);
        _dueDayTime = settings.dueDayTime;
        _loaded = true;
      });
    }
    return settings;
  }

  Future<void> _pickTime({required int? slot}) async {
    final current = slot == null
        ? TimeOfDay(hour: _dueDayTime.hour, minute: _dueDayTime.minute)
        : TimeOfDay(
            hour: _dayBeforeTimes[slot].hour,
            minute: _dayBeforeTimes[slot].minute,
          );
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: slot == null ? 'Reminder on the due date' : 'Reminder time',
    );
    if (picked == null || !mounted) return;
    final selected = ReminderTime(picked.hour, picked.minute);
    if (slot != null &&
        _dayBeforeTimes.asMap().entries.any(
          (entry) =>
              entry.key != slot &&
              entry.value.hour == selected.hour &&
              entry.value.minute == selected.minute,
        )) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Choose a different time for each day-before reminder.',
            ),
          ),
        );
      return;
    }
    setState(() {
      if (slot == null) {
        _dueDayTime = selected;
      } else {
        _dayBeforeTimes[slot] = selected;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_loaded) return;
    setState(() => _saving = true);
    try {
      final settings = PaymentReminderSettings(
        dayBeforeTimes: List.unmodifiable(_dayBeforeTimes),
        dueDayTime: _dueDayTime,
      );
      try {
        await _service.saveSettings(settings);
      } catch (error, stackTrace) {
        debugPrint('Saving payment reminder times failed: $error\n$stackTrace');
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                error is ArgumentError
                    ? 'Choose three different times for the day-before reminders.'
                    : 'Reminder times could not be saved. Check device storage and try again.',
              ),
              backgroundColor: AppColors.payable,
            ),
          );
        return;
      }

      bool? allowed;
      try {
        allowed = await _service.requestPermissions();
      } catch (error, stackTrace) {
        debugPrint(
          'Requesting notification permission while saving reminders '
          'failed: $error\n$stackTrace',
        );
      }

      try {
        final db = await Dbhelper.getInstance.getDB();
        // Entries whose return date has passed keep no reminder; they are
        // marked overdue in the customer's khata, where they can be extended.
        final result = await _service.rescheduleAll(db);
        if (result.failedTransactions > 0) {
          debugPrint(
            'Saved reminder times, but ${result.failedTransactions} '
            'payment reminder(s) could not be scheduled. '
            'First error: ${result.firstFailure}',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Reminder times were saved. '
                  '${result.failedTransactions} payment alert(s) could not '
                  'be scheduled; check those entries and notification access.',
                ),
                backgroundColor: AppColors.payable,
              ),
            );
          return;
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Refreshing scheduled reminders after saving settings '
          'failed: $error\n$stackTrace',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Reminder times were saved, but existing reminders could not '
                'be refreshed. Check due dates and try saving again.',
              ),
              backgroundColor: AppColors.payable,
            ),
          );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              allowed == false
                  ? 'Times saved, but notifications are off for Easy Khata. Allow them in your phone settings.'
                  : 'Reminder times saved.',
            ),
            backgroundColor: allowed == false
                ? AppColors.accent
                : AppColors.receivable,
          ),
        );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Shows a notification now, so the user can see that alerts reach them.
  Future<void> _sendTest() async {
    if (_testing) return;
    setState(() => _testing = true);
    String message;
    var failed = true;
    try {
      if (await _service.requestPermissions() &&
          await _service.notificationsEnabled()) {
        await _service.showTestNotification();
        message = 'Test notification sent. Check your notification panel.';
        failed = false;
      } else {
        message =
            'Notifications are off for Easy Khata. Allow them in your phone '
            'settings, then try again.';
      }
    } catch (error, stackTrace) {
      debugPrint('Sending a test notification failed: $error\n$stackTrace');
      message = 'The test notification could not be shown. Please try again.';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failed ? AppColors.payable : AppColors.receivable,
        ),
      );
  }

  String _format(ReminderTime time) {
    final local = TimeOfDay(hour: time.hour, minute: time.minute);
    return local.format(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment reminders')),
      body: FutureBuilder<PaymentReminderSettings>(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Reminder settings could not be loaded.'),
            );
          }
          if (!_loaded) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF243B5A), AppColors.navy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFFFD17A),
                      size: 26,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Never miss a due date',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Choose when Easy Khata reminds you before a '
                            'payment is due and on the due date.',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              height: 1.45,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'THE DAY BEFORE',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var slot = 0; slot < 3; slot++) ...[
                      if (slot > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor: AppColors.navy.withValues(
                            alpha: 0.07,
                          ),
                          child: Text(
                            '${slot + 1}',
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          [
                            'Morning reminder',
                            'Afternoon reminder',
                            'Evening reminder',
                          ][slot],
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _format(_dayBeforeTimes[slot]),
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                        onTap: () => _pickTime(slot: slot),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ON THE DUE DATE',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(
                      Icons.event_available_rounded,
                      color: AppColors.navy,
                    ),
                  ),
                  title: const Text(
                    'Default alert time',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Default when you add a return date; you can set a '
                    'different time for each payment entry.',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _format(_dueDayTime),
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                  onTap: () => _pickTime(slot: null),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'These times use your phone’s local time. The customer and '
                'payment direction are included in each private notification.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save reminder times'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _testing ? null : _sendTest,
                icon: const Icon(Icons.notifications_none_rounded),
                label: Text(
                  _testing ? 'Sending…' : 'Send a test notification',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
