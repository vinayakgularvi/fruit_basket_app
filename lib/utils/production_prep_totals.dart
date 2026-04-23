import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../models/subscription_plan.dart';
import 'delivery_plan_dates.dart';

/// Kitchen pack lines: Basic → Small, Standard → Medium, Premium → Large,
/// Alkaline water → Alkaline; combo tiers add fruit + alkaline counts.
enum ProductionPackBucket {
  small,
  medium,
  large,
  alkaline,
}

extension ProductionPackBucketLabel on ProductionPackBucket {
  /// Plan-oriented labels (matches [PlanTier.title] groupings for the kitchen).
  String get shortLabel => switch (this) {
        ProductionPackBucket.small => 'Basic fruit plan',
        ProductionPackBucket.medium => 'Standard healthy plan',
        ProductionPackBucket.large => 'Premium nutrition plan',
        ProductionPackBucket.alkaline => 'Alkaline (1 L)',
      };
}

bool _isDeliveryCalendarDay(DateTime day) =>
    dateOnly(day).weekday != DateTime.sunday;

bool _subscriptionCoversDate(Customer c, DateTime day) {
  final d = dateOnly(day);
  final start = dateOnly(c.startDate);
  final end = dateOnly(c.endDate);
  return !d.isBefore(start) && !d.isAfter(end);
}

/// Active customers in [slot] on a delivery calendar day in range, not skipped.
/// Same inclusion as delivery routes (no extra admin-approval filter).
bool isCustomerCountedForProductionPrep(
  Customer c,
  DateTime calendarDay,
  DeliverySlot slot,
) {
  if (!c.active) return false;
  if (c.preferredSlot != slot) return false;
  final d = dateOnly(calendarDay);
  if (!_isDeliveryCalendarDay(d)) return false;
  if (!_subscriptionCoversDate(c, d)) return false;
  if (customerSkipsDeliveryOnDate(c, d)) return false;
  return true;
}

void addPlanTierToPackCounts(
  PlanTier tier,
  Map<ProductionPackBucket, int> counts,
) {
  void bump(ProductionPackBucket b) {
    counts[b] = (counts[b] ?? 0) + 1;
  }

  switch (tier) {
    case PlanTier.basic:
      bump(ProductionPackBucket.small);
    case PlanTier.standard:
      bump(ProductionPackBucket.medium);
    case PlanTier.premium:
      bump(ProductionPackBucket.large);
    case PlanTier.alkalineInfusedWater1L:
      bump(ProductionPackBucket.alkaline);
    case PlanTier.comboBasicAlkaline:
      bump(ProductionPackBucket.small);
      bump(ProductionPackBucket.alkaline);
    case PlanTier.comboStandardAlkaline:
      bump(ProductionPackBucket.medium);
      bump(ProductionPackBucket.alkaline);
    case PlanTier.comboPremiumAlkaline:
      bump(ProductionPackBucket.large);
      bump(ProductionPackBucket.alkaline);
  }
}

Map<ProductionPackBucket, int> productionPackCountsForDaySlot(
  Iterable<Customer> customers,
  DateTime calendarDay,
  DeliverySlot slot,
) {
  final out = <ProductionPackBucket, int>{};
  for (final c in customers) {
    if (!isCustomerCountedForProductionPrep(c, calendarDay, slot)) continue;
    addPlanTierToPackCounts(c.planTier, out);
    final sec = c.secondaryPlanTier;
    if (sec != null) {
      addPlanTierToPackCounts(sec, out);
    }
  }
  return out;
}

/// First calendar day strictly after [from] (date-only) that is not Sunday.
DateTime nextNonSundayAfter(DateTime from) {
  var d = dateOnly(from).add(const Duration(days: 1));
  while (d.weekday == DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// Which day/slot the home “pack” strip should show from local [now].
///
/// - Before 11:00 → today **morning** slot.
/// - From 11:00 to before 20:00 → today **evening** slot.
/// - From 20:00 onward → **next** delivery-day **morning** (skips Sunday).
class ProductionPrepScheduleView {
  const ProductionPrepScheduleView({
    required this.title,
    required this.calendarDay,
    required this.slot,
  });

  final String title;
  final DateTime calendarDay;
  final DeliverySlot slot;
}

ProductionPrepScheduleView resolveProductionPrepScheduleView(DateTime now) {
  final today = dateOnly(now);
  final h = now.hour;

  if (h >= 20) {
    final day = nextNonSundayAfter(now);
    return ProductionPrepScheduleView(
      title: 'Next morning — pack',
      calendarDay: day,
      slot: DeliverySlot.morning,
    );
  }

  if (h >= 11) {
    return ProductionPrepScheduleView(
      title: 'This evening — pack',
      calendarDay: today,
      slot: DeliverySlot.evening,
    );
  }

  return ProductionPrepScheduleView(
    title: 'This morning — pack',
    calendarDay: today,
    slot: DeliverySlot.morning,
  );
}

int totalPackUnits(Map<ProductionPackBucket, int> counts) =>
    counts.values.fold(0, (a, b) => a + b);
