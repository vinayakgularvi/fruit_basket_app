import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/employee.dart';
import '../utils/delivery_plan_dates.dart';
import '../utils/employee_payroll.dart';
import '../utils/whatsapp_launch.dart';

class AddEditEmployeeScreen extends StatefulWidget {
  const AddEditEmployeeScreen({super.key, this.editing});

  final Employee? editing;

  @override
  State<AddEditEmployeeScreen> createState() => _AddEditEmployeeScreenState();
}

class _AddEditEmployeeScreenState extends State<AddEditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _mobile;
  late TextEditingController _address;
  late TextEditingController _salary;
  late TextEditingController _incentive;
  late DateTime _startDate;
  late Employee _model;
  late final VoidCallback _bumpPayPreview;

  bool get _isNew => widget.editing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing ?? Employee.empty();
    _model = e;
    _name = TextEditingController(text: e.name);
    _mobile = TextEditingController(text: e.mobile);
    _address = TextEditingController(text: e.address);
    _salary = TextEditingController(text: e.salaryRupees > 0 ? '${e.salaryRupees}' : '');
    _incentive = TextEditingController(
      text: e.incentiveRupees > 0 ? '${e.incentiveRupees}' : '',
    );
    _startDate = dateOnly(e.startDate);
    _bumpPayPreview = () {
      if (mounted) setState(() {});
    };
    _salary.addListener(_bumpPayPreview);
    _incentive.addListener(_bumpPayPreview);
  }

  @override
  void dispose() {
    _salary.removeListener(_bumpPayPreview);
    _incentive.removeListener(_bumpPayPreview);
    _name.dispose();
    _mobile.dispose();
    _address.dispose();
    _salary.dispose();
    _incentive.dispose();
    super.dispose();
  }

  int _parseMoney(String raw) {
    final s = raw.trim().replaceAll(',', '');
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? 0;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => _startDate = dateOnly(picked));
    }
  }

  Future<void> _pickAbsentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOnly(DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final day = dateOnly(picked);
    final dates = _model.absentDates.map(dateOnly).toList();
    if (dates.any(
      (x) =>
          x.year == day.year && x.month == day.month && x.day == day.day,
    )) {
      return;
    }
    dates.add(day);
    dates.sort();
    setState(() => _model = _model.copyWith(absentDates: dates));
  }

  Employee _draftFromForm() {
    return _model.copyWith(
      name: _name.text.trim(),
      mobile: _mobile.text.trim(),
      address: _address.text.trim(),
      startDate: _startDate,
      salaryRupees: _parseMoney(_salary.text),
      incentiveRupees: _parseMoney(_incentive.text),
    );
  }

  void _sendWhatsAppKannada() {
    openEmployeeDetailsWhatsAppKannada(context, _draftFromForm());
  }

  void _removeAbsent(DateTime day) {
    final d = dateOnly(day);
    final dates = _model.absentDates
        .map(dateOnly)
        .where(
          (x) =>
              !(x.year == d.year && x.month == d.month && x.day == d.day),
        )
        .toList();
    setState(() => _model = _model.copyWith(absentDates: dates));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = context.read<AppRepository>();
    final messenger = ScaffoldMessenger.maybeOf(context);

    final salary = _parseMoney(_salary.text);
    final incentive = _parseMoney(_incentive.text);
    final draft = _model.copyWith(
      name: _name.text.trim(),
      mobile: _mobile.text.trim(),
      address: _address.text.trim(),
      startDate: _startDate,
      salaryRupees: salary,
      incentiveRupees: incentive,
    );

    try {
      if (_isNew) {
        await repo.addEmployee(draft);
      } else {
        await repo.updateEmployee(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    if (_isNew) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete employee?'),
        content: Text(
          'Remove ${_name.text.trim().isEmpty ? 'this employee' : _name.text.trim()} '
          'from the list? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<AppRepository>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await repo.deleteEmployee(_model.id);
      if (!mounted) return;
      Navigator.of(context).pop('deleted');
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final df = DateFormat.yMMMd();
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final previewSalary = _parseMoney(_salary.text);
    final previewIncentive = _parseMoney(_incentive.text);
    final previewTotal = previewSalary + previewIncentive;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New employee' : 'Edit employee'),
        actions: [
          IconButton(
            tooltip: 'WhatsApp — Kannada details',
            icon: Icon(Icons.chat_rounded, color: cs.primary),
            onPressed: _sendWhatsAppKannada,
          ),
          if (!_isNew)
            IconButton(
              tooltip: 'Delete employee',
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: _confirmDelete,
            ),
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter name';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().length < 10) {
                  return 'Enter a valid mobile number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Address',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter address';
                return null;
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start date'),
              subtitle: Text(df.format(_startDate)),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: _pickStartDate,
              ),
            ),
            const Divider(height: 32),
            Text(
              'Pay (monthly)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _salary,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Salary',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _incentive,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Incentive',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (_parseMoney(v ?? '') < 0) return 'Enter 0 or more';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monthly gross',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currency.format(previewTotal),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            '${currency.format(previewSalary)} salary + '
                            '${currency.format(previewIncentive)} incentive',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Text(
                  'Absence',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickAbsentDate,
                  icon: const Icon(Icons.event_busy, size: 20),
                  label: const Text('Mark absent'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_model.absentDates.length} day(s) marked absent',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in List<DateTime>.from(_model.absentDates)
                  ..sort((a, b) => b.compareTo(a)))
                  InputChip(
                    label: Text(df.format(dateOnly(d))),
                    onDeleted: () => _removeAbsent(d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (_) {
                final preview = _model.copyWith(
                  salaryRupees: previewSalary,
                  incentiveRupees: previewIncentive,
                );
                final pay = monthlyPayrollBreakdown(preview, DateTime.now());
                final monthFmt = DateFormat.yMMM();
                return Card(
                  color: cs.tertiaryContainer.withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payable this month '
                          '(${monthFmt.format(DateTime(pay.year, pay.month))})',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Pay uses ${pay.workingDaysInMonth} working days per month. '
                          'Each absent Mon–Sat day in this calendar month reduces '
                          'pay; Sundays are not counted as absence.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${pay.presentWorkingDays}/${pay.workingDaysInMonth} payable days '
                          '(−${pay.absentDaysAppliedForPayroll} absent)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (pay.absenceMarkedExceedsMonthlyBasis)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${pay.absentWorkingDaysInMonth} marked absent · '
                              'only ${pay.workingDaysInMonth} can reduce this month’s pay',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          currency.format(pay.payableTotalRupees),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onTertiaryContainer,
                          ),
                        ),
                        Text(
                          '${currency.format(pay.payableSalaryRupees)} salary + '
                          '${currency.format(pay.payableIncentiveRupees)} incentive',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onTertiaryContainer,
                          ),
                        ),
                        if (pay.deductedRupees > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Absence deduction: '
                              '−${currency.format(pay.deductedRupees)}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: cs.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
