import 'delivery_slot.dart';
import 'subscription_plan.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.preferredSlot,
    required this.planTier,
    required this.billingPeriod,
    required this.planPriceRupees,
    required this.startDate,
    required this.endDate,
    this.requestedDeliveryTime = '',
    this.active = true,
    this.notes = '',
    this.paymentTrackedPeriodStart,
    this.weeklyPeriodPaid = false,
    this.monthlyAdvancePaid = false,
    this.monthlyBalancePaid = false,
    this.lastPaymentAmountRupees,
    this.lastPaymentAt,
    this.lastPaymentKind,
    this.pendingDueKind,
    this.pendingDueRemainingRupees,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final DeliverySlot preferredSlot;
  final PlanTier planTier;
  final BillingPeriod billingPeriod;
  /// Snapshot price at signup (rupees).
  final int planPriceRupees;
  final DateTime startDate;
  final DateTime endDate;
  /// Preferred time window within the slot (e.g. "8–10 AM"), free text.
  final String requestedDeliveryTime;
  final bool active;
  final String notes;

  /// First day of the billing period for which [weeklyPeriodPaid] / monthly flags apply.
  final DateTime? paymentTrackedPeriodStart;
  final bool weeklyPeriodPaid;
  final bool monthlyAdvancePaid;
  final bool monthlyBalancePaid;

  /// Rupees actually collected when [weeklyPeriodPaid] / monthly flags were last set.
  final int? lastPaymentAmountRupees;
  final DateTime? lastPaymentAt;
  /// [PaymentCollectionKind.name] for the last collection, if any.
  final String? lastPaymentKind;

  /// When a collection was short, the slot still owed (same period as [paymentTrackedPeriodStart]).
  final String? pendingDueKind;
  final int? pendingDueRemainingRupees;

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    DeliverySlot? preferredSlot,
    PlanTier? planTier,
    BillingPeriod? billingPeriod,
    int? planPriceRupees,
    DateTime? startDate,
    DateTime? endDate,
    String? requestedDeliveryTime,
    bool? active,
    String? notes,
    DateTime? paymentTrackedPeriodStart,
    bool? weeklyPeriodPaid,
    bool? monthlyAdvancePaid,
    bool? monthlyBalancePaid,
    int? lastPaymentAmountRupees,
    DateTime? lastPaymentAt,
    String? lastPaymentKind,
    String? pendingDueKind,
    int? pendingDueRemainingRupees,
    bool clearPendingDue = false,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      preferredSlot: preferredSlot ?? this.preferredSlot,
      planTier: planTier ?? this.planTier,
      billingPeriod: billingPeriod ?? this.billingPeriod,
      planPriceRupees: planPriceRupees ?? this.planPriceRupees,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      requestedDeliveryTime:
          requestedDeliveryTime ?? this.requestedDeliveryTime,
      active: active ?? this.active,
      notes: notes ?? this.notes,
      paymentTrackedPeriodStart:
          paymentTrackedPeriodStart ?? this.paymentTrackedPeriodStart,
      weeklyPeriodPaid: weeklyPeriodPaid ?? this.weeklyPeriodPaid,
      monthlyAdvancePaid: monthlyAdvancePaid ?? this.monthlyAdvancePaid,
      monthlyBalancePaid: monthlyBalancePaid ?? this.monthlyBalancePaid,
      lastPaymentAmountRupees:
          lastPaymentAmountRupees ?? this.lastPaymentAmountRupees,
      lastPaymentAt: lastPaymentAt ?? this.lastPaymentAt,
      lastPaymentKind: lastPaymentKind ?? this.lastPaymentKind,
      pendingDueKind:
          clearPendingDue ? null : (pendingDueKind ?? this.pendingDueKind),
      pendingDueRemainingRupees: clearPendingDue
          ? null
          : (pendingDueRemainingRupees ?? this.pendingDueRemainingRupees),
    );
  }
}
