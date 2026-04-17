/// Fruit Basket subscription tiers and billing.
enum PlanTier {
  basic,
  standard,
  premium,
  alkalineInfusedWater1L,
  comboBasicAlkaline,
  comboStandardAlkaline,
  comboPremiumAlkaline,
}

extension PlanTierLabel on PlanTier {
  String get title => switch (this) {
        PlanTier.basic => 'Basic Fruit Plan',
        PlanTier.standard => 'Standard Healthy Plan',
        PlanTier.premium => 'Premium Nutrition Plan',
        PlanTier.alkalineInfusedWater1L =>
          'Alkaline Infused Water (1 L bottle)',
        PlanTier.comboBasicAlkaline => 'Combo Basic + Alkaline',
        PlanTier.comboStandardAlkaline => 'Combo Standard + Alkaline',
        PlanTier.comboPremiumAlkaline => 'Combo Premium + Alkaline',
      };
}

enum BillingPeriod {
  weekly,
  monthly,
  /// Two delivery days (Sunday holiday logic still applies from [startDate]).
  trial2Day,
}

extension BillingPeriodLabel on BillingPeriod {
  String get title => switch (this) {
        BillingPeriod.weekly => 'Week',
        BillingPeriod.monthly => 'Month',
        BillingPeriod.trial2Day => '2-day trial',
      };

  /// Delivery days in the period (Sundays excluded elsewhere).
  int get deliveryDays => switch (this) {
        BillingPeriod.weekly => 6,
        BillingPeriod.monthly => 26,
        BillingPeriod.trial2Day => 2,
      };

  /// Weekly-style single payment per billing window (vs monthly advance/balance).
  bool get usesWeeklyStylePayment =>
      this == BillingPeriod.weekly || this == BillingPeriod.trial2Day;

  /// Short label for lists (e.g. ₹…/wk).
  String get priceUnitWord => switch (this) {
        BillingPeriod.weekly => 'week',
        BillingPeriod.monthly => 'month',
        BillingPeriod.trial2Day => '2-day trial',
      };

  String get listAbbrev => switch (this) {
        BillingPeriod.weekly => 'wk',
        BillingPeriod.monthly => 'mo',
        BillingPeriod.trial2Day => '2d',
      };

  /// Noun for dialogs (“Add one …”).
  String get periodNoun => switch (this) {
        BillingPeriod.weekly => 'week',
        BillingPeriod.monthly => 'month',
        BillingPeriod.trial2Day => '2-day trial',
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
    case BillingPeriod.trial2Day:
      final t = BillingPeriod.trial2Day.deliveryDays;
      final m = BillingPeriod.monthly.deliveryDays;
      return ((planPriceRupees * m) / t).round();
  }
}

/// Price in rupees (whole) for the given tier and period.
int planPriceRupees(PlanTier tier, BillingPeriod period) {
  return switch (period) {
    BillingPeriod.trial2Day => switch (tier) {
        PlanTier.basic => 148,
        PlanTier.standard => 218,
        PlanTier.premium => 311,
        PlanTier.alkalineInfusedWater1L => 148,
        PlanTier.comboBasicAlkaline => 250,
        PlanTier.comboStandardAlkaline => 316,
        PlanTier.comboPremiumAlkaline => 416,
      },
    BillingPeriod.weekly => switch (tier) {
        PlanTier.basic => 443,
        PlanTier.standard => 653,
        PlanTier.premium => 933,
        PlanTier.alkalineInfusedWater1L => 443,
        PlanTier.comboBasicAlkaline => 749,
        PlanTier.comboStandardAlkaline => 949,
        PlanTier.comboPremiumAlkaline => 1249,
      },
    BillingPeriod.monthly => switch (tier) {
        PlanTier.basic => 1699,
        PlanTier.standard => 2599,
        PlanTier.premium => 3399,
        PlanTier.alkalineInfusedWater1L => 1699,
        PlanTier.comboBasicAlkaline => 2699,
        PlanTier.comboStandardAlkaline => 3599,
        PlanTier.comboPremiumAlkaline => 4399,
      },
  };
}
