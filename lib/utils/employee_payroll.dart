import '../models/employee.dart';
import 'delivery_plan_dates.dart';

/// Fixed working-day basis for monthly payroll (not calendar length).
const int kPayrollWorkingDaysPerMonth = 30;

/// Sundays treated as non-working for counting **absence** only.
bool _isWorkingDay(DateTime d) => d.weekday != DateTime.sunday;

/// Absences in [year]/[month] that fall on working days (Mon–Sat).
/// Used against [kPayrollWorkingDaysPerMonth] for pro-rating.
int absentWorkingDaysInCalendarMonth(Employee e, int year, int month) {
  var n = 0;
  for (final raw in e.absentDates) {
    final a = dateOnly(raw);
    if (a.year != year || a.month != month) continue;
    if (_isWorkingDay(a)) n++;
  }
  return n;
}

/// Monthly gross split into payable amounts after absence-based pro-rating.
///
/// Uses **30 working days** per month as the denominator. Each rupee bucket
/// (salary, incentive) is multiplied by `(present days) / 30` and rounded.
/// [absentWorkingDaysInMonth] is Mon–Sat absence marks in that calendar month (may exceed 30);
/// pay reduction uses [absentDaysAppliedForPayroll] (capped at 30).
class MonthlyPayrollBreakdown {
  const MonthlyPayrollBreakdown({
    required this.year,
    required this.month,
    required this.workingDaysInMonth,
    required this.absentWorkingDaysInMonth,
    required this.presentWorkingDays,
    required this.grossSalaryRupees,
    required this.grossIncentiveRupees,
    required this.payableSalaryRupees,
    required this.payableIncentiveRupees,
  });

  final int year;
  final int month;
  /// Always [kPayrollWorkingDaysPerMonth] for the formula denominator.
  final int workingDaysInMonth;
  final int absentWorkingDaysInMonth;
  final int presentWorkingDays;
  final int grossSalaryRupees;
  final int grossIncentiveRupees;
  final int payableSalaryRupees;
  final int payableIncentiveRupees;

  int get grossTotalRupees => grossSalaryRupees + grossIncentiveRupees;
  int get payableTotalRupees => payableSalaryRupees + payableIncentiveRupees;
  int get deductedRupees => grossTotalRupees - payableTotalRupees;

  /// Absence marks that actually reduce pay (at most [workingDaysInMonth]).
  int get absentDaysAppliedForPayroll =>
      absentWorkingDaysInMonth.clamp(0, workingDaysInMonth);

  bool get absenceMarkedExceedsMonthlyBasis =>
      absentWorkingDaysInMonth > workingDaysInMonth;
}

/// Pro-rated pay for the calendar month containing [monthAnyDay].
MonthlyPayrollBreakdown monthlyPayrollBreakdown(
  Employee e,
  DateTime monthAnyDay,
) {
  final y = monthAnyDay.year;
  final m = monthAnyDay.month;
  const wd = kPayrollWorkingDaysPerMonth;
  final absentRaw = absentWorkingDaysInCalendarMonth(e, y, m);
  final absent = absentRaw.clamp(0, wd);
  final present = wd - absent;
  final salary = e.salaryRupees;
  final incentive = e.incentiveRupees;

  final payableSalary = ((salary * present) / wd).round();
  final payableIncentive = ((incentive * present) / wd).round();

  return MonthlyPayrollBreakdown(
    year: y,
    month: m,
    workingDaysInMonth: wd,
    absentWorkingDaysInMonth: absentRaw,
    presentWorkingDays: present,
    grossSalaryRupees: salary,
    grossIncentiveRupees: incentive,
    payableSalaryRupees: payableSalary,
    payableIncentiveRupees: payableIncentive,
  );
}
