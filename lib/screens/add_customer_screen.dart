import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../models/payment.dart';
import '../models/subscription_plan.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/payment_schedule.dart';

/// 15-minute windows for “Requested time of delivery” (morning route).
const _morningDeliveryWindows = <String>[
  '7:00–7:15 AM',
  '7:15–7:30 AM',
  '7:30–7:45 AM',
  '7:45–8:00 AM',
  '8:00–8:15 AM',
  '8:15–8:30 AM',
  '8:30–8:45 AM',
  '8:45–9:00 AM',
];

/// 15-minute windows for evening route.
const _eveningDeliveryWindows = <String>[
  '5:30–5:45 PM',
  '5:45–6:00 PM',
  '6:00–6:15 PM',
  '6:15–6:30 PM',
  '6:30–6:45 PM',
  '6:45–7:00 PM',
];

List<String> _deliveryWindowsForSlot(DeliverySlot slot) =>
    slot == DeliverySlot.morning ? _morningDeliveryWindows : _eveningDeliveryWindows;

/// '' = no preference; [_kDeliveryTimeOther] = custom text field.
const _kDeliveryTimeOther = '__other__';

String? _validateName(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return 'Enter a name';
  if (t.length < 2) return 'Name must be at least 2 characters';
  if (t.length > 100) return 'Name must be at most 100 characters';
  return null;
}

String? _validatePhone(String? v) {
  final raw = v?.trim() ?? '';
  if (raw.isEmpty) return 'Enter a phone number';

  final digitsOnly = raw.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.length < 10) {
    return 'Enter at least 10 digits (mobile number)';
  }
  if (digitsOnly.length > 15) {
    return 'Phone number is too long (max 15 digits)';
  }

  if (!RegExp(r'^[\d\s+().-]+$').hasMatch(raw)) {
    return 'Use only digits and phone symbols (+, -, spaces, parentheses)';
  }
  return null;
}

String? _validateDeliveryLocation(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return null;
  if (t.length > 2000) {
    return 'Text is too long (max 2000 characters)';
  }
  return null;
}

String? _validateNotes(String? v) {
  final t = v?.trim() ?? '';
  if (t.length > 500) return 'Notes must be at most 500 characters';
  return null;
}

String? _validateRequestedTimeCustom(String? v) {
  final t = v?.trim() ?? '';
  if (t.length > 120) {
    return 'Requested time must be at most 120 characters';
  }
  return null;
}

String? _validateOptionalPaymentAmount(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return null;
  final n = int.tryParse(t);
  if (n == null) return 'Enter a valid amount';
  if (n < 0) return 'Amount cannot be negative';
  return null;
}

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key, this.existing});

  /// When set, the form edits this customer (same document id in Firestore).
  final Customer? existing;

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

enum _InitialPaymentOption {
  fullPayment,
  weeklyFull,
  monthlyFull,
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _deliveryTimeCustom = TextEditingController();
  final _initialPaymentAmount = TextEditingController();
  DeliverySlot _slot = DeliverySlot.morning;

  String _deliveryTimePreset = '';

  BillingPeriod _billingPeriod = BillingPeriod.monthly;
  PlanTier _planTier = PlanTier.basic;
  late DateTime _startDate;
  bool _active = true;
  bool _addInitialPayment = false;
  _InitialPaymentOption _initialPaymentOption =
      _InitialPaymentOption.fullPayment;

