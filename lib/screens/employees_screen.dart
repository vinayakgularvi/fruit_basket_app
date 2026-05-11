import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_repository.dart';
import '../models/employee.dart';
import '../utils/employee_payroll.dart';
import '../utils/whatsapp_launch.dart';
import 'add_edit_employee_screen.dart';

String _nameInitial(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return t.substring(0, 1).toUpperCase();
}

Future<void> _confirmDeleteEmployee(BuildContext context, Employee employee) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete employee?'),
      content: Text(
        'Remove ${employee.name.trim().isEmpty ? 'this employee' : employee.name} '
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
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await context.read<AppRepository>().deleteEmployee(employee.id);
    if (!context.mounted) return;
    messenger?.showSnackBar(
      SnackBar(content: Text('${employee.name} removed')),
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not delete: $e')),
    );
  }
}

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final employees = repo.employees;
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final df = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Employees'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => const AddEditEmployeeScreen(),
            ),
          );
          if (ok == true && context.mounted) {
            await context.read<AppRepository>().refreshEmployees();
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add employee'),
      ),
      body: repo.employeesLoading && employees.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => repo.refreshEmployees(),
              child: employees.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.badge_outlined, size: 48),
                        SizedBox(height: 16),
                        Center(
                          child: Text(
                            'No employees yet.\nTap “Add employee” to create one.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: employees.length,
                      itemBuilder: (context, i) {
                        final e = employees[i];
                        return _EmployeeCard(
                          employee: e,
                          currency: currency,
                          dateFmt: df,
                          onDelete: () => _confirmDeleteEmployee(context, e),
                          onTap: () async {
                            final result = await Navigator.of(context).push<
                                Object?>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AddEditEmployeeScreen(editing: e),
                              ),
                            );
                            if (!context.mounted) return;
                            if (result == 'deleted') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.name.trim().isEmpty
                                        ? 'Employee removed'
                                        : '${e.name} removed',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (result == true) {
                              await context
                                  .read<AppRepository>()
                                  .refreshEmployees();
                            }
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.currency,
    required this.dateFmt,
    required this.onDelete,
    required this.onTap,
  });

  final Employee employee;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payroll = monthlyPayrollBreakdown(employee, DateTime.now());
    final monthFmt = DateFormat.yMMM();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          foregroundColor: cs.onPrimaryContainer,
                          child: Text(_nameInitial(employee.name)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                employee.mobile,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      employee.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            'Started ${dateFmt.format(employee.startDate)}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            Icons.event_busy_outlined,
                            size: 16,
                            color: cs.error,
                          ),
                          label: Text(
                            '${employee.absentDates.length} absent',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _MoneyLine(
                            label: 'Salary',
                            value: currency.format(employee.salaryRupees),
                          ),
                        ),
                        Expanded(
                          child: _MoneyLine(
                            label: 'Incentive',
                            value: currency.format(employee.incentiveRupees),
                          ),
                        ),
                        Expanded(
                          child: _MoneyLine(
                            label: 'Gross',
                            value: currency.format(employee.totalSalaryRupees),
                            emphasize: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Payable · ${monthFmt.format(DateTime(payroll.year, payroll.month))}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${payroll.presentWorkingDays}/${payroll.workingDaysInMonth} payable days '
                              '(−${payroll.absentDaysAppliedForPayroll} absent)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                            if (payroll.absenceMarkedExceedsMonthlyBasis)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${payroll.absentWorkingDaysInMonth} marked absent '
                                  '(payroll caps at ${payroll.workingDaysInMonth} days)',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              currency.format(payroll.payableTotalRupees),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onTertiaryContainer,
                              ),
                              textAlign: TextAlign.end,
                            ),
                            if (payroll.deductedRupees > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'After −${currency.format(payroll.deductedRupees)} absence deduction',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4, end: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'WhatsApp — Kannada details',
                  icon: Icon(Icons.chat_rounded, color: cs.primary),
                  onPressed: () =>
                      openEmployeeDetailsWhatsAppKannada(context, employee),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valueStyle =
        (emphasize ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? cs.primary : null,
            );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: valueStyle,
          ),
        ],
      ),
    );
  }
}
