import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/employee.dart';
import '../utils/delivery_plan_dates.dart';

DateTime _coerceDate(dynamic v, String docId, String field) {
  if (v == null) {
    debugPrint('Firestore employees/$docId: missing "$field", using today');
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }
  if (v is Timestamp) return dateOnly(v.toDate());
  if (v is DateTime) return dateOnly(v);
  if (v is String) {
    final parsed = DateTime.tryParse(v);
    if (parsed != null) return dateOnly(parsed);
  }
  if (v is int) {
    final ms = v > 100000000000 ? v : v * 1000;
    return dateOnly(DateTime.fromMillisecondsSinceEpoch(ms));
  }
  if (v is Map) {
    final sec = v['seconds'] ?? v['_seconds'];
    if (sec is num) {
      final nano = v['nanoseconds'] ?? v['_nanoseconds'] ?? 0;
      final ns = nano is num ? nano.toInt() : 0;
      return dateOnly(Timestamp(sec.toInt(), ns).toDate());
    }
  }
  debugPrint('Firestore employees/$docId: invalid "$field" ($v), using today');
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

List<DateTime> _absentDateList(dynamic v, String docId) {
  if (v == null) return [];
  if (v is! Iterable) return [];
  final out = <DateTime>[];
  for (final e in v) {
    if (e is Timestamp) {
      out.add(dateOnly(e.toDate()));
    }
  }
  out.sort((a, b) => a.compareTo(b));
  return out;
}

int _optionalInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.round();
  return fallback;
}

int _incentiveRupeesFromFirestore(Map<String, dynamic> d, int salaryRupees) {
  final direct = d['incentiveRupees'];
  if (direct != null && direct is num) {
    return direct.round();
  }
  final pct = d['incentivePercent'];
  if (pct != null && pct is num && salaryRupees > 0) {
    return (salaryRupees * pct.toDouble() / 100).round();
  }
  return 0;
}

Map<String, dynamic> employeeToFirestore(Employee e) {
  return {
    'name': e.name,
    'mobile': e.mobile,
    'address': e.address,
    'startDate': Timestamp.fromDate(
      DateTime(e.startDate.year, e.startDate.month, e.startDate.day),
    ),
    'salaryRupees': e.salaryRupees,
    'incentiveRupees': e.incentiveRupees,
    'absentDates': e.absentDates
        .map(
          (d) => Timestamp.fromDate(DateTime(d.year, d.month, d.day)),
        )
        .toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

Employee employeeFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();
  if (d == null) {
    throw StateError('Missing employee data for ${doc.id}');
  }
  final id = doc.id;
  final salary = _optionalInt(d['salaryRupees'], 0);
  return Employee(
    id: id,
    name: (d['name'] as String?)?.trim() ?? '',
    mobile: (d['mobile'] as String?)?.trim() ?? '',
    address: (d['address'] as String?)?.trim() ?? '',
    startDate: _coerceDate(d['startDate'], id, 'startDate'),
    salaryRupees: salary,
    incentiveRupees: _incentiveRupeesFromFirestore(d, salary),
    absentDates: _absentDateList(d['absentDates'], id),
  );
}
