import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/customer.dart';
import '../models/customer_list_filter.dart';
import '../models/delivery_slot.dart';
import '../models/payment.dart';
import '../models/subscription_plan.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/payment_schedule.dart';

/// 30-minute windows for “Requested time of delivery” (morning: 7–9:30 AM).
const _morningDeliveryWindows = <String>[
  '7:00–7:30 AM',
  '7:30–8:00 AM',
  '8:00–8:30 AM',
  '8:30–9:00 AM',
  '9:00–9:30 AM',
];

/// 30-minute windows for evening route (5–7 PM).
const _eveningDeliveryWindows = <String>[
  '5:00–5:30 PM',
  '5:30–6:00 PM',
  '6:00–6:30 PM',
  '6:30–7:00 PM',
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

String? _validateOptionalDiscountedPlanPrice(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return null;
  final n = int.tryParse(t);
  if (n == null) return 'Enter a valid amount in rupees';
  if (n < 1) return 'Amount must be at least ₹1';
  if (n > 99999999) return 'Amount is too large';
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
  /// Optional override; when empty, [planPriceRupees] uses catalog for tier + billing.
  final _discountedPlanPrice = TextEditingController();
  /// Optional override for second plan price.
  final _discountedSecondaryPlanPrice = TextEditingController();
  DeliverySlot _slot = DeliverySlot.morning;

  String _deliveryTimePreset = '';
  bool _strictDeliveryTime = false;

  BillingPeriod _billingPeriod = BillingPeriod.monthly;
  PlanTier _planTier = PlanTier.basic;
  bool _hasSecondaryPlan = false;
  PlanTier _secondaryPlanTier = PlanTier.alkalineInfusedWater1L;
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
      _strictDeliveryTime = e.strictDeliveryTime;
      _applyDeliveryTimeFromCustomer(e);
      final catalog = planPriceRupees(e.planTier, e.billingPeriod);
      if (e.planPriceRupees != catalog) {
        _discountedPlanPrice.text = e.planPriceRupees.toString();
      }
      if (e.secondaryPlanTier != null) {
        _hasSecondaryPlan = true;
        _secondaryPlanTier = e.secondaryPlanTier!;
        final cat2 = planPriceRupees(e.secondaryPlanTier!, e.billingPeriod);
        if (e.secondaryPlanPriceRupees != cat2) {
          _discountedSecondaryPlanPrice.text =
              e.secondaryPlanPriceRupees.toString();
        }
      }
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

  int get _secondaryCatalogPrice =>
      planPriceRupees(_secondaryPlanTier, _billingPeriod);

  /// Saved second-plan price when enabled; else 0.
  int get _effectiveSecondaryPlanPriceRupees {
    if (!_hasSecondaryPlan) return 0;
    final t = _discountedSecondaryPlanPrice.text.trim();
    if (t.isEmpty) return _secondaryCatalogPrice;
    return int.tryParse(t) ?? _secondaryCatalogPrice;
  }

  /// Saved plan price: optional discounted/custom amount, else catalog.
  int get _effectivePlanPriceRupees {
    final t = _discountedPlanPrice.text.trim();
    if (t.isEmpty) return _planPrice;
    return int.tryParse(t) ?? _planPrice;
  }

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
    _discountedPlanPrice.dispose();
    _discountedSecondaryPlanPrice.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<_InitialPaymentOption> get _allowedInitialPaymentOptions {
    if (_billingPeriod.usesWeeklyStylePayment) {
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
    if (_hasSecondaryPlan && _effectiveSecondaryPlanPriceRupees < 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Second plan needs a valid price (at least ₹1), or clear second plan.',
          ),
        ),
      );
      return;
    }
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
      planPriceRupees: _effectivePlanPriceRupees,
      secondaryPlanTier: _hasSecondaryPlan ? _secondaryPlanTier : null,
      secondaryPlanPriceRupees:
          _hasSecondaryPlan ? _effectiveSecondaryPlanPriceRupees : 0,
      startDate: dateOnly(_startDate),
      endDate: _endDate,
      requestedDeliveryTime: time,
      strictDeliveryTime: _strictDeliveryTime,
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
      deletedAt: editing?.deletedAt,
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
        final fullDue = customer.totalPlanPriceRupees;
        final fullPay = initialAmt >= fullDue;
        lastPaymentKind = 'full_payment';
        clearPendingDue = fullPay;

        if (customer.billingPeriod.usesWeeklyStylePayment) {
          weeklyPaid = fullPay;
          if (!fullPay) {
            pendingDueKind = PaymentCollectionKind.weeklyFull.name;
            pendingDueRemaining = fullDue - initialAmt;
          }
        } else {
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
    Navigator.of(context).pop(
      editing == null ? CustomerListFilter.createdPendingApproval : null,
    );
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
                  value: BillingPeriod.trial2Day,
                  label: Text('2-day trial'),
                  icon: Icon(Icons.timer_outlined),
                ),
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
              switch (_billingPeriod) {
                BillingPeriod.trial2Day =>
                  '2 delivery days in the trial (Sunday holiday)',
                BillingPeriod.weekly =>
                  '6 delivery days per period (Sunday holiday)',
                BillingPeriod.monthly =>
                  '26 delivery days per period (Sunday holiday)',
              },
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ...PlanTier.values.map((tier) {
              final price = planPriceRupees(tier, _billingPeriod);
              final unit = _billingPeriod.priceUnitWord;
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _discountedPlanPrice,
              keyboardType: TextInputType.number,
              maxLength: 9,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Discounted plan price (₹, optional)',
                hintText: 'Leave blank for catalog price',
                helperText:
                    'Catalog is ₹$_planPrice / ${_billingPeriod.priceUnitWord}. '
                    'If you enter an amount, that becomes the plan price for '
                    'payments and receipts.',
                prefixText: '₹ ',
                counterText: '',
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _validateOptionalDiscountedPlanPrice,
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Second plan on same subscription'),
              subtitle: const Text(
                'Same billing period; adds another tier for payments and '
                'kitchen pack counts.',
              ),
              value: _hasSecondaryPlan,
              onChanged: (v) => setState(() {
                _hasSecondaryPlan = v;
                if (!v) _discountedSecondaryPlanPrice.clear();
              }),
            ),
            if (_hasSecondaryPlan) ...[
              const SizedBox(height: 4),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Second plan tier',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PlanTier>(
                    isExpanded: true,
                    value: _secondaryPlanTier,
                    items: PlanTier.values
                        .map(
                          (tier) => DropdownMenuItem<PlanTier>(
                            value: tier,
                            child: Text(
                              '${tier.title} — '
                              '₹${planPriceRupees(tier, _billingPeriod)}/'
                              '${_billingPeriod.priceUnitWord}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _secondaryPlanTier = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _discountedSecondaryPlanPrice,
                keyboardType: TextInputType.number,
                maxLength: 9,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Second plan price (₹, optional)',
                  hintText: 'Leave blank for catalog price',
                  helperText:
                      'Catalog is ₹$_secondaryCatalogPrice / ${_billingPeriod.priceUnitWord}',
                  prefixText: '₹ ',
                  counterText: '',
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _validateOptionalDiscountedPlanPrice,
              ),
            ],
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
                    ? 'Morning: 7:00–9:30 AM (30-minute windows)'
                    : 'Evening: 5:00–7:00 PM (30-minute windows)',
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.schedule,
                color: _strictDeliveryTime ? cs.error : cs.onSurfaceVariant,
              ),
              title: const Text('Strict delivery time'),
              subtitle: const Text(
                'Delivery should occur within the requested window. '
                'Shows a red indicator on the route and customer list.',
              ),
              value: _strictDeliveryTime,
              onChanged: (v) => setState(() => _strictDeliveryTime = v),
            ),
            const SizedBox(height: 8),
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
                            'Plan price',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            'Catalog: ₹$_planPrice / ${_billingPeriod.priceUnitWord}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                          if (_discountedPlanPrice.text.trim().isNotEmpty &&
                              _effectivePlanPriceRupees != _planPrice) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Primary saved: ₹$_effectivePlanPriceRupees / ${_billingPeriod.priceUnitWord}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                            ),
                          ] else ...[
                            const SizedBox(height: 2),
                            Text(
                              'Primary: ₹$_effectivePlanPriceRupees / ${_billingPeriod.priceUnitWord}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                          if (_hasSecondaryPlan) ...[
                            const SizedBox(height: 4),
                            Text(
                              '+ ${_secondaryPlanTier.title} · '
                              '₹$_effectiveSecondaryPlanPriceRupees / ${_billingPeriod.priceUnitWord}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'Total / ${_billingPeriod.priceUnitWord}: '
                            '₹${_effectivePlanPriceRupees + (_hasSecondaryPlan ? _effectiveSecondaryPlanPriceRupees : 0)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
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
