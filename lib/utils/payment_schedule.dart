import '../models/customer.dart';
import '../models/payment.dart' show PaymentCollectionKind;
import '../models/subscription_plan.dart';
import 'delivery_plan_dates.dart';

/// Used only to interpret legacy Firestore rows where advance was stored separately
/// from balance (older app versions). Not shown as a product rule in the UI.
const int _kLegacyMonthlyAdvanceAssumedRupees = 1000;

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

/// Calendar day to use for payment due / admin adjustments when [today] is not
/// inside the subscription window: first day of subscription if before start,
/// last day if after end; otherwise [today].
///
/// Lets admins correct paid/due for the first or last billing segment when the
/// clock is outside `[startDate, endDate]`.
DateTime paymentScheduleAnchorDate(Customer c, DateTime today) {
  final t = dateOnly(today);
  if (periodStartForDate(c, t) != null) return t;
  final subStart = dateOnly(c.startDate);
  final subEnd = dateOnly(c.endDate);
  if (t.isBefore(subStart)) return subStart;
  if (t.isAfter(subEnd)) return subEnd;
  return subStart;
}

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameDay(DateTime a, DateTime b) => sameCalendarDay(a, b);

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

bool _monthlyPeriodMarkedPaid(Customer c, DateTime periodStart) =>
    effectiveMonthlyAdvancePaid(c, periodStart) &&
    effectiveMonthlyBalancePaid(c, periodStart);

/// Rough credit already applied toward the current monthly period (legacy + partials).
int _monthlyAlreadyCreditedRupees(Customer c, DateTime periodStart) {
  if (_monthlyPeriodMarkedPaid(c, periodStart)) {
    return c.planPriceRupees;
  }

  // Legacy: only “advance” flag set for this period (old two-part monthly).
  if (effectiveMonthlyAdvancePaid(c, periodStart) &&
      !effectiveMonthlyBalancePaid(c, periodStart)) {
    final last = c.lastPaymentAmountRupees;
    final lk = c.lastPaymentKind;
    if (last != null &&
        last > 0 &&
        (lk == PaymentCollectionKind.monthlyAdvance.name ||
            lk == PaymentCollectionKind.monthlyBalance.name)) {
      return last > c.planPriceRupees ? c.planPriceRupees : last;
    }
    const cap = _kLegacyMonthlyAdvanceAssumedRupees;
    return c.planPriceRupees < cap ? c.planPriceRupees : cap;
  }

  return 0;
}

/// True when [recorded] is the collection the UI stored for this due (monthly kinds are interchangeable).
bool collectionKindMatchesDue(
  PaymentCollectionKind recorded,
  PaymentCollectionKind dueKind,
) {
  if (recorded == dueKind) return true;
  const m = {
    PaymentCollectionKind.monthlyAdvance,
    PaymentCollectionKind.monthlyBalance,
  };
  return m.contains(recorded) && m.contains(dueKind);
}

bool _isMonthlyPendingKind(String? k) =>
    k == PaymentCollectionKind.monthlyAdvance.name ||
    k == PaymentCollectionKind.monthlyBalance.name;

/// Single highest-priority due item for [today] (null if nothing due).
({PaymentCollectionKind kind, int amountRupees, String label})?
    paymentDueForCustomer(Customer c, DateTime today) {
  if (!c.active) return null;
  final pStart = periodStartForDate(c, today);
  if (pStart == null) return null;

  if (c.billingPeriod.usesWeeklyStylePayment) {
    if (effectiveWeeklyPaid(c, pStart)) return null;
    if (periodTrackedMatchesPeriodStart(c, pStart) &&
        c.pendingDueKind == PaymentCollectionKind.weeklyFull.name &&
        c.pendingDueRemainingRupees != null &&
        c.pendingDueRemainingRupees! > 0) {
      return (
        kind: PaymentCollectionKind.weeklyFull,
        amountRupees: c.pendingDueRemainingRupees!,
        label: c.billingPeriod == BillingPeriod.trial2Day
            ? '2-day trial'
            : 'Weekly plan',
      );
    }
    return (
      kind: PaymentCollectionKind.weeklyFull,
      amountRupees: c.planPriceRupees,
      label: c.billingPeriod == BillingPeriod.trial2Day
          ? '2-day trial'
          : 'Weekly plan',
    );
  }

  if (_monthlyPeriodMarkedPaid(c, pStart)) return null;

  if (periodTrackedMatchesPeriodStart(c, pStart) &&
      c.pendingDueKind != null &&
      c.pendingDueRemainingRupees != null &&
      c.pendingDueRemainingRupees! > 0 &&
      _isMonthlyPendingKind(c.pendingDueKind)) {
    return (
      kind: PaymentCollectionKind.monthlyAdvance,
      amountRupees: c.pendingDueRemainingRupees!,
      label: 'Monthly plan',
    );
  }

  final credited = _monthlyAlreadyCreditedRupees(c, pStart);
  final due = c.planPriceRupees - credited;
  if (due <= 0) return null;

  return (
    kind: PaymentCollectionKind.monthlyAdvance,
    amountRupees: due,
    label: 'Monthly plan',
  );
}

/// Scheduled rupees for [kind] from plan rules (does not depend on calendar day).
int scheduledAmountForKind(Customer c, PaymentCollectionKind kind) {
  switch (kind) {
    case PaymentCollectionKind.weeklyFull:
      return c.planPriceRupees;
    case PaymentCollectionKind.monthlyAdvance:
    case PaymentCollectionKind.monthlyBalance:
      return c.planPriceRupees;
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
  if (due != null && collectionKindMatchesDue(kind, due.kind)) {
    return due.amountRupees;
  }
  return scheduledAmountForKind(c, kind);
}
