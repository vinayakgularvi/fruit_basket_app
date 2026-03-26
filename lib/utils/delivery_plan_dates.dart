import '../models/subscription_plan.dart';

/// Normalizes to date-only (local).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
