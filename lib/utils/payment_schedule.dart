import '../models/customer.dart';
import '../models/payment.dart' show PaymentCollectionKind;
import '../models/subscription_plan.dart';
import 'delivery_plan_dates.dart';

/// Monthly: ₹1000 advance on first delivery day; balance after 20 calendar days.
const int monthlyAdvanceRupees = 1000;
const int monthlyBalanceDueAfterDays = 20;

/// First calendar day after [periodEnd] that is a delivery day (not Sunday).
DateTime nextPeriodStartAfter(DateTime periodEnd) {
  var d = dateOnly(periodEnd).add(const Duration(days: 1));
  while (d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// Billing period that contains [today], or null if outside subscription.
DateTime? periodStartForDate(Customer c, DateTime today) {
  final t = dateOnly(today);
  final subStart = dateOnly(c.startDate);
  final subEnd = dateOnly(c.endDate);
  if (t.isBefore(subStart) || t.isAfter(subEnd)) return null;

  var pStart = subStart;
  while (true) {
    final naturalEnd = endDateForBilling(pStart, c.billingPeriod);
    final periodEnd = naturalEnd.isAfter(subEnd) ? subEnd : naturalEnd;
    if (!t.isBefore(pStart) && !t.isAfter(periodEnd)) return pStart;
    if (periodEnd == subEnd) return null;
    pStart = nextPeriodStartAfter(periodEnd);
    if (pStart.isAfter(subEnd)) return null;
  }
}

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameDay(DateTime a, DateTime b) => sameCalendarDay(a, b);

int _daysBetween(DateTime from, DateTime to) {
  final a = dateOnly(from);
  final b = dateOnly(to);
  return b.difference(a).inDays;
}

/// Advance (capped) and remaining balance for monthly plan.
(int advance, int balance) monthlySplitAmounts(int planPriceRupees) {
  final adv = planPriceRupees < monthlyAdvanceRupees
      ? planPriceRupees
      : monthlyAdvanceRupees;
  final bal = planPriceRupees - adv;
  return (adv, bal < 0 ? 0 : bal);
}

/// Effective payment flags for [periodStart] (resets when period changes in storage).
bool effectiveWeeklyPaid(Customer c, DateTime periodStart) {
  final tracked = c.paymentTrackedPeriodStart;
  if (tracked == null) return false;
  if (!_sameDay(dateOnly(tracked), dateOnly(periodStart))) return false;
  return c.weeklyPeriodPaid;
}

bool effectiveMonthlyAdvancePaid(Customer c, DateTime periodStart) {
  final tracked = c.paymentTrackedPeriodStart;
  if (tracked == null) return false;
  if (!_sameDay(dateOnly(tracked), dateOnly(periodStart))) return false;
  return c.monthlyAdvancePaid;
}

bool effectiveMonthlyBalancePaid(Customer c, DateTime periodStart) {
  final tracked = c.paymentTrackedPeriodStart;
  if (tracked == null) return false;
  if (!_sameDay(dateOnly(tracked), dateOnly(periodStart))) return false;
  return c.monthlyBalancePaid;
}

/// [paymentTrackedPeriodStart] aligns with this billing period’s [pStart].
bool periodTrackedMatchesPeriodStart(Customer c, DateTime pStart) {
  final tr = c.paymentTrackedPeriodStart;
  if (tr == null) return false;
  return _sameDay(dateOnly(tr), dateOnly(pStart));
}

/// Payment due on the **next calendar day** after [today] (if subscription covers it).
({PaymentCollectionKind kind, int amountRupees, String label})?
    paymentDueForNextCalendarDay(Customer c, DateTime today) {
  final next = dateOnly(today).add(const Duration(days: 1));
  return paymentDueForCustomer(c, next);
}

/// Single highest-priority due item for [today] (null if nothing due).
({PaymentCollectionKind kind, int amountRupees, String label})?
    paymentDueForCustomer(Customer c, DateTime today) {
  if (!c.active) return null;
  final pStart = periodStartForDate(c, today);
  if (pStart == null) return null;
  final t = dateOnly(today);

  if (c.billingPeriod == BillingPeriod.weekly) {
    if (effectiveWeeklyPaid(c, pStart)) return null;
    if (periodTrackedMatchesPeriodStart(c, pStart) &&
        c.pendingDueKind == PaymentCollectionKind.weeklyFull.name &&
        c.pendingDueRemainingRupees != null &&
        c.pendingDueRemainingRupees! > 0) {
      return (
        kind: PaymentCollectionKind.weeklyFull,
        amountRupees: c.pendingDueRemainingRupees!,
        label: 'Weekly plan (remaining)',
      );
    }
    return (
      kind: PaymentCollectionKind.weeklyFull,
      amountRupees: c.planPriceRupees,
      label: _sameDay(t, pStart)
          ? 'Weekly plan (first delivery day)'
          : 'Weekly plan (due this period)',
    );
  }

  final (adv, bal) = monthlySplitAmounts(c.planPriceRupees);
  final daysSinceStart = _daysBetween(pStart, t);
  final advancePaid = effectiveMonthlyAdvancePaid(c, pStart);
  final balancePaid = effectiveMonthlyBalancePaid(c, pStart);

  if (adv > 0 && !advancePaid) {
    final usePending = periodTrackedMatchesPeriodStart(c, pStart) &&
        c.pendingDueKind == PaymentCollectionKind.monthlyAdvance.name &&
        c.pendingDueRemainingRupees != null &&
        c.pendingDueRemainingRupees! > 0;
    final amt = usePending ? c.pendingDueRemainingRupees! : adv;
    return (
      kind: PaymentCollectionKind.monthlyAdvance,
      amountRupees: amt,
      label: usePending
          ? 'Monthly advance (remaining)'
          : (_sameDay(t, pStart)
              ? 'Monthly advance (first delivery day)'
              : 'Monthly advance (due)'),
    );
  }

  if (bal > 0 &&
      !balancePaid &&
      daysSinceStart >= monthlyBalanceDueAfterDays &&
      (adv == 0 || advancePaid)) {
    final usePending = periodTrackedMatchesPeriodStart(c, pStart) &&
        c.pendingDueKind == PaymentCollectionKind.monthlyBalance.name &&
        c.pendingDueRemainingRupees != null &&
        c.pendingDueRemainingRupees! > 0;
    final amt = usePending ? c.pendingDueRemainingRupees! : bal;
    return (
      kind: PaymentCollectionKind.monthlyBalance,
      amountRupees: amt,
      label: usePending
          ? 'Monthly balance (remaining)'
          : 'Monthly balance (day $monthlyBalanceDueAfterDays+)',
    );
  }

  return null;
}

/// Scheduled rupees for [kind] from plan rules (does not depend on calendar day).
int scheduledAmountForKind(Customer c, PaymentCollectionKind kind) {
  switch (kind) {
    case PaymentCollectionKind.weeklyFull:
      return c.planPriceRupees;
    case PaymentCollectionKind.monthlyAdvance:
      return monthlySplitAmounts(c.planPriceRupees).$1;
    case PaymentCollectionKind.monthlyBalance:
      return monthlySplitAmounts(c.planPriceRupees).$2;
  }
}

/// Amount to assume when marking [kind] paid without a custom value: prefer
/// today’s [paymentDueForCustomer] if it matches [kind], else [scheduledAmountForKind].
int defaultCollectionAmountRupees(
  Customer c,
  PaymentCollectionKind kind,
  DateTime today,
) {
  final due = paymentDueForCustomer(c, today);
  if (due != null && due.kind == kind) return due.amountRupees;
  return scheduledAmountForKind(c, kind);
}
