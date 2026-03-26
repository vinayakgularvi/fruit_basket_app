import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../models/delivery_slot.dart';
import '../models/subscription_plan.dart';

/// Handles Timestamp, DateTime, ISO strings, epoch ints, and map-shaped Timestamps (web/imports).
DateTime _coerceDate(dynamic v, String docId, String field) {
  if (v == null) {
    debugPrint('Firestore customers/$docId: missing "$field", using today');
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return parsed;
  }
  if (v is int) {
    final ms = v > 100000000000 ? v : v * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  if (v is Map) {
    final sec = v['seconds'] ?? v['_seconds'];
    if (sec is num) {
      final nano = v['nanoseconds'] ?? v['_nanoseconds'] ?? 0;
      final ns = nano is num ? nano.toInt() : 0;
      return Timestamp(sec.toInt(), ns).toDate();
    }
  }
  debugPrint('Firestore customers/$docId: invalid "$field" ($v), using today');
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

Map<String, dynamic> customerToFirestore(Customer c) {
  return {
    'name': c.name,
    'phone': c.phone,
    'address': c.address,
    'preferredSlot': c.preferredSlot.name,
    'planTier': c.planTier.name,
    'billingPeriod': c.billingPeriod.name,
    'planPriceRupees': c.planPriceRupees,
    'startDate': Timestamp.fromDate(
      DateTime(c.startDate.year, c.startDate.month, c.startDate.day),
    ),
    'endDate': Timestamp.fromDate(
      DateTime(c.endDate.year, c.endDate.month, c.endDate.day),
    ),
    'requestedDeliveryTime': c.requestedDeliveryTime,
    'active': c.active,
    'notes': c.notes,
    'assignedDeliveryAgentUsername': c.assignedDeliveryAgentUsername,
    'paymentTrackedPeriodStart': c.paymentTrackedPeriodStart == null
        ? null
        : Timestamp.fromDate(
            DateTime(
              c.paymentTrackedPeriodStart!.year,
              c.paymentTrackedPeriodStart!.month,
              c.paymentTrackedPeriodStart!.day,
            ),
          ),
    'weeklyPeriodPaid': c.weeklyPeriodPaid,
    'monthlyAdvancePaid': c.monthlyAdvancePaid,
    'monthlyBalancePaid': c.monthlyBalancePaid,
    'lastPaymentAmountRupees': c.lastPaymentAmountRupees,
    'lastPaymentAt': c.lastPaymentAt == null
        ? null
        : Timestamp.fromDate(c.lastPaymentAt!),
    'lastPaymentKind': c.lastPaymentKind,
    'pendingDueKind': c.pendingDueKind,
    'pendingDueRemainingRupees': c.pendingDueRemainingRupees,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

Customer customerFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();
  if (d == null) {
    throw StateError('Missing customer data for ${doc.id}');
  }

  final id = doc.id;

  DeliverySlot slot(String? name) => DeliverySlot.values.firstWhere(
        (e) => e.name == name,
        orElse: () => DeliverySlot.morning,
      );

  PlanTier tier(String? name) => PlanTier.values.firstWhere(
        (e) => e.name == name,
        orElse: () => PlanTier.basic,
      );

  BillingPeriod period(String? name) => BillingPeriod.values.firstWhere(
        (e) => e.name == name,
        orElse: () => BillingPeriod.monthly,
      );

  final sd = _coerceDate(d['startDate'], id, 'startDate');
  final ed = _coerceDate(d['endDate'], id, 'endDate');

  final price = d['planPriceRupees'];
  final planPriceRupees = price is num
      ? price.toInt()
      : int.tryParse(price?.toString() ?? '') ?? 0;

  return Customer(
    id: id,
    name: d['name'] as String? ?? '',
    phone: d['phone'] as String? ?? '',
    address: d['address'] as String? ?? '',
    preferredSlot: slot(d['preferredSlot'] as String?),
    planTier: tier(d['planTier'] as String?),
    billingPeriod: period(d['billingPeriod'] as String?),
    planPriceRupees: planPriceRupees,
    startDate: DateTime(sd.year, sd.month, sd.day),
    endDate: DateTime(ed.year, ed.month, ed.day),
    requestedDeliveryTime: _coerceString(d['requestedDeliveryTime']),
    active: _coerceBool(d['active']),
    notes: d['notes'] as String? ?? '',
    assignedDeliveryAgentUsername:
        _optionalString(d['assignedDeliveryAgentUsername']),
    paymentTrackedPeriodStart:
        _optionalDateOnly(d['paymentTrackedPeriodStart'], id),
    weeklyPeriodPaid: d['weeklyPeriodPaid'] as bool? ?? false,
    monthlyAdvancePaid: d['monthlyAdvancePaid'] as bool? ?? false,
    monthlyBalancePaid: d['monthlyBalancePaid'] as bool? ?? false,
    lastPaymentAmountRupees: _optionalInt(d['lastPaymentAmountRupees']),
    lastPaymentAt: d['lastPaymentAt'] == null
        ? null
        : _coerceDate(d['lastPaymentAt'], id, 'lastPaymentAt'),
    lastPaymentKind: d['lastPaymentKind'] as String?,
    pendingDueKind: d['pendingDueKind'] as String?,
    pendingDueRemainingRupees: _optionalInt(d['pendingDueRemainingRupees']),
  );
}

int? _optionalInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _optionalString(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

DateTime? _optionalDateOnly(dynamic v, String docId) {
  if (v == null) return null;
  final dt = _coerceDate(v, docId, 'paymentTrackedPeriodStart');
  return DateTime(dt.year, dt.month, dt.day);
}

String _coerceString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString().trim();
}

bool _coerceBool(dynamic v) {
  if (v == null) return true;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) {
    final t = v.toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return true;
}

/// Parses each doc; skips and logs any document that still fails to parse.
List<Customer> customersFromQueryDocs(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final out = <Customer>[];
  for (final doc in docs) {
    try {
      out.add(customerFromFirestore(doc));
    } catch (e, st) {
      debugPrint('Firestore customers/${doc.id}: skipped — $e\n$st');
    }
  }
  return out;
}