  final _dateFmt = DateFormat.yMMMd();
  String? _assignedDeliveryAgentUsername;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _phone.text = e.phone;
      _address.text = e.address;
      _notes.text = e.notes;
      _slot = e.preferredSlot;
      _billingPeriod = e.billingPeriod;
      _planTier = e.planTier;
      _startDate = dateOnly(e.startDate);
      _active = e.active;
      _assignedDeliveryAgentUsername = e.assignedDeliveryAgentUsername;
      _applyDeliveryTimeFromCustomer(e);
    } else {
      _startDate = dateOnly(DateTime.now());
    }
  }

  void _applyDeliveryTimeFromCustomer(Customer c) {
    final opts = _deliveryWindowsForSlot(c.preferredSlot);
    final t = c.requestedDeliveryTime.trim();
    if (t.isEmpty) {
      _deliveryTimePreset = '';
      return;
    }
    if (opts.contains(t)) {
      _deliveryTimePreset = t;
      return;
    }
    _deliveryTimePreset = _kDeliveryTimeOther;
    _deliveryTimeCustom.text = t;
  }

  DateTime get _endDate => endDateForBilling(_startDate, _billingPeriod);

  int get _planPrice => planPriceRupees(_planTier, _billingPeriod);

  String get _resolvedRequestedDeliveryTime {
    if (_deliveryTimePreset == _kDeliveryTimeOther) {
      return _deliveryTimeCustom.text.trim();
    }
    if (_deliveryTimePreset.isEmpty) return '';
    final opts = _deliveryWindowsForSlot(_slot);
    if (opts.contains(_deliveryTimePreset)) return _deliveryTimePreset;
    return '';
  }

  /// Valid dropdown value for the current slot (clears if preset doesn’t apply).
  String get _deliveryTimeDropdownValue {
    final opts = _deliveryWindowsForSlot(_slot);
    if (_deliveryTimePreset == _kDeliveryTimeOther) {
      return _kDeliveryTimeOther;
    }
    if (_deliveryTimePreset.isEmpty) return '';
    if (opts.contains(_deliveryTimePreset)) return _deliveryTimePreset;
    return '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _deliveryTimeCustom.dispose();
    _initialPaymentAmount.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<_InitialPaymentOption> get _allowedInitialPaymentOptions {
    if (_billingPeriod == BillingPeriod.weekly) {
      return const [
        _InitialPaymentOption.fullPayment,
        _InitialPaymentOption.weeklyFull,
      ];
    }
    return const [
      _InitialPaymentOption.fullPayment,
      _InitialPaymentOption.monthlyFull,
    ];
  }

  String _paymentOptionLabel(_InitialPaymentOption option) {
    switch (option) {
      case _InitialPaymentOption.fullPayment:
        return 'Full payment';
      case _InitialPaymentOption.weeklyFull:
        return 'Weekly plan only';
      case _InitialPaymentOption.monthlyFull:
        return 'Monthly plan only';
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _startDate = dateOnly(picked));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final time = _resolvedRequestedDeliveryTime;
    if (time.length > 120) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Requested delivery time is too long (max 120 characters).'),
        ),
      );
      return;
    }
    final repo = context.read<AppRepository>();
    final editing = widget.existing;
    final id =
        editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    var customer = Customer(
      id: id,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      preferredSlot: _slot,
      planTier: _planTier,
      billingPeriod: _billingPeriod,
      planPriceRupees: _planPrice,
      startDate: dateOnly(_startDate),
      endDate: _endDate,
      requestedDeliveryTime: time,
      active: editing != null ? _active : true,
      notes: _notes.text.trim(),
      assignedDeliveryAgentUsername: _assignedDeliveryAgentUsername,
      skippedDeliveryDays: editing?.skippedDeliveryDays ?? 0,
      skippedDeliveryDates: editing?.skippedDeliveryDates ?? const [],
      paymentTrackedPeriodStart: editing?.paymentTrackedPeriodStart,
      weeklyPeriodPaid: editing?.weeklyPeriodPaid ?? false,
      monthlyAdvancePaid: editing?.monthlyAdvancePaid ?? false,
      monthlyBalancePaid: editing?.monthlyBalancePaid ?? false,
      lastPaymentAmountRupees: editing?.lastPaymentAmountRupees,
      lastPaymentAt: editing?.lastPaymentAt,
      lastPaymentKind: editing?.lastPaymentKind,
      pendingDueKind: editing?.pendingDueKind,
      pendingDueRemainingRupees: editing?.pendingDueRemainingRupees,
      customerCreated: editing?.customerCreated ?? true,
      adminApproved: editing?.adminApproved ?? false,
    );

    final initialAmtText = _initialPaymentAmount.text.trim();
    final initialAmt = int.tryParse(initialAmtText);
    if (_addInitialPayment && initialAmt != null && initialAmt >= 0) {
      var weeklyPaid = customer.weeklyPeriodPaid;
      var monthlyAdvancePaid = customer.monthlyAdvancePaid;
      var monthlyBalancePaid = customer.monthlyBalancePaid;
      String? pendingDueKind = customer.pendingDueKind;
      int? pendingDueRemaining = customer.pendingDueRemainingRupees;
      var clearPendingDue = false;
      String lastPaymentKind = '';

      if (_initialPaymentOption == _InitialPaymentOption.fullPayment) {
        final fullDue = customer.planPriceRupees;
        final fullPay = initialAmt >= fullDue;
        lastPaymentKind = 'full_payment';
        clearPendingDue = fullPay;

        if (customer.billingPeriod == BillingPeriod.weekly) {
          weeklyPaid = fullPay;
          if (!fullPay) {
            pendingDueKind = PaymentCollectionKind.weeklyFull.name;
            pendingDueRemaining = fullDue - initialAmt;
          }
        } else {
          final fullDue = customer.planPriceRupees;
          if (fullPay) {
            monthlyAdvancePaid = true;
            monthlyBalancePaid = true;
          } else {
            monthlyAdvancePaid = false;
            monthlyBalancePaid = false;
            pendingDueKind = PaymentCollectionKind.monthlyAdvance.name;
            pendingDueRemaining = fullDue - initialAmt;
          }
        }
      } else {
        final kind = switch (_initialPaymentOption) {
          _InitialPaymentOption.weeklyFull => PaymentCollectionKind.weeklyFull,
          _InitialPaymentOption.monthlyFull =>
            PaymentCollectionKind.monthlyAdvance,
          _InitialPaymentOption.fullPayment => PaymentCollectionKind.weeklyFull,
        };
        final scheduledDue = scheduledAmountForKind(customer, kind);
        final fullPay = initialAmt >= scheduledDue;
        lastPaymentKind = kind.name;
        clearPendingDue = fullPay;

        if (kind == PaymentCollectionKind.weeklyFull) {
          weeklyPaid = fullPay;
          if (!fullPay) {
            pendingDueKind = kind.name;
            pendingDueRemaining = scheduledDue - initialAmt;
          }
        } else {
          if (fullPay) {
            monthlyAdvancePaid = true;
            monthlyBalancePaid = true;
          } else {
            monthlyAdvancePaid = false;
            monthlyBalancePaid = false;
            pendingDueKind = kind.name;
            pendingDueRemaining = scheduledDue - initialAmt;
          }
        }
      }

      customer = customer.copyWith(
        paymentTrackedPeriodStart: dateOnly(_startDate),
        weeklyPeriodPaid: weeklyPaid,
        monthlyAdvancePaid: monthlyAdvancePaid,
        monthlyBalancePaid: monthlyBalancePaid,
        lastPaymentAmountRupees: initialAmt,
        lastPaymentAt: DateTime.now(),
        lastPaymentKind: lastPaymentKind,
        clearPendingDue: clearPendingDue,
        pendingDueKind: clearPendingDue ? null : pendingDueKind,
        pendingDueRemainingRupees: clearPendingDue ? null : pendingDueRemaining,
      );
    }

    if (editing != null) {
      await repo.updateCustomer(customer);
    } else {
      await repo.addCustomer(customer);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repo = context.watch<AppRepository>();
    final canAssignAgent = repo.isAdmin;
    final agents = repo.deliveryAgentUsernames;

    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit customer' : 'Add customer'),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Name',
                counterText: '',
              ),
              validator: _validateName,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 22,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: '+91 98765 43210',
                counterText: '',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\s+().-]')),
              ],
              validator: _validatePhone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            Text('Plan', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<BillingPeriod>(
              segments: const [
                ButtonSegment(
                  value: BillingPeriod.weekly,
                  label: Text('Weekly'),
                  icon: Icon(Icons.date_range_outlined),
                ),
                ButtonSegment(
                  value: BillingPeriod.monthly,
                  label: Text('Monthly'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
              ],
              selected: {_billingPeriod},
              onSelectionChanged: (s) {
                final next = s.first;
                setState(() {
                  _billingPeriod = next;
                  final allowed = _allowedInitialPaymentOptions;
                  if (!allowed.contains(_initialPaymentOption)) {
                    _initialPaymentOption = allowed.first;
                  }
                });
              },
            ),
            const SizedBox(height: 4),
            Text(
              _billingPeriod == BillingPeriod.weekly
                  ? '6 delivery days per period (Sunday holiday)'
                  : '26 delivery days per period (Sunday holiday)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ...PlanTier.values.map((tier) {
              final price = planPriceRupees(tier, _billingPeriod);
              final unit =
                  _billingPeriod == BillingPeriod.weekly ? 'week' : 'month';
              final selected = _planTier == tier;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? cs.primaryContainer.withValues(alpha: 0.55)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _planTier = tier),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected ? cs.primary : cs.outline,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tier.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                ),
                                Text('₹$price / $unit'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Start date'),
              subtitle: Text(_dateFmt.format(_startDate)),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar_outlined),
                onPressed: _pickStartDate,
                tooltip: 'Change start date',
              ),
              onTap: _pickStartDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.flag_outlined, color: cs.primary),
              title: const Text('End date (automatic)'),
              subtitle: Text(
                _dateFmt.format(_endDate),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (canAssignAgent) ...[
              DropdownButtonFormField<String?>(
                initialValue: _assignedDeliveryAgentUsername,
                decoration: const InputDecoration(
                  labelText: 'Assign delivery agent (optional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Unassigned'),
                  ),
                  ...agents.map(
                    (u) => DropdownMenuItem<String?>(
                      value: u,
                      child: Text(u),
                    ),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _assignedDeliveryAgentUsername = v),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Preferred slot',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<DeliverySlot>(
              segments: const [
                ButtonSegment(
                  value: DeliverySlot.morning,
                  label: Text('Morning'),
                  icon: Icon(Icons.wb_sunny_outlined),
                ),
                ButtonSegment(
                  value: DeliverySlot.evening,
                  label: Text('Evening'),
                  icon: Icon(Icons.nights_stay_outlined),
                ),
              ],
              selected: {_slot},
              onSelectionChanged: (s) {
                final next = s.first;
                setState(() {
                  _slot = next;
                  final opts = _deliveryWindowsForSlot(next);
                  if (_deliveryTimePreset.isNotEmpty &&
                      _deliveryTimePreset != _kDeliveryTimeOther &&
                      !opts.contains(_deliveryTimePreset)) {
                    _deliveryTimePreset = '';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Requested time of delivery',
                helperText: _slot == DeliverySlot.morning
                    ? 'Morning: 7:00–9:00 AM (15-minute preferences)'
                    : 'Evening: 5:30–7:00 PM (15-minute preferences)',
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _deliveryTimeDropdownValue,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No preference'),
                    ),
                    ..._deliveryWindowsForSlot(_slot).map(
                      (w) => DropdownMenuItem<String>(
                        value: w,
                        child: Text(w),
                      ),
                    ),
                    const DropdownMenuItem<String>(
                      value: _kDeliveryTimeOther,
                      child: Text('Other…'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _deliveryTimePreset = v ?? ''),
                ),
              ),
            ),
            if (_deliveryTimePreset == _kDeliveryTimeOther) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _deliveryTimeCustom,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Describe preferred time',
                  hintText: 'e.g. After 6 PM, before noon',
                  counterText: '',
                ),
                validator: _validateRequestedTimeCustom,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              keyboardType: TextInputType.multiline,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Delivery location (optional)',
                hintText: 'Google Maps link, address, or landmark',
                prefixIcon: Icon(Icons.place_outlined),
                alignLabelWithHint: true,
              ),
              validator: _validateDeliveryLocation,
            ),
            const SizedBox(height: 8),
            Text(
              'Leave blank if unknown. For route distance on the delivery screen, '
              'a Google Maps share link in this field works best.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add initial payment'),
              subtitle: const Text('Optional: record collected amount now'),
              value: _addInitialPayment,
              onChanged: (v) => setState(() => _addInitialPayment = v),
            ),
            if (_addInitialPayment) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<_InitialPaymentOption>(
                initialValue: _allowedInitialPaymentOptions
                        .contains(_initialPaymentOption)
                    ? _initialPaymentOption
                    : _allowedInitialPaymentOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Payment type',
                ),
                items: _allowedInitialPaymentOptions
                    .map(
                      (k) => DropdownMenuItem<_InitialPaymentOption>(
                        value: k,
                        child: Text(_paymentOptionLabel(k)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _initialPaymentOption = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _initialPaymentAmount,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Collected amount (optional)',
                  hintText: 'e.g. 500',
                  prefixText: '₹ ',
                  counterText: '',
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _validateOptionalPaymentAmount,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _notes,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
              ),
              validator: _validateNotes,
            ),
            if (isEditing) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active subscription'),
                subtitle: const Text(
                  'Inactive customers are hidden from delivery routes',
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selected plan total',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '₹$_planPrice / ${_billingPeriod == BillingPeriod.weekly ? "week" : "month"}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(isEditing ? 'Save changes' : 'Save customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
