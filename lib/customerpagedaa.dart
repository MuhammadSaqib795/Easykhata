import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/model/customermodel.dart';
import 'package:digitalkhata/services/payment_reminder_service.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/utills/contact_picker.dart';
import 'package:digitalkhata/utills/format.dart';
import 'package:digitalkhata/widgets/return_date_sheet.dart';
import 'package:digitalkhata/widgets/ui_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AddCustomerPage extends StatefulWidget {
  const AddCustomerPage({super.key});

  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _balanceController = TextEditingController();

  bool _isSaving = false;

  /// "Gave" = customer owes you, "Got" = you owe the customer.
  /// Intentionally null by default so the user must choose explicitly.
  String? _balanceType;
  String? _balanceTypeError;
  DateTime? _returnDate;
  int? _returnTimeMinutes;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_balanceController.text.trim()) ?? 0.0;

  Future<void> _pickReturnDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final current = _returnDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(today)
          ? current
          : today,
      firstDate: today,
      lastDate: DateTime(today.year + 10, today.month, today.day),
      helpText: 'When should this opening balance be returned?',
      confirmText: 'Set return date',
    );
    if (picked == null || !mounted) return;

    final settings = await PaymentReminderService.instance.loadSettings();
    if (!mounted) return;
    final initialMinutes =
        _returnTimeMinutes ??
        settings.dueDayTime.hour * 60 + settings.dueDayTime.minute;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
      helpText: 'When should Easy Khata alert you?',
      confirmText: 'Set alert time',
    );
    if (pickedTime == null || !mounted) return;
    final selectedMinutes = pickedTime.hour * 60 + pickedTime.minute;
    if (!isReminderTimeInFuture(
      dueDate: picked,
      dueDayMinutes: selectedMinutes,
      now: DateTime.now(),
    )) {
      await showPassedTimeWarning(context);
      return;
    }

    var allowed = false;
    try {
      allowed = await PaymentReminderService.instance.requestPermissions();
    } catch (error, stackTrace) {
      debugPrint(
        'Requesting payment reminder permission failed: $error\n$stackTrace',
      );
    }
    if (!mounted) return;
    setState(() {
      _returnDate = DateUtils.dateOnly(picked);
      _returnTimeMinutes = pickedTime.hour * 60 + pickedTime.minute;
    });
    if (!allowed) {
      showAppSnack(
        context,
        'The return date is set, but notifications are off for Easy Khata. '
        'Allow them in your phone settings to get the alert.',
        error: true,
      );
    }
  }

  Future<void> _importFromContacts() async {
    final picked = await pickPhoneContact(
      context,
      onError: (m) => showAppSnack(context, m, error: true),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _phoneController.text = picked.phone;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = picked.name;
      }
    });
  }

  Future<void> _saveCustomer() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState!.validate();

    // An amount needs an explicit direction (Gave / Got).
    String? typeError;
    if (_amount > 0 && _balanceType == null) {
      typeError = 'Select "You Gave" or "You Got"';
    }
    setState(() => _balanceTypeError = typeError);
    if (!formOk || typeError != null || _isSaving) return;

    final returnDate = _amount > 0 ? _returnDate : null;
    final returnTimeMinutes = _amount > 0 ? _returnTimeMinutes : null;
    // The alert time can pass while the form is still open. Nothing is saved
    // then: the user picks a new time or removes the return date.
    if (returnDate != null &&
        returnTimeMinutes != null &&
        !isReminderTimeInFuture(
          dueDate: returnDate,
          dueDayMinutes: returnTimeMinutes,
          now: DateTime.now(),
        )) {
      await showPassedTimeWarning(context, nothingSaved: true);
      return;
    }

    setState(() => _isSaving = true);

    final customer = Customermodel(
      id: null,
      name: _nameController.text.trim(),
      phoneNo: cleanPhone(_phoneController.text),
      currentBalance: 0.0, // set from the opening balance in one DB transaction
      img: '',
      desp: '',
      creationTime: DateTime.now(),
    );
    final dbProvider = context.read<Dbprovider>();

    try {
      await dbProvider.addCustomerWithOpeningBalance(
        customer,
        openingAmount: _amount,
        openingType: _amount > 0 ? _balanceType : null,
        paymentDueDate: returnDate,
        paymentDueMinute: returnTimeMinutes,
      );
      if (!mounted) return;
      showAppSnack(context, 'Customer added.');
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Save customer failed: $e');
      if (!mounted) return;
      showAppSnack(
        context,
        'The customer could not be saved. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _typeOption({
    required String type,
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final selected = _balanceType == type;
    return Expanded(
      child: Material(
        color: selected ? color.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _balanceType = type;
            _balanceTypeError = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? color : AppColors.muted),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? get _balanceSummary {
    if (_amount <= 0 || _balanceType == null) return null;
    final amt = formatMoney(_amount);
    return _balanceType == 'Gave'
        ? 'Customer will owe you $amt'
        : 'You will owe the customer $amt';
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add customer',
      subtitle:
          'Add a customer and optional opening balance. Set a return date to '
          'get payment alerts.',
      actionLabel: 'Save customer',
      busy: _isSaving,
      onAction: _saveCustomer,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Customer name',
                hint: 'e.g. Ali Khan',
                controller: _nameController,
                icon: Icons.person_outline_rounded,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              AppTextField(
                label: 'Phone number',
                hint: '03XX XXXXXXX',
                controller: _phoneController,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                validator: validatePhone,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _importFromContacts,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.navy,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.contacts_outlined, size: 18),
                  label: const Text('Pick from contacts'),
                ),
              ),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Opening balance (optional)',
                hint: '0',
                controller: _balanceController,
                icon: Icons.account_balance_wallet_outlined,
                prefixText: 'Rs. ',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                onChanged: (_) => setState(() {
                  if (_amount <= 0) {
                    _returnDate = null;
                    _returnTimeMinutes = null;
                  }
                }),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null; // optional
                  final n = double.tryParse(t);
                  if (n == null || n < 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              Row(
                children: [
                  _typeOption(
                    type: 'Gave',
                    title: 'You Gave',
                    subtitle: 'Customer owes you',
                    color: AppColors.payable,
                    icon: Icons.arrow_upward_rounded,
                  ),
                  const SizedBox(width: 12),
                  _typeOption(
                    type: 'Got',
                    title: 'You Got',
                    subtitle: 'You owe customer',
                    color: AppColors.receivable,
                    icon: Icons.arrow_downward_rounded,
                  ),
                ],
              ),
              if (_balanceTypeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _balanceTypeError!,
                    style: const TextStyle(
                      color: AppColors.payable,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              if (_balanceSummary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _balanceSummary!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isSaving || _amount <= 0 ? null : _pickReturnDate,
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
                          Icons.event_available_rounded,
                          size: 20,
                          color: _amount <= 0 || _returnDate == null
                              ? AppColors.muted
                              : AppColors.navy,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Expected return date',
                                style: TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _amount <= 0
                                    ? 'Enter an opening balance to set an alert'
                                    : _returnDate == null
                                    ? 'Optional · set a payment reminder'
                                    : '${formatDate(_returnDate!)}'
                                          '${_returnTimeMinutes == null ? '' : ' · ${TimeOfDay(hour: _returnTimeMinutes! ~/ 60, minute: _returnTimeMinutes! % 60).format(context)}'}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_returnDate != null)
                          IconButton(
                            tooltip: 'Remove return date',
                            visualDensity: VisualDensity.compact,
                            onPressed: _isSaving
                                ? null
                                : () => setState(() {
                                    _returnDate = null;
                                    _returnTimeMinutes = null;
                                  }),
                            icon: const Icon(Icons.close_rounded, size: 19),
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
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Choose when payment is expected. You can change this date '
                  'later from the customer’s opening balance entry.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}
