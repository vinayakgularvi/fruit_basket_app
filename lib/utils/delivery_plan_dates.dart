import '../models/customer.dart';
import '../models/subscription_plan.dart';

/// Normalizes to date-only (local).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// True when [calendarDay] is in [c.skippedDeliveryDates] (date-only match).
bool customerSkipsDeliveryOnDate(Customer c, DateTime calendarDay) {
  final d = dateOnly(calendarDay);
  for (final s in c.skippedDeliveryDates) {
    if (dateOnly(s) == d) return true;
  }
  return false;
}

/// [Customer.endDate] is today (calendar) and the customer is active.
bool subscriptionLastDayToday(Customer c) {
  if (!c.active) return false;
  final t = dateOnly(DateTime.now());
  final e = dateOnly(c.endDate);
  return t.year == e.year && t.month == e.month && t.day == e.day;
}

/// Puts subscription last-day stops first; keeps relative order within each group.
List<Customer> prioritizeSubscriptionLastDay(List<Customer> ordered) {
  final first = <Customer>[];
  final rest = <Customer>[];
  for (final c in ordered) {
    if (subscriptionLastDayToday(c)) {
      first.add(c);
    } else {
      rest.add(c);
    }
  }
  return [...first, ...rest];
}

/// Last calendar day of the plan after [deliveryDaysNeeded] delivery days.
/// Sundays are non-delivery days (holiday).
DateTime endDateAfterDeliveryDays(DateTime start, int deliveryDaysNeeded) {
  assert(deliveryDaysNeeded > 0);
  var d = dateOnly(start);
  var count = 0;
  while (true) {
    if (d.weekday != DateTime.sunday) {
      count++;
      if (count == deliveryDaysNeeded) return d;
    }
    d = d.add(const Duration(days: 1));
  }
}

/// Convenience using [BillingPeriod.deliveryDays].
DateTime endDateForBilling(DateTime start, BillingPeriod period) {
  return endDateAfterDeliveryDays(start, period.deliveryDays);
}
