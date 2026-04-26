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
    this.strictDeliveryTime = false,
    this.active = true,
    this.notes = '',
    this.assignedDeliveryAgentUsername,
    this.skippedDeliveryDays = 0,
    this.skippedDeliveryDates = const [],
    this.paymentTrackedPeriodStart,
    this.weeklyPeriodPaid = false,
    this.monthlyAdvancePaid = false,
    this.monthlyBalancePaid = false,
    this.lastPaymentAmountRupees,
    this.lastPaymentAt,
    this.lastPaymentKind,
    this.pendingDueKind,
    this.pendingDueRemainingRupees,
    this.customerCreated = true,
    this.adminApproved = false,
    this.secondaryPlanTier,
    this.secondaryPlanPriceRupees = 0,
    this.deletedAt,
  });

  /// How long a soft-deleted customer doc is kept before [AppRepository] purges it.
  static const Duration softDeleteRetention = Duration(days: 30);

  final String id;
  final String name;
  final String phone;
  final String address;
  final DeliverySlot preferredSlot;
  final PlanTier planTier;
  final BillingPeriod billingPeriod;
  /// Snapshot price at signup (rupees).
  final int planPriceRupees;
  /// Optional second product on the same billing period (e.g. fruit + alkaline).
  final PlanTier? secondaryPlanTier;
  /// Per-period rupees for [secondaryPlanTier]; must be > 0 when tier is set.
  final int secondaryPlanPriceRupees;
  final DateTime startDate;
  final DateTime endDate;
  /// Preferred time window within the slot (e.g. "8–10 AM"), free text.
  final String requestedDeliveryTime;
  /// Customer expects delivery within the requested window (highlight in UI).
  final bool strictDeliveryTime;
  final bool active;
  final String notes;
  final String? assignedDeliveryAgentUsername;
  final int skippedDeliveryDays;
  final List<DateTime> skippedDeliveryDates;

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
  final bool customerCreated;
  final bool adminApproved;

  /// When set, the customer is hidden from routes and normal lists until restored
  /// or [softDeleteRetention] elapses (then the doc is removed from Firestore).
  final DateTime? deletedAt;

  /// Combined period price for payments, receipts, and due calculations.
  int get totalPlanPriceRupees =>
      planPriceRupees +
      (secondaryPlanTier != null ? secondaryPlanPriceRupees : 0);

  bool get isSoftDeleted => deletedAt != null;

  /// True while [asOf] is still before the auto-purge time (exclusive of purged docs).
  bool isSoftDeleteRecoverable(DateTime asOf) {
    if (deletedAt == null) return false;
    return asOf.isBefore(deletedAt!.add(softDeleteRetention));
  }

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
    bool? strictDeliveryTime,
    bool? active,
    String? notes,
    String? assignedDeliveryAgentUsername,
    int? skippedDeliveryDays,
    List<DateTime>? skippedDeliveryDates,
    DateTime? paymentTrackedPeriodStart,
    bool? weeklyPeriodPaid,
    bool? monthlyAdvancePaid,
    bool? monthlyBalancePaid,
    int? lastPaymentAmountRupees,
    DateTime? lastPaymentAt,
    String? lastPaymentKind,
    String? pendingDueKind,
    int? pendingDueRemainingRupees,
    bool? customerCreated,
    bool? adminApproved,
    PlanTier? secondaryPlanTier,
    int? secondaryPlanPriceRupees,
    bool clearPendingDue = false,
    bool clearAssignedDeliveryAgent = false,
    bool clearSecondaryPlan = false,
    bool clearLastPayment = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
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
      strictDeliveryTime: strictDeliveryTime ?? this.strictDeliveryTime,
      active: active ?? this.active,
      notes: notes ?? this.notes,
      assignedDeliveryAgentUsername: clearAssignedDeliveryAgent
          ? null
          : (assignedDeliveryAgentUsername ??
              this.assignedDeliveryAgentUsername),
      skippedDeliveryDays: skippedDeliveryDays ?? this.skippedDeliveryDays,
      skippedDeliveryDates:
          skippedDeliveryDates ?? this.skippedDeliveryDates,
      paymentTrackedPeriodStart:
          paymentTrackedPeriodStart ?? this.paymentTrackedPeriodStart,
      weeklyPeriodPaid: weeklyPeriodPaid ?? this.weeklyPeriodPaid,
      monthlyAdvancePaid: monthlyAdvancePaid ?? this.monthlyAdvancePaid,
      monthlyBalancePaid: monthlyBalancePaid ?? this.monthlyBalancePaid,
      lastPaymentAmountRupees: clearLastPayment
          ? null
          : (lastPaymentAmountRupees ?? this.lastPaymentAmountRupees),
      lastPaymentAt:
          clearLastPayment ? null : (lastPaymentAt ?? this.lastPaymentAt),
      lastPaymentKind:
          clearLastPayment ? null : (lastPaymentKind ?? this.lastPaymentKind),
      pendingDueKind:
          clearPendingDue ? null : (pendingDueKind ?? this.pendingDueKind),
      pendingDueRemainingRupees: clearPendingDue
          ? null
          : (pendingDueRemainingRupees ?? this.pendingDueRemainingRupees),
      customerCreated: customerCreated ?? this.customerCreated,
      adminApproved: adminApproved ?? this.adminApproved,
      secondaryPlanTier: clearSecondaryPlan
          ? null
          : (secondaryPlanTier ?? this.secondaryPlanTier),
      secondaryPlanPriceRupees: clearSecondaryPlan
          ? 0
          : (secondaryPlanPriceRupees ?? this.secondaryPlanPriceRupees),
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
