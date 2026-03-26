/// Fruit Basket subscription tiers and billing.
enum PlanTier {
  basic,
  standard,
  premium,
}

extension PlanTierLabel on PlanTier {
  String get title => switch (this) {
        PlanTier.basic => 'Basic Fruit Plan',
        PlanTier.standard => 'Standard Healthy Plan',
        PlanTier.premium => 'Premium Nutrition Plan',
      };
}

enum BillingPeriod {
  weekly,
  monthly,
}

extension BillingPeriodLabel on BillingPeriod {
  String get title => switch (this) {
        BillingPeriod.weekly => 'Week',
        BillingPeriod.monthly => 'Month',
      };

  /// Delivery days in the period (Sundays excluded elsewhere).
  int get deliveryDays => switch (this) {
        BillingPeriod.weekly => 6,
        BillingPeriod.monthly => 26,
      };
}

/// Approximate monthly rupees from a customer's stored [planPriceRupees] and
/// [billingPeriod] (weekly scaled by delivery-day ratio 26/6 vs monthly).
int planPriceToApproximateMonthlyRupees({
  required int planPriceRupees,
  required BillingPeriod billingPeriod,
}) {
  switch (billingPeriod) {
    case BillingPeriod.monthly:
      return planPriceRupees;
    case BillingPeriod.weekly:
      final w = BillingPeriod.weekly.deliveryDays;
      final m = BillingPeriod.monthly.deliveryDays;
      return ((planPriceRupees * m) / w).round();
  }
}

/// Price in rupees (whole) for the given tier and period.
int planPriceRupees(PlanTier tier, BillingPeriod period) {
  if (period == BillingPeriod.weekly) {
    return switch (tier) {
      PlanTier.basic => 343,
      PlanTier.standard => 553,
      PlanTier.premium => 833,
    };
  }
  return switch (tier) {
    PlanTier.basic => 1299,
    PlanTier.standard => 2199,
    PlanTier.premium => 2999,
  };
}
