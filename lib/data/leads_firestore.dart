import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lead.dart';

DateTime? _parseCreatedAt(dynamic v) {
  if (v == null) return null;
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
  return null;
}

String _str(dynamic v) {
  if (v == null) return '';
  return v.toString().trim();
}

bool _bool(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

Lead leadFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();
  // Full path keeps IDs unique when using collectionGroup (e.g. users/*/leads/*).
  final uniqueId = doc.reference.path;
  if (d == null) {
    return Lead(id: uniqueId, name: '(no data)');
  }
  return Lead(
    id: uniqueId,
    billing: _str(d['billing']),
    calendar: _str(d['calendar']),
    createdAt: _parseCreatedAt(d['createdAt']),
    goal: _str(d['goal']),
    meal: _str(d['meal']),
    mealLabel: _str(d['mealLabel']),
    mobile: _str(d['mobile']),
    name: _str(d['name']),
    plan: _str(d['plan']),
    price: _str(d['price']),
    source: _str(d['source']),
    called: _bool(d['called']),
    notInterested: _bool(d['notInterested']),
  );
}

List<Lead> leadsFromQueryDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs.map((d) => leadFromFirestore(d)).toList();
}
