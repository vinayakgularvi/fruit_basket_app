import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/needed_fruit.dart';

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

double? _double(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

DateTime? _parsePurchasedAt(dynamic v) {
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

NeededFruit neededFruitFromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();
  if (d == null) {
    return NeededFruit(id: doc.id, fruitName: '(no data)', quantityNotes: '');
  }
  return NeededFruit(
    id: doc.id,
    fruitName: _str(d['fruitName']),
    quantityNotes: _str(d['quantityNotes']),
    notes: _str(d['notes']),
    purchased: _bool(d['purchased']),
    purchasedAt: _parsePurchasedAt(d['purchasedAt']),
    pricePerKgRupees: _double(d['pricePerKgRupees']),
    totalWeightKg: _double(d['totalWeightKg']),
    totalCostRupees: _double(d['totalCostRupees']),
  );
}

List<NeededFruit> neededFruitsFromQueryDocs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs.map(neededFruitFromFirestore).toList();
}
